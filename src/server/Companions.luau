-- Companions: tamed creatures that follow their owner and fight for them.
--
-- Each player's companions are saved in PlayerData.companions (shared by all their classes).
-- The ones marked `active` are out: they follow the owner, attack whatever the owner last hit
-- (or whatever is biting the owner or them), and are knocked out instead of killed, getting up
-- again after CompanionData.KNOCKOUT_TIME. A class can have CompanionData.limit of them out.
-- A companion's bite is credited to its owner (XP, quest credit, loot).
--
-- Their bodies aren't tagged Damageable, so players can't hit or lock on to them, and they don't
-- collide with players or each other. Everything here runs on the server: clients get the
-- Companions event (for the panel) and read health from the replicated models, which carry the
-- attributes OwnerId, CompanionUid, CompanionName, State, KnockedOut and Spirit.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CompanionData = require(Shared:WaitForChild("CompanionData"))
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Net = require(Shared:WaitForChild("Net"))
local Build = require(script.Parent:WaitForChild("Build"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Creature = require(script.Parent:WaitForChild("Creature"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Companions = {}

local THINK_INTERVAL = 0.1
local SETTLE_TIME = 0.4 -- a new body is held still this long before physics takes over
local FOLLOW_DISTANCE = 7 -- how far behind the owner a companion waits
local FOLLOW_SLACK = 3 -- it doesn't shuffle about for less than this
local TELEPORT_DISTANCE = 90 -- further behind than this, it reappears beside the owner
local TARGET_RANGE = 80 -- targets further than this from the owner are left alone
local WINDUP = 0.35 -- seconds between deciding to bite and the bite landing
local RECOVER = 0.4
local REGEN = 0.03 -- fraction of max health regained per second out of a fight
local FALL_LIMIT = -60
local REQUEST_COOLDOWN = 0.4 -- seconds between panel requests from one player
local GROUP = "Companions"
local PLAYER_GROUP = "Players"
local SLOT_ANGLES = { 155, 205, 180, 120 } -- degrees round from straight ahead: they fan out behind the owner
local SPIRIT_SLOT = 4
local SPIRIT_COLOR = Color3.fromRGB(150, 235, 255)
local TAG = Config.TAG_DAMAGEABLE

type Entry = PlayerData.CompanionEntry
type Companion = {
	owner: Player,
	entry: Entry?, -- nil for the spirit wolf, which isn't saved
	data: CreatureData.CreatureInfo,
	name: string,
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	state: string, -- "Follow" | "Chase" | "Windup" | "Recover" | "KnockedOut"
	timer: number,
	nextAttack: number,
	target: Model?,
	threat: Model?, -- the creature that last bit it
	threatAt: number,
	settleUntil: number?,
	koUntil: number,
	expiresAt: number?, -- the spirit wolf fades at this time
	moving: boolean, -- walking back to its place behind the owner
	rootHeight: number, -- how far above the ground its root rides
	damage: number,
}
type Mark = { model: Model, at: number }
type Buff = { untilTime: number, damage: number, speed: number }

local out: { [Player]: { Companion } } = {}
local byModel: { [Model]: Companion } = {}
local focus: { [Player]: Mark } = {} -- what each player last damaged
local ownerThreat: { [Player]: Mark } = {} -- what last bit each player
local knockedUntil: { [Player]: { [number]: number } } = {} -- uid -> when it recovers (kept while it is sent home)
local buffs: { [Player]: Buff } = {} -- Call of the Wild
local lastRequest: { [Player]: number } = {}

local companionsEvent = Net.event("Companions")
local toastEvent = Net.event("Toast")

local function getFolder(): Folder
	return Build.folder("Companions", workspace)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function listOf(player: Player): { Companion }
	local list = out[player]
	if not list then
		list = {}
		out[player] = list
	end
	return list
end

local function knockedOf(player: Player): { [number]: number }
	local map = knockedUntil[player]
	if not map then
		map = {}
		knockedUntil[player] = map
	end
	return map
end

local function rosterOf(player: Player): { Entry }?
	local data = PlayerData.get(player)
	return data and data.companions
end

-- The owner's living character, its root and its Humanoid (or nils).
local function ownerParts(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character or not Combat.isAlive(character) then
		return nil, nil, nil
	end
	return character, Combat.rootOf(character), character:FindFirstChildOfClass("Humanoid")
end

local function yawOf(cframe: CFrame): number
	local _, yaw = cframe:ToOrientation()
	return yaw
end

-- The point on the ground where companion number `slot` waits: behind the owner, fanned out.
local function slotPosition(root: BasePart, slot: number): Vector3
	local angle = SLOT_ANGLES[(slot - 1) % #SLOT_ANGLES + 1]
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(look.Unit)
	local point = root.Position + direction * FOLLOW_DISTANCE
	return Vector3.new(point.X, Build.groundY(point.X, point.Z), point.Z)
end

local function slotOf(c: Companion): number
	if not c.entry then
		return SPIRIT_SLOT
	end
	local slot = 0
	for _, other in listOf(c.owner) do
		if other.entry then
			slot += 1
		end
		if other == c then
			break
		end
	end
	return math.max(slot, 1)
end

-- How many of the player's saved companions are out (the spirit wolf doesn't count).
local function countOut(player: Player): number
	local count = 0
	for _, c in listOf(player) do
		if c.entry then
			count += 1
		end
	end
	return count
end

local function findOut(player: Player, uid: number): Companion?
	for _, c in listOf(player) do
		if c.entry and c.entry.uid == uid then
			return c
		end
	end
	return nil
end

function Companions.limit(player: Player): number
	return CompanionData.limit(player:GetAttribute("Class"))
end

-- Sends the player their list for the companion panel.
local function send(player: Player)
	local roster = rosterOf(player)
	if not roster then
		return
	end
	local now = os.clock()
	local classId = player:GetAttribute("Class")
	local knocked = knockedOf(player)
	local list = {}
	for _, entry in roster do
		local recoverAt = knocked[entry.uid]
		table.insert(list, {
			uid = entry.uid,
			id = entry.id,
			name = entry.name,
			active = entry.active,
			allowed = CompanionData.canBringOut(classId, entry.id),
			knockedOut = if recoverAt and recoverAt > now then math.ceil(recoverAt - now) else 0,
		})
	end
	companionsEvent:FireClient(player, list, CompanionData.limit(classId), CompanionData.STABLE_SIZE)
end

-- Health and damage follow the owner's level (and class, for the Beast Tamer's bonus).
local function applyStats(c: Companion, heal: boolean)
	local level = (c.owner:GetAttribute("Level") :: number?) or 1
	local maxHealth = CompanionData.maxHealth(c.data, level)
	c.humanoid.MaxHealth = maxHealth
	if heal then
		c.humanoid.Health = maxHealth
	end
	c.damage = CompanionData.damage(c.data, level, c.owner:GetAttribute("Class"))
end

local function despawn(c: Companion, poof: boolean)
	local list = out[c.owner]
	local index = list and table.find(list, c)
	if list and index then
		table.remove(list, index)
	end
	byModel[c.model] = nil
	if poof and c.root.Parent then
		Combat.burst(c.root.Position, 5, Color3.fromRGB(200, 230, 255))
	end
	c.model:Destroy()
end

local function despawnAll(player: Player)
	for _, c in table.clone(listOf(player)) do
		despawn(c, false)
	end
end

-- Stands the companion upright on the ground at `point`, keeping the way it faces.
local function standAt(c: Companion, point: Vector3)
	local y = Build.groundY(point.X, point.Z) + c.rootHeight
	c.model:PivotTo(CFrame.new(point.X, y, point.Z) * CFrame.Angles(0, yawOf(c.root.CFrame), 0))
	c.root.AssemblyLinearVelocity = Vector3.zero
end

local function face(c: Companion, position: Vector3)
	local from = c.root.Position
	local flatTarget = Vector3.new(position.X, from.Y, position.Z)
	if (flatTarget - from).Magnitude > 0.1 then
		c.root.CFrame = CFrame.lookAt(from, flatTarget)
	end
end

-- A soft outline for `seconds` (Call of the Wild).
local function glow(model: Model, seconds: number)
	local highlight = Instance.new("Highlight")
	highlight.Name = "WildGlow"
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(140, 255, 150)
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	Debris:AddItem(highlight, seconds)
end

-- Knocked out instead of killed: it lies down, can't be hit, and gets up after KNOCKOUT_TIME.
local function knockOut(c: Companion)
	if c.state == "KnockedOut" or not byModel[c.model] then
		return
	end
	local entry = c.entry
	if not entry then
		despawn(c, true) -- the spirit wolf just fades away
		return
	end
	c.state = "KnockedOut"
	c.target = nil
	c.moving = false
	c.koUntil = os.clock() + CompanionData.KNOCKOUT_TIME
	knockedOf(c.owner)[entry.uid] = c.koUntil
	c.model:SetAttribute("KnockedOut", true)
	c.model:SetAttribute("Invulnerable", true)
	c.humanoid.DisplayName = `{c.name} (knocked out)`
	c.settleUntil = nil
	c.root.Anchored = true
	-- Lie on its side on the ground.
	local position = c.root.Position
	local ground = Build.groundY(position.X, position.Z)
	c.model:PivotTo(CFrame.new(position.X, ground + c.root.Size.X / 2 + 0.2, position.Z)
		* CFrame.Angles(0, yawOf(c.root.CFrame), math.rad(90)))
	toastEvent:FireClient(c.owner, `{c.name} was knocked out. It will recover in {CompanionData.KNOCKOUT_TIME} s`)
	send(c.owner)
end

local function recover(c: Companion)
	c.state = "Follow"
	c.koUntil = 0
	if c.entry then
		knockedOf(c.owner)[c.entry.uid] = nil
	end
	c.model:SetAttribute("KnockedOut", nil)
	c.model:SetAttribute("Invulnerable", nil)
	c.humanoid.DisplayName = `{c.owner.DisplayName}'s {c.name}`
	c.humanoid.Health = c.humanoid.MaxHealth
	local _, ownerRoot = ownerParts(c.owner)
	local position = c.root.Position
	if ownerRoot and flatDistance(position, ownerRoot.Position) > TELEPORT_DISTANCE then
		position = slotPosition(ownerRoot, slotOf(c)) -- the owner moved on: get up beside them
	end
	standAt(c, position)
	c.root.Anchored = false
	c.root:SetNetworkOwner(nil)
	toastEvent:FireClient(c.owner, `{c.name} is back on its feet`)
	send(c.owner)
end

-- Builds a companion's body standing on `ground`, facing `yaw`.
local function spawn(player: Player, entry: Entry?, data: CreatureData.CreatureInfo, ground: Vector3, yaw: number?, name: string): Companion
	local model, humanoid, root = Creature.buildBody(data, ground, getFolder(), false)
	if yaw then
		model:PivotTo(CFrame.new(model:GetPivot().Position) * CFrame.Angles(0, yaw, 0))
	end
	model.Name = name
	humanoid.DisplayName = `{player.DisplayName}'s {name}`
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) -- knocked out, never dead (see think)
	model:SetAttribute("NeverDies", true)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CompanionUid", if entry then entry.uid else 0)
	model:SetAttribute("CompanionName", name)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = GROUP
		end
	end
	local c: Companion = {
		owner = player,
		entry = entry,
		data = data,
		name = name,
		model = model,
		humanoid = humanoid,
		root = root,
		state = "Follow",
		timer = 0,
		nextAttack = 0,
		target = nil,
		threat = nil,
		threatAt = 0,
		settleUntil = os.clock() + SETTLE_TIME,
		koUntil = 0,
		expiresAt = nil,
		moving = false,
		rootHeight = root.Position.Y - ground.Y,
		damage = 0,
	}
	applyStats(c, true)
	table.insert(listOf(player), c)
	byModel[model] = c
	Combat.onHit(model, function()
		if humanoid.Health <= 1 then
			knockOut(c)
		end
	end)
	return c
end

local function validTarget(model: Model?, ownerPosition: Vector3): boolean
	if not model or not model.Parent or not Combat.isAlive(model) or not CollectionService:HasTag(model, TAG) then
		return false
	end
	local root = Combat.rootOf(model)
	return root ~= nil and (root.Position - ownerPosition).Magnitude <= TARGET_RANGE
end

-- What to attack: whatever the owner last hit, else whatever last bit this companion, else
-- whatever last bit the owner.
local function pickTarget(c: Companion, now: number, ownerPosition: Vector3): Model?
	local mark = focus[c.owner]
	if mark and now - mark.at <= CompanionData.FOCUS_TIME and validTarget(mark.model, ownerPosition) then
		return mark.model
	end
	if c.threat and now - c.threatAt <= CompanionData.THREAT_TIME and validTarget(c.threat, ownerPosition) then
		return c.threat
	end
	local threat = ownerThreat[c.owner]
	if threat and now - threat.at <= CompanionData.THREAT_TIME and validTarget(threat.model, ownerPosition) then
		return threat.model
	end
	return nil
end

local function think(c: Companion, dt: number)
	local now = os.clock()
	local settleUntil = c.settleUntil
	if settleUntil then
		if now < settleUntil then
			return
		end
		c.settleUntil = nil
		c.root.Anchored = false
		c.root:SetNetworkOwner(nil) -- the server moves companions
	end
	if c.expiresAt and now >= c.expiresAt then
		despawn(c, true)
		return
	end
	if c.state == "KnockedOut" then
		if now >= c.koUntil then
			recover(c)
		end
		return
	end
	if c.humanoid.Health <= 1 then
		knockOut(c) -- safety net: health drained some way other than Combat.damage
		return
	end
	local _, ownerRoot, ownerHumanoid = ownerParts(c.owner)
	if not ownerRoot or not ownerHumanoid then
		c.humanoid:MoveTo(c.root.Position) -- the owner is down: wait (their companions are cleared when they fall)
		return
	end
	local position = c.root.Position
	local ownerPosition = ownerRoot.Position
	if position.Y < FALL_LIMIT or flatDistance(position, ownerPosition) > TELEPORT_DISTANCE then
		standAt(c, slotPosition(ownerRoot, slotOf(c)))
		c.state = "Follow"
		c.target = nil
		c.moving = false
		return
	end

	local buff = buffs[c.owner]
	local damageBonus, speedBonus = 1, 1
	if buff and now < buff.untilTime then
		damageBonus, speedBonus = buff.damage, buff.speed
	end

	if c.state == "Follow" or c.state == "Chase" then
		c.target = pickTarget(c, now, ownerPosition)
		c.state = if c.target then "Chase" else "Follow"
	end

	if c.state == "Follow" then
		if c.humanoid.Health < c.humanoid.MaxHealth then
			c.humanoid.Health = math.min(c.humanoid.MaxHealth, c.humanoid.Health + c.humanoid.MaxHealth * REGEN * dt)
		end
		local toOwner = flatDistance(position, ownerPosition)
		if toOwner > FOLLOW_DISTANCE + FOLLOW_SLACK + 1 then
			c.moving = true -- the owner walked off: catch up
		end
		if c.moving then
			local goal = slotPosition(ownerRoot, slotOf(c))
			if flatDistance(position, goal) <= FOLLOW_SLACK then
				c.moving = false
				c.humanoid:MoveTo(position)
			else
				local speed = math.max(c.data.walkSpeed, ownerHumanoid.WalkSpeed * 1.1) * speedBonus
				if toOwner > 30 then
					speed *= 1.5
				end
				c.humanoid.WalkSpeed = speed
				c.humanoid:MoveTo(goal)
			end
		end
	elseif c.state == "Chase" then
		local targetRoot = c.target and Combat.rootOf(c.target)
		if not targetRoot then
			c.state = "Follow"
			return
		end
		if flatDistance(position, targetRoot.Position) <= c.data.attackRange + 1.5 then
			c.humanoid:MoveTo(position) -- stop
			face(c, targetRoot.Position)
			if now >= c.nextAttack then
				c.state = "Windup"
				c.timer = WINDUP
			end
		else
			c.humanoid.WalkSpeed = math.max(c.data.walkSpeed, ownerHumanoid.WalkSpeed) * 1.1 * speedBonus
			c.humanoid:MoveTo(targetRoot.Position)
		end
	elseif c.state == "Windup" then
		local target = c.target
		local targetRoot = if target and Combat.isAlive(target) then Combat.rootOf(target) else nil
		if targetRoot then
			face(c, targetRoot.Position)
		end
		c.timer -= dt
		if c.timer <= 0 then
			if target and targetRoot and flatDistance(position, targetRoot.Position) <= c.data.attackRange + 3 then
				local amount, crit = Combat.rollDamage(c.damage * damageBonus)
				Combat.damage(target, amount, c.owner, crit, c.model) -- the owner gets the credit
			end
			c.nextAttack = now + c.data.attackInterval
			c.state = "Recover"
			c.timer = RECOVER
		end
	elseif c.state == "Recover" then
		c.timer -= dt
		if c.timer <= 0 then
			c.state = "Chase"
		end
	end
end

-- Brings out the companions marked active, as far as the player's class allows; the rest are
-- sent home. Called when the character spawns (so also after a class change).
function Companions.refresh(player: Player)
	local roster = rosterOf(player)
	if not roster then
		return
	end
	despawnAll(player)
	local _, root = ownerParts(player)
	local classId = player:GetAttribute("Class")
	local limit = CompanionData.limit(classId)
	local count = 0
	local changed = false
	for _, entry in roster do
		if entry.active then
			local data = CreatureData.creatures[entry.id]
			if data and count < limit and CompanionData.canBringOut(classId, entry.id) then
				count += 1
				if root then
					spawn(player, entry, data, slotPosition(root, count), yawOf(root.CFrame), entry.name)
				end
			else
				entry.active = false
				changed = true
			end
		end
	end
	if changed then
		PlayerData.markDirty(player)
	end
	send(player)
end

-- Whether `player` could take on a newly tamed creature of this kind. Returns false and why not.
function Companions.canTame(player: Player, data: CreatureData.CreatureInfo): (boolean, string?)
	local roster = rosterOf(player)
	if not roster then
		return false, "Your progress hasn't loaded yet"
	end
	if data.tamerOnly and player:GetAttribute("Class") ~= CompanionData.TAMER_CLASS then
		return false, `Only a Beast Tamer can tame a {string.lower(data.name)}`
	end
	if #roster >= CompanionData.STABLE_SIZE then
		return false, `You already have {CompanionData.STABLE_SIZE} companions. Release one first (P)`
	end
	return true, nil
end

-- Adds a newly tamed creature to the player's companions. It comes out at `position` facing
-- `yaw` (where the wild creature stood) if there's room; otherwise it waits at home.
function Companions.add(player: Player, data: CreatureData.CreatureInfo, position: Vector3, yaw: number?): boolean
	local save = PlayerData.get(player)
	if not save or not Companions.canTame(player, data) then
		return false
	end
	local entry: Entry = { uid = save.nextCompanionUid, id = data.id, name = data.name, active = false }
	save.nextCompanionUid += 1
	table.insert(save.companions, entry)
	local limit = Companions.limit(player)
	if countOut(player) < limit and CompanionData.canBringOut(player:GetAttribute("Class"), data.id) and ownerParts(player) then
		entry.active = true
		local ground = Vector3.new(position.X, Build.groundY(position.X, position.Z), position.Z)
		spawn(player, entry, data, ground, yaw, entry.name)
	else
		toastEvent:FireClient(player, `{entry.name} is waiting at home: only {limit} can be out. Press P to choose`)
	end
	PlayerData.markDirty(player)
	send(player)
	task.spawn(PlayerData.save, player) -- a new companion is worth saving straight away
	return true
end

-- Living companions (not knocked out) within `radius` of `position`, for heals.
function Companions.near(position: Vector3, radius: number): { Model }
	local list = {}
	for model, c in byModel do
		if c.state ~= "KnockedOut" and model.Parent and (c.root.Position - position).Magnitude <= radius then
			table.insert(list, model)
		end
	end
	return list
end

-- The Beast Tamer's Call of the Wild: the player's companions hit harder and run faster for
-- `skill.duration` and are healed, and a spirit wolf joins the fight for `skill.spiritTime`.
function Companions.callOfTheWild(player: Player, skill: { [string]: any }): boolean
	local _, root = ownerParts(player)
	if not root then
		return false
	end
	local now = os.clock()
	buffs[player] = { untilTime = now + skill.duration, damage = 1 + skill.damageBonus, speed = 1 + skill.speedBonus }
	for _, c in table.clone(listOf(player)) do
		if not c.entry then
			despawn(c, false) -- an earlier spirit wolf
		elseif c.state ~= "KnockedOut" then
			Combat.heal(c.model, c.humanoid.MaxHealth * skill.heal)
			glow(c.model, skill.duration)
		end
	end
	local data = CreatureData.creatures[skill.spirit]
	if data then
		local spirit = spawn(player, nil, data, slotPosition(root, SPIRIT_SLOT), yawOf(root.CFrame), `Spirit {data.name}`)
		spirit.expiresAt = now + skill.spiritTime
		spirit.model:SetAttribute("Spirit", true)
		for _, part in spirit.model:GetDescendants() do
			if part:IsA("BasePart") and part ~= spirit.root then
				part.Material = Enum.Material.Neon
				part.Color = SPIRIT_COLOR
				part.Transparency = 0.45
				part.CastShadow = false
			end
		end
	end
	Combat.burst(root.Position, 18, Color3.fromRGB(120, 220, 130))
	return true
end

-- Panel requests ------------------------------------------------------------------------------

local function tooSoon(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or -100) < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = now
	return false
end

local function findEntry(player: Player, uid: any): (Entry?, number?)
	local roster = rosterOf(player)
	if not roster or typeof(uid) ~= "number" then
		return nil, nil
	end
	for index, entry in roster do
		if entry.uid == uid then
			return entry, index
		end
	end
	return nil, nil
end

local function onSetActive(player: Player, uid: any, active: any)
	if typeof(active) ~= "boolean" or tooSoon(player) then
		return
	end
	local entry = findEntry(player, uid)
	if not entry then
		return
	end
	local current = findOut(player, entry.uid)
	if active and not current then
		local _, root = ownerParts(player)
		local data = CreatureData.creatures[entry.id]
		local limit = Companions.limit(player)
		local recoverAt = knockedOf(player)[entry.uid]
		if not root or not data then
			return
		elseif not CompanionData.canBringOut(player:GetAttribute("Class"), entry.id) then
			toastEvent:FireClient(player, `Only a Beast Tamer can bring out a {string.lower(data.name)}`)
		elseif countOut(player) >= limit then
			toastEvent:FireClient(player, if limit == 1 then "Only 1 companion can be out. Send the other home first"
				else `Only {limit} companions can be out. Send one home first`)
		elseif recoverAt and recoverAt > os.clock() then
			toastEvent:FireClient(player, `{entry.name} is still recovering ({math.ceil(recoverAt - os.clock())} s)`)
		else
			entry.active = true
			spawn(player, entry, data, slotPosition(root, countOut(player) + 1), yawOf(root.CFrame), entry.name)
			PlayerData.markDirty(player)
		end
	elseif not active then
		if current then
			despawn(current, true)
		end
		if entry.active then
			entry.active = false
			PlayerData.markDirty(player)
		end
	end
	send(player)
end

local function onRelease(player: Player, uid: any)
	if tooSoon(player) then
		return
	end
	local entry, index = findEntry(player, uid)
	local roster = rosterOf(player)
	if not entry or not index or not roster then
		return
	end
	local current = findOut(player, entry.uid)
	if current then
		despawn(current, true)
	end
	table.remove(roster, index)
	knockedOf(player)[entry.uid] = nil
	PlayerData.markDirty(player)
	toastEvent:FireClient(player, `You released {entry.name} back into the wild`)
	send(player)
end

-- Players --------------------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	-- Players and companions don't push each other around.
	local function group(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = PLAYER_GROUP
		end
	end
	for _, descendant in character:GetDescendants() do
		group(descendant)
	end
	character.DescendantAdded:Connect(group)

	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Died:Connect(function()
		despawnAll(player) -- they come back, at full health, when the owner does
	end)
	knockedUntil[player] = {}
	focus[player] = nil
	ownerThreat[player] = nil
	buffs[player] = nil
	task.wait(0.5) -- let the character land at the spawn point first
	if player.Character == character and character.Parent then
		Companions.refresh(player)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		despawnAll(player)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		for _, c in listOf(player) do
			applyStats(c, c.state ~= "KnockedOut") -- a level-up heals companions, like their owner
		end
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

local started = false
function Companions.start()
	if started then
		return
	end
	started = true
	for _, name in { GROUP, PLAYER_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, PLAYER_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
	getFolder()

	Net.event("CompanionSetActive").OnServerEvent:Connect(onSetActive)
	Net.event("CompanionRelease").OnServerEvent:Connect(onRelease)
	PlayerData.onLoaded(send)

	-- Companions pick their targets from who hit what.
	Combat.onDamage(function(model: Model, source: Instance?, via: Model?)
		local now = os.clock()
		if source and source:IsA("Player") then
			if not via and CollectionService:HasTag(model, TAG) then
				focus[source] = { model = model, at = now }
			end
		elseif source and source:IsA("Model") then
			local c = byModel[model]
			if c then
				c.threat = source
				c.threatAt = now
			else
				local player = Players:GetPlayerFromCharacter(model)
				if player then
					ownerThreat[player] = { model = source, at = now }
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		despawnAll(player)
		out[player] = nil
		focus[player] = nil
		ownerThreat[player] = nil
		knockedUntil[player] = nil
		buffs[player] = nil
		lastRequest[player] = nil
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < THINK_INTERVAL then
			return
		end
		local step = accumulated
		accumulated = 0
		for _, list in out do
			for _, c in table.clone(list) do
				local ok, err = pcall(think, c, step)
				if not ok then
					warn("Companion think failed:", err)
				end
				-- What it is doing, for anything that wants to show it (and for testing).
				if c.model.Parent and c.model:GetAttribute("State") ~= c.state then
					c.model:SetAttribute("State", c.state)
				end
			end
		end
	end)
end

return Companions
