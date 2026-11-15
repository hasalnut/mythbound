-- Wild creatures: a low-poly body welded to a Humanoid root, driven by a small state machine.
--
-- Wander -> (player in aggro range, or hit) -> Chase -> Windup (glows red) -> bite -> Recover -> Chase ...
-- Too far from home -> Return (heals on the way) -> Wander.  Health 0 -> Dead (fades, respawns later).
-- In co-op a chasing creature switches to another player who is clearly closer, and when its
-- target dies a hostile creature turns on whoever else is near instead of going home.
--
-- Passive creatures (foxes) never fight: Wander -> (a player comes close, or something sudden
-- happens nearby) -> Flee -> Return. A player carrying food the creature likes doesn't scare it
-- (the calm check, set by Taming). While it is being fed it stands still (Held).
-- A creature that is tamed leaves through Creature.remove: no XP, loot or quest credit.
-- A companion's bite counts for its owner, and can bring the creature onto the companion.
--
-- The body comes from ServerStorage.Assets.<id> if a replacement model is there (see Assets.luau),
-- otherwise it is built from grey parts.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Build = require(script.Parent:WaitForChild("Build"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local Creature = {}
Creature.__index = Creature

local PACK_RADIUS = 50
local THINK_INTERVAL = 0.1
local RETARGET_INTERVAL = 1 -- how often a chasing creature checks for a closer player
local RETARGET_MARGIN = 12 -- another player must be this many studs closer before it switches
local FALL_LIMIT = -60 -- below this height a creature has fallen out of the world
local SPAWN_TRIES = 10
local SETTLE_TIME = 1.5 -- new creatures are held still this long: freshly made terrain needs a moment
-- before its collision is solid, and anything dropped on it straight away falls through
local FALLEN_RESPAWN = 3 -- seconds before a creature that fell out of the world is replaced
local MAX_SPAWN_SLOPE = 2.5 -- studs of ground height difference allowed under a new creature
local RESPAWN_CLEARANCE = 60 -- creatures don't (re)appear this close to a player (wolves notice at 55)
local RESPAWN_RETRY = 2 -- seconds before trying again when players are standing on the spawn area
local FLEE_STEP = 20 -- how far ahead a fleeing creature aims each think
local FLEE_SAFE = 1.6 -- it keeps running until players are this many times its flee range away
local FLEE_TURNS = { 0, 50, -50, 100, -100, 150, -150 } -- degrees to try when the way ahead is blocked
local FLEE_MAX_RISE = 5 -- studs of climb or drop over one flee step that count as blocked (hills, the pond)

local all: { any } = {}
local byModel: { [Model]: any } = {}
local defeatListeners: { (CreatureData.CreatureInfo, { Player }, Vector3) -> () } = {}
local spawnListeners: { (any) -> () } = {}
local calmCheck: ((any, Player) -> boolean)? = nil
local folder: Folder? = nil

local function getFolder(): Folder
	if not folder then
		folder = Build.folder("Creatures", workspace)
	end
	return folder :: Folder
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Builds the grey body from parts. The front of every creature is -Z, like all Roblox models.
-- Returns the model, its Humanoid and root, and the HitRadius and HitHeight to use.
local function buildGreyBody(data: CreatureData.CreatureInfo, position: Vector3): (Model, Humanoid, BasePart, number, number)
	local s = data.scale
	local legLength = 1.6 * s
	local bodyHeight = 1.9 * s
	local bodyLength = 4.2 * s
	local bodyWidth = 1.8 * s
	local bodyY = legLength + bodyHeight / 2

	local model = Instance.new("Model")
	model.Name = data.name

	local base = CFrame.new(position + Vector3.new(0, bodyY, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local root = Build.part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(bodyWidth, bodyHeight, bodyLength),
		CFrame = base,
		Transparency = 1,
		Anchored = false,
		CanCollide = true,
		Parent = model,
	})

	local function add(name: string, size: Vector3, offset: Vector3, color: Color3, rotation: CFrame?)
		local part = Build.part({
			Name = name,
			Size = size,
			CFrame = base * CFrame.new(offset) * (rotation or CFrame.identity),
			Color = color,
			Parent = model,
		})
		Build.weld(part, root)
		return part
	end

	local front = -bodyLength / 2
	add("Body", Vector3.new(bodyWidth, bodyHeight, bodyLength), Vector3.zero, data.color)
	add("Head", Vector3.new(1.5 * s, 1.5 * s, 1.7 * s), Vector3.new(0, 0.7 * s, front - 0.6 * s), data.color)
	add("Snout", Vector3.new(0.8 * s, 0.7 * s, 1.0 * s), Vector3.new(0, 0.4 * s, front - 1.8 * s), data.accent)
	add("Nose", Vector3.new(0.35 * s, 0.3 * s, 0.2 * s), Vector3.new(0, 0.65 * s, front - 2.3 * s), Color3.fromRGB(30, 28, 28))
	for _, side in { -1, 1 } do
		add("Eye", Vector3.new(0.22 * s, 0.22 * s, 0.1 * s), Vector3.new(side * 0.42 * s, 1.0 * s, front - 1.42 * s), Color3.fromRGB(25, 20, 20))
		add("Leg", Vector3.new(0.5 * s, legLength, 0.5 * s), Vector3.new(side * bodyWidth * 0.32, -bodyHeight / 2 - legLength / 2 + 0.1, front * 0.7), data.color)
		add("Leg", Vector3.new(0.5 * s, legLength, 0.5 * s), Vector3.new(side * bodyWidth * 0.32, -bodyHeight / 2 - legLength / 2 + 0.1, -front * 0.7), data.color)
		if data.id == "wolf" or data.id == "fox" then
			add("Ear", Vector3.new(0.4 * s, 0.7 * s, 0.25 * s), Vector3.new(side * 0.45 * s, 1.75 * s, front - 0.4 * s), data.color)
		elseif data.id == "boar" then
			add("Tusk", Vector3.new(0.15 * s, 0.45 * s, 0.15 * s), Vector3.new(side * 0.42 * s, 0.25 * s, front - 2.1 * s), data.accent)
		end
	end
	if data.id == "wolf" then
		add("Tail", Vector3.new(0.45 * s, 0.45 * s, 1.8 * s), Vector3.new(0, 0.35 * s, -front + 0.7 * s), data.accent, CFrame.Angles(math.rad(25), 0, 0))
		add("Chest", Vector3.new(bodyWidth * 0.9, bodyHeight * 0.7, 0.3 * s), Vector3.new(0, -0.1 * s, front - 0.05), data.accent)
	elseif data.id == "fox" then
		-- A bushy tail held up, with a pale tip.
		local lift = CFrame.Angles(math.rad(-25), 0, 0)
		add("Tail", Vector3.new(0.75 * s, 0.75 * s, 2.2 * s), Vector3.new(0, 0.5 * s, -front + 0.9 * s), data.color, lift)
		add("TailTip", Vector3.new(0.65 * s, 0.65 * s, 0.8 * s), Vector3.new(0, 1.1 * s, -front + 2.2 * s), data.accent, lift)
		add("Chest", Vector3.new(bodyWidth * 0.9, bodyHeight * 0.7, 0.3 * s), Vector3.new(0, -0.1 * s, front - 0.05), data.accent)
	else
		add("Tail", Vector3.new(0.2 * s, 0.2 * s, 0.6 * s), Vector3.new(0, 0.4 * s, -front + 0.25 * s), data.color)
		add("Mane", Vector3.new(0.5 * s, 0.4 * s, bodyLength * 0.7), Vector3.new(0, bodyHeight / 2 + 0.15 * s, 0), Color3.fromRGB(60, 42, 30))
	end

	local humanoid = Instance.new("Humanoid")
	-- R15 makes the Humanoid hold the root at HipHeight above the ground, which custom bodies need.
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = legLength
	humanoid.Parent = model
	model.PrimaryPart = root
	return model, humanoid, root, math.max(bodyWidth, bodyLength) * 0.45, bodyHeight / 2 + 1.6 * s
end

-- A copy of the replacement model ServerStorage.Assets.<id>, standing on `position`, or nil.
local function buildFromAsset(data: CreatureData.CreatureInfo, position: Vector3): (Model?, Humanoid?, BasePart?, number, number)
	local template = Assets.find(data.id)
	if not template then
		return nil, nil, nil, 0, 0
	end
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		warn(`[Creature] ServerStorage.Assets model "{data.id}" needs a HumanoidRootPart and a Humanoid; using the grey body instead.`)
		model:Destroy()
		return nil, nil, nil, 0, 0
	end
	model.Name = data.name
	model.PrimaryPart = root
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	-- Stand it on the ground with the root held at HipHeight, facing a random way.
	local rootY = position.Y + humanoid.HipHeight + root.Size.Y / 2
	local target = CFrame.new(position.X, rootY, position.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	model:PivotTo(target * root.CFrame:ToObjectSpace(model:GetPivot()))
	local box, size = model:GetBoundingBox()
	local top = box.Position.Y + size.Y / 2 - root.Position.Y
	return model, humanoid, root, math.max(size.X, size.Z) * 0.45, top + 0.5
end

-- Builds a creature's body under `parent`: the replacement model if there is one, otherwise the
-- grey body. `wild` ones are tagged Damageable, so players can attack and lock on to them;
-- companions (Companions.luau) are built with `wild` false and can't be hit by players.
-- The root starts anchored: whoever owns the body releases it once the ground is solid.
function Creature.buildBody(data: CreatureData.CreatureInfo, position: Vector3, parent: Instance, wild: boolean): (Model, Humanoid, BasePart)
	local model: Model, humanoid: Humanoid, root: BasePart, hitRadius: number, hitHeight: number
	local assetModel, assetHumanoid, assetRoot, assetRadius, assetHeight = buildFromAsset(data, position)
	if assetModel and assetHumanoid and assetRoot then
		model, humanoid, root, hitRadius, hitHeight = assetModel, assetHumanoid, assetRoot, assetRadius, assetHeight
	else
		model, humanoid, root, hitRadius, hitHeight = buildGreyBody(data, position)
	end

	humanoid.MaxHealth = data.maxHealth
	humanoid.Health = data.maxHealth
	humanoid.WalkSpeed = data.walkSpeed
	humanoid.DisplayName = data.name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	model:SetAttribute("CreatureId", data.id)
	model:SetAttribute("HitRadius", hitRadius)
	model:SetAttribute("HitHeight", hitHeight)
	model:SetAttribute("Hostile", wild and data.behaviour == "Hostile")
	model:SetAttribute("Void", data.isVoid)
	if wild then
		CollectionService:AddTag(model, Config.TAG_DAMAGEABLE)
	end
	root.Anchored = true -- released by think() once SETTLE_TIME has passed
	model.Parent = parent
	return model, humanoid, root
end

export type Creature = typeof(setmetatable(
	{} :: {
		data: CreatureData.CreatureInfo,
		home: Vector3,
		state: string,
		timer: number,
		nextAttack: number,
		retargetAt: number,
		target: Model?,
		lastAttacker: Player?,
		damagers: { [Player]: boolean }, -- everyone who hit it; they share XP and quest credit
		wanderPoint: Vector3,
		model: Model,
		humanoid: Humanoid,
		root: BasePart,
		warning: Highlight,
		settleUntil: number?,
		stunnedUntil: number, -- Shield Slam, Frost Nova
		tauntedUntil: number, -- Taunt: keeps its target and won't switch
		fleeFrom: Vector3, -- what a fleeing creature is running from
		fleeUntil: number,
		holder: Model?, -- the character feeding it (Held)
		onDespawn: ((reason: string) -> ())?,
	},
	Creature
))

-- `onDespawn(reason)` runs when the body has been removed. `reason` is "defeated", "fell" (out of
-- the world) or "tamed".
function Creature.spawn(data: CreatureData.CreatureInfo, position: Vector3, onDespawn: ((reason: string) -> ())?): Creature
	local model, humanoid, root = Creature.buildBody(data, position, getFolder(), true)
	local warning = Instance.new("Highlight")
	warning.Name = "WindupWarning"
	warning.FillColor = Color3.fromRGB(255, 40, 30)
	warning.FillTransparency = 0.35
	warning.OutlineColor = Color3.fromRGB(255, 90, 60)
	warning.OutlineTransparency = 0.2
	warning.Enabled = false
	warning.Parent = model

	local self = setmetatable({
		data = data,
		home = position,
		state = "Wander",
		timer = 0,
		nextAttack = 0,
		retargetAt = 0,
		target = nil,
		lastAttacker = nil,
		damagers = {},
		wanderPoint = position,
		model = model,
		humanoid = humanoid,
		root = root,
		warning = warning,
		settleUntil = os.clock() + SETTLE_TIME,
		stunnedUntil = 0,
		tauntedUntil = 0,
		fleeFrom = position,
		fleeUntil = 0,
		holder = nil,
		onDespawn = onDespawn,
	}, Creature)

	Combat.onHit(model, function(source, via)
		self:provoke(source, via)
	end)
	humanoid.Died:Connect(function()
		self:die()
	end)
	table.insert(all, self)
	byModel[model] = self
	for _, listener in spawnListeners do
		task.spawn(listener, self)
	end
	return self
end

-- Runs `listener(creature)` for every creature spawned from now on (Taming adds feed prompts).
function Creature.onSpawned(listener: (any) -> ())
	table.insert(spawnListeners, listener)
end

-- `check(creature, player)` returns true when `player` doesn't scare a passive `creature`
-- (Taming: they carry food it likes).
function Creature.setCalmCheck(check: (any, Player) -> boolean)
	calmCheck = check
end

-- The living wild creature closest to `position` within `radius` that `accept` says yes to.
function Creature.nearest(position: Vector3, radius: number, accept: (any) -> boolean): Creature?
	local best: Creature? = nil
	local bestDistance = radius
	for _, creature in all do
		if creature.state ~= "Dead" then
			local distance = (creature.root.Position - position).Magnitude
			if distance <= bestDistance and accept(creature) then
				best = creature
				bestDistance = distance
			end
		end
	end
	return best
end

-- The creature object for a model, if it is one.
function Creature.find(model: Model): Creature?
	return byModel[model]
end

-- Stops it in place for `seconds`, tinted `color` (blue for frozen, white for stunned).
function Creature.stun(self: Creature, seconds: number, color: Color3)
	if self.state == "Dead" then
		return
	end
	local untilTime = os.clock() + seconds
	if untilTime <= self.stunnedUntil then
		return
	end
	self.stunnedUntil = untilTime
	self.warning.Enabled = false
	self.humanoid:MoveTo(self.root.Position)
	local tint = self.model:FindFirstChild("StunTint") :: Highlight?
	if not tint then
		local highlight = Instance.new("Highlight")
		highlight.Name = "StunTint"
		highlight.FillTransparency = 0.45
		highlight.OutlineTransparency = 0.3
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = self.model
		tint = highlight
	end
	(tint :: Highlight).FillColor = color;
	(tint :: Highlight).OutlineColor = color
	task.delay(seconds, function()
		if os.clock() >= self.stunnedUntil - 0.01 and tint and tint.Parent then
			tint:Destroy()
		end
	end)
end

-- Shoves it `distance` studs along `direction`, stopping short of anything solid.
function Creature.knockback(self: Creature, direction: Vector3, distance: number)
	if self.state == "Dead" or self.root.Anchored then
		return
	end
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		return
	end
	flatDirection = flatDirection.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model }
	local hit = workspace:Raycast(self.root.Position, flatDirection * distance, params)
	local travel = if hit then math.max(0, (hit.Position - self.root.Position).Magnitude - 2) else distance
	self.model:PivotTo(self.model:GetPivot() + flatDirection * travel)
end

-- Tank Taunt: every creature within `radius` of `position` turns on `character` for `seconds`.
function Creature.taunt(character: Model, position: Vector3, radius: number, seconds: number): number
	local count = 0
	local now = os.clock()
	for _, creature in all do
		if creature.state ~= "Dead" and (creature.root.Position - position).Magnitude <= radius then
			creature:setTarget(character)
			creature.tauntedUntil = now + seconds
			count += 1
		end
	end
	return count
end

function Creature.setTarget(self: Creature, character: Model)
	self.target = character
	self.state = "Chase"
end

-- How far away this creature notices `player`. Ninjas move quietly and are noticed at half range.
function Creature.noticeRange(self: Creature, player: Player): number
	local range = self.data.aggroRange
	if player:GetAttribute("Class") == "ninja" then
		range *= 0.5
	end
	return range
end

-- The living player character closest to this creature, and how far away it is. With
-- `noticing`, only players inside the notice range count; otherwise those within `maxDistance`.
function Creature.nearestPlayer(self: Creature, noticing: boolean, maxDistance: number?): (Model?, number)
	local best: Model? = nil
	local bestDistance = math.huge
	local position = self.root.Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and Combat.isAlive(character) and not character:GetAttribute("Vanished") then
			local root = Combat.rootOf(character)
			if root then
				local distance = (root.Position - position).Magnitude
				local limit = if noticing then self:noticeRange(player) else (maxDistance or math.huge)
				if distance < limit and distance < bestDistance then
					best = character
					bestDistance = distance
				end
			end
		end
	end
	return best, bestDistance
end

-- Pack animals (wolves) join the fight. Each goes for the player closest to itself, so in co-op
-- a pack spreads out between players who stand apart and gangs up on players who stand together.
function Creature.alertPack(self: Creature, character: Model)
	if not self.data.pack then
		return
	end
	for _, other in all do
		if other ~= self and other.data.id == self.data.id and other.state == "Wander"
			and (other.root.Position - self.root.Position).Magnitude < PACK_RADIUS then
			local nearest = other:nearestPlayer(false, other.data.aggroRange * 1.5)
			other:setTarget(nearest or character)
		end
	end
end

-- `source` is the player who gets the credit. `via` is their companion when it did the biting:
-- the creature then goes for the companion rather than the player.
function Creature.provoke(self: Creature, source: Instance?, via: Model?)
	if self.state == "Dead" then
		return
	end
	if source and source:IsA("Player") then
		self.lastAttacker = source
		self.damagers[source] = true
		local attacker = via or source.Character
		if not attacker or not Combat.isAlive(attacker) then
			return
		end
		if self.data.behaviour == "Passive" then
			local attackerRoot = Combat.rootOf(attacker)
			if attackerRoot then
				self:flee(attackerRoot.Position, 4)
			end
		elseif self.state == "Wander" or self.state == "Return" then
			self:setTarget(attacker)
			self:alertPack(attacker)
		elseif via and self.target ~= via and (self.state == "Chase" or self.state == "Recover")
			and os.clock() >= self.tauntedUntil and math.random() < 0.5 then
			self.target = via -- sometimes turns on the companion that bit it
		end
	end
end

-- For passive creatures: the nearest player close enough to scare it, or nil. Players the calm
-- check vouches for (they carry food it likes) and vanished Ninjas don't count.
function Creature.nearestThreat(self: Creature, rangeScale: number?): Model?
	local range = self.data.fleeRange
	if not range then
		return nil
	end
	local best: Model? = nil
	local bestDistance = range * (rangeScale or 1)
	local position = self.root.Position
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and Combat.isAlive(character) and not character:GetAttribute("Vanished") then
			local root = Combat.rootOf(character)
			if root then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance and not (calmCheck and calmCheck(self, player)) then
					best = character
					bestDistance = distance
				end
			end
		end
	end
	return best
end

-- Runs away from `from` for at least `seconds`.
function Creature.flee(self: Creature, from: Vector3, seconds: number)
	if self.state == "Dead" then
		return
	end
	self.fleeFrom = from
	self.fleeUntil = math.max(self.fleeUntil, os.clock() + seconds)
	self.target = nil
	self.holder = nil
	self.warning.Enabled = false
	self.state = "Flee"
end

-- Something sudden happened at `position` (a dash, an attack, a skill): passive creatures
-- within `radius` bolt, even from a player carrying food.
function Creature.startle(position: Vector3, radius: number)
	for _, creature in all do
		if creature.data.behaviour == "Passive" and creature.state ~= "Dead"
			and (creature.root.Position - position).Magnitude <= radius then
			creature:flee(position, 3)
		end
	end
end

-- Stands still facing `character` while it is being fed (Taming). `unhold` lets it wander again.
function Creature.hold(self: Creature, character: Model)
	if self.state == "Dead" then
		return
	end
	self.holder = character
	self.target = nil
	self.state = "Held"
	self.humanoid:MoveTo(self.root.Position)
end

function Creature.unhold(self: Creature)
	if self.state == "Held" then
		self.holder = nil
		self.state = "Wander"
		self.timer = 1
	end
end

function Creature.lookForTarget(self: Creature)
	if self.data.behaviour ~= "Hostile" then
		return
	end
	local character = self:nearestPlayer(true)
	if character then
		self:setTarget(character)
		self:alertPack(character)
	end
end

function Creature.targetRoot(self: Creature): BasePart?
	local target = self.target
	-- A vanished Ninja can't be followed, and a knocked-out companion is left alone.
	if target and Combat.isAlive(target) and not target:GetAttribute("Vanished") and not target:GetAttribute("KnockedOut") then
		return Combat.rootOf(target)
	end
	return nil
end

function Creature.loseTarget(self: Creature)
	self.target = nil
	self.warning.Enabled = false
	self.state = "Return"
end

function Creature.faceTowards(self: Creature, position: Vector3)
	local from = self.root.Position
	local flatTarget = Vector3.new(position.X, from.Y, position.Z)
	if (flatTarget - from).Magnitude > 0.1 then
		self.root.CFrame = CFrame.lookAt(from, flatTarget)
	end
end

function Creature.think(self: Creature, dt: number)
	local state = self.state
	if state == "Dead" then
		return
	end
	local settleUntil = self.settleUntil
	if settleUntil then
		if os.clock() < settleUntil then
			return
		end
		self.settleUntil = nil
		self.root.Anchored = false
		self.root:SetNetworkOwner(nil) -- the server moves creatures
	end
	if not self.root.Parent or self.root.Position.Y < FALL_LIMIT then
		self:die(true) -- flung or fell out of the world: remove it so the spawner replaces it
		return
	end
	local now = os.clock()
	local position = self.root.Position

	if now < self.stunnedUntil then
		self.humanoid:MoveTo(position)
		if state == "Windup" then
			self.warning.Enabled = false -- a stun cancels the bite
			self.state = "Chase"
		end
		return
	end

	if self.data.fleeRange and (state == "Wander" or state == "Return") then
		local threat = self:nearestThreat()
		local threatRoot = threat and Combat.rootOf(threat)
		if threatRoot then
			self:flee(threatRoot.Position, 2)
			return
		end
	end

	if state == "Flee" then
		local threat = self:nearestThreat(FLEE_SAFE)
		local threatRoot = threat and Combat.rootOf(threat)
		if threatRoot then
			self.fleeFrom = threatRoot.Position
			self.fleeUntil = math.max(self.fleeUntil, now + 1)
		end
		if now >= self.fleeUntil then
			-- Safe: stop and catch its breath, then wander as before.
			self.state = "Wander"
			self.timer = 2 + math.random() * 2
			self.humanoid:MoveTo(position)
			return
		end
		local away = Vector3.new(position.X - self.fleeFrom.X, 0, position.Z - self.fleeFrom.Z)
		if away.Magnitude < 0.5 then
			local angle = math.random() * math.pi * 2
			away = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		away = away.Unit
		-- Stay inside the map, within reach of home and off steep ground (the hills around the
		-- map slow a creature to a crawl): when the way ahead is blocked, turn and run along
		-- the edge instead of stopping there.
		local edge = Config.MAP_HALF - 20
		local goal = position + away * FLEE_STEP
		local groundHere = Build.groundY(position.X, position.Z)
		for _, degrees in FLEE_TURNS do
			local direction = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(away)
			local candidate = position + direction * FLEE_STEP
			if math.abs(candidate.X) <= edge and math.abs(candidate.Z) <= edge
				and flatDistance(candidate, self.home) <= self.data.leash
				and math.abs(Build.groundY(candidate.X, candidate.Z) - groundHere) <= FLEE_MAX_RISE then
				goal = candidate
				break
			end
		end
		self.humanoid.WalkSpeed = self.data.fleeSpeed or self.data.walkSpeed
		self.humanoid:MoveTo(goal)
	elseif state == "Held" then
		local holder = self.holder
		local holderRoot = if holder and Combat.isAlive(holder) then Combat.rootOf(holder) else nil
		if not holderRoot then
			self:unhold()
			return
		end
		self.humanoid:MoveTo(position)
		self:faceTowards(holderRoot.Position)
	elseif state == "Wander" then
		self:lookForTarget()
		if self.state ~= "Wander" then
			return
		end
		if self.data.behaviour == "Passive" and self.humanoid.Health < self.humanoid.MaxHealth then
			-- Passive creatures don't walk home to heal (that could lead them back to whoever
			-- scared them); they recover slowly wherever they are.
			self.humanoid.Health = math.min(self.humanoid.MaxHealth, self.humanoid.Health + self.humanoid.MaxHealth * 0.05 * dt)
			if self.humanoid.Health >= self.humanoid.MaxHealth then
				table.clear(self.damagers)
			end
		end
		self.timer -= dt
		if self.timer <= 0 then
			self.timer = 2.5 + math.random() * 3.5
			if math.random() < 0.35 then
				self.wanderPoint = position
			else
				local angle = math.random() * math.pi * 2
				local radius = math.random() * 30
				self.wanderPoint = self.home + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			end
			self.humanoid.WalkSpeed = self.data.walkSpeed * 0.35
			self.humanoid:MoveTo(self.wanderPoint)
		end
	elseif state == "Chase" then
		if (position - self.home).Magnitude > self.data.leash then
			self:loseTarget()
			return
		end
		local targetRoot = self:targetRoot()
		if not targetRoot then
			-- The target died or left. Hostile creatures turn on whoever else is close.
			local nextTarget = if self.data.behaviour == "Hostile" then self:nearestPlayer(true) else nil
			if nextTarget then
				self.target = nextTarget
			else
				self:loseTarget()
			end
			return
		end
		if now >= self.retargetAt and now >= self.tauntedUntil then
			-- In co-op, switch to another player who is clearly closer. Neutral creatures
			-- (aggro range 0) never switch: they stay on whoever hit them.
			self.retargetAt = now + RETARGET_INTERVAL
			local closest, closestDistance = self:nearestPlayer(false, self.data.aggroRange)
			if closest and closest ~= self.target
				and closestDistance + RETARGET_MARGIN < (targetRoot.Position - position).Magnitude then
				self.target = closest
				return
			end
		end
		local distance = flatDistance(position, targetRoot.Position)
		if distance <= self.data.attackRange + 1.5 then
			self.humanoid:MoveTo(position) -- stop
			self:faceTowards(targetRoot.Position)
			if now >= self.nextAttack then
				self.state = "Windup"
				self.timer = self.data.windup
				self.warning.Enabled = true
			end
		else
			self.humanoid.WalkSpeed = self.data.walkSpeed
			self.humanoid:MoveTo(targetRoot.Position)
		end
	elseif state == "Windup" then
		local targetRoot = self:targetRoot()
		if targetRoot then
			self:faceTowards(targetRoot.Position)
		end
		self.timer -= dt
		if self.timer <= 0 then
			self.warning.Enabled = false
			-- The bite lands only if the player didn't dash or step away in time.
			if targetRoot and self.target and flatDistance(position, targetRoot.Position) <= self.data.attackRange + 3 then
				Combat.damage(self.target, self.data.damage, self.model, false)
			end
			self.nextAttack = now + self.data.attackInterval
			self.state = "Recover"
			self.timer = 0.5
		end
	elseif state == "Recover" then
		self.timer -= dt
		if self.timer <= 0 then
			self.state = "Chase"
		end
	elseif state == "Return" then
		self.humanoid.WalkSpeed = self.data.walkSpeed
		self.humanoid:MoveTo(self.home)
		self.humanoid.Health = math.min(self.humanoid.MaxHealth, self.humanoid.Health + self.humanoid.MaxHealth * 0.3 * dt)
		if flatDistance(position, self.home) < 8 then
			self.humanoid.Health = self.humanoid.MaxHealth
			table.clear(self.damagers) -- fully healed: earlier hits no longer count
			self.state = "Wander"
			self.timer = 0
		end
	end
end

-- `fell` is true when it dropped out of the world rather than being defeated.
function Creature.die(self: Creature, fell: boolean?)
	if self.state == "Dead" then
		return
	end
	self.state = "Dead"
	self.warning.Enabled = false
	CollectionService:RemoveTag(self.model, Config.TAG_DAMAGEABLE)
	local index = table.find(all, self)
	if index then
		table.remove(all, index)
	end
	byModel[self.model] = nil
	if not fell then
		local players = {}
		for player in self.damagers do
			if player.Parent then
				table.insert(players, player)
			end
		end
		for _, listener in defeatListeners do
			task.spawn(listener, self.data, players, self.root.Position)
		end
	end
	self.root.Anchored = true
	local fade = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, part in self.model:GetDescendants() do
		if part:IsA("BasePart") and part ~= self.root then
			TweenService:Create(part, fade, { Transparency = 1 }):Play()
		end
	end
	task.delay(1.2, function()
		self.model:Destroy()
		if self.onDespawn then
			self.onDespawn(if fell then "fell" else "defeated")
		end
	end)
end

-- Takes the creature out of the wild at once without a defeat: no XP, loot or quest credit.
-- Used when it is tamed (`reason` "tamed"); its body is replaced by a companion.
function Creature.remove(self: Creature, reason: string)
	if self.state == "Dead" then
		return
	end
	self.state = "Dead"
	self.warning.Enabled = false
	CollectionService:RemoveTag(self.model, Config.TAG_DAMAGEABLE)
	local index = table.find(all, self)
	if index then
		table.remove(all, index)
	end
	byModel[self.model] = nil
	self.model:Destroy()
	if self.onDespawn then
		self.onDespawn(reason)
	end
end

-- Runs `listener(data, players, position)` whenever a creature is defeated; `players` is everyone
-- who damaged it and `position` is where it fell.
function Creature.onDefeated(listener: (CreatureData.CreatureInfo, { Player }, Vector3) -> ())
	table.insert(defeatListeners, listener)
end

-- One loop thinks for every creature, ten times a second.
local started = false
function Creature.start()
	if started then
		return
	end
	started = true
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < THINK_INTERVAL then
			return
		end
		local step = accumulated
		accumulated = 0
		for _, creature in table.clone(all) do
			local ok, err = pcall(creature.think, creature, step)
			if not ok then
				warn("Creature think failed:", err)
			end
		end
	end)
end

local function playerWithin(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and Combat.rootOf(character)
		if root and (root.Position - position).Magnitude < distance then
			return true
		end
	end
	return false
end

-- Keeps `count` creatures alive around `center`, replacing each one some time after it dies or
-- is tamed. A replacement never appears beside a player: it waits until the spot is clear.
function Creature.spawner(data: CreatureData.CreatureInfo, center: Vector3, count: number, radius: number)
	local footprint = 2.5 * data.scale
	local samples = { Vector2.zero, Vector2.new(footprint, 0), Vector2.new(-footprint, 0), Vector2.new(0, footprint), Vector2.new(0, -footprint) }
	local function spawnOne()
		-- Pick a fairly flat spot: a long body dropped on a steep slope starts inside the hill
		-- and gets flung out of the world.
		local position = center
		for _ = 1, SPAWN_TRIES do
			local angle = math.random() * math.pi * 2
			local distance = math.sqrt(math.random()) * radius
			local x = center.X + math.cos(angle) * distance
			local z = center.Z + math.sin(angle) * distance
			local low, high = math.huge, -math.huge
			for _, offset in samples do
				local y = Build.groundY(x + offset.X, z + offset.Y)
				low = math.min(low, y)
				high = math.max(high, y)
			end
			position = Vector3.new(x, high + 0.3, z)
			if high - low <= MAX_SPAWN_SLOPE and not playerWithin(position, RESPAWN_CLEARANCE) then
				break
			end
		end
		if playerWithin(position, RESPAWN_CLEARANCE) then
			task.delay(RESPAWN_RETRY, spawnOne) -- players are all over the area: wait for them to move on
			return
		end
		Creature.spawn(data, position, function(reason: string)
			local seconds = if reason == "fell" then FALLEN_RESPAWN
				elseif reason == "tamed" then CreatureData.TAMED_RESPAWN
				else data.respawn
			task.delay(seconds, spawnOne)
		end)
	end
	for _ = 1, count do
		spawnOne()
	end
end

return Creature
