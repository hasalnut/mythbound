-- Server-side combat: damage, player attacks (melee arcs and projectiles) and dashes.
-- Anything that can be hit is a Model tagged "Damageable" with a Humanoid and these attributes:
--   HitRadius (studs), HitHeight (studs above the root), Hostile (bool), Void (bool),
--   DamageReduction (0-1), Invulnerable (bool, set during a dash)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))
local SkillData = require(Shared:WaitForChild("SkillData"))

local Combat = {}

local TAG = Config.TAG_DAMAGEABLE
local damageNumberEvent = Net.event("DamageNumber")
local effectEvent = Net.event("Effect")

type HitHandler = (source: Instance?) -> ()
local hitHandlers: { [Model]: HitHandler } = {}

type Projectile = {
	position: Vector3,
	velocity: Vector3,
	life: number,
	shooter: Player,
	damage: number,
	crit: boolean,
	voidMultiplier: number,
	explodeRadius: number?, -- set for projectiles that burst on impact (Fireball)
	explodeColor: Color3?,
}
local projectiles: { Projectile } = {}

local lastAttack: { [Player]: number } = {}
local lastDash: { [Player]: number } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- False for vectors holding NaN or infinity (a client could send one on purpose).
local function isFinite(v: Vector3): boolean
	local m = v.Magnitude
	return m == m and m < math.huge
end

function Combat.rootOf(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function Combat.isAlive(model: Instance?): boolean
	if not model or not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Lets a creature react when it is hit (for example, to chase whoever hit it).
function Combat.onHit(model: Model, handler: HitHandler)
	hitHandlers[model] = handler
	model.Destroying:Connect(function()
		hitHandlers[model] = nil
	end)
end

function Combat.flash(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "HitFlash"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	task.delay(0.1, function()
		highlight:Destroy()
	end)
end

function Combat.rollDamage(base: number): (number, boolean)
	local crit = math.random() < Config.CRIT_CHANCE
	local amount = base * (0.9 + math.random() * 0.2)
	if crit then
		amount *= Config.CRIT_MULT
	end
	return amount, crit
end

-- Deals damage after damage reduction. `source` is the attacking Player or creature Model.
function Combat.damage(model: Model, amount: number, source: Instance?, crit: boolean?): number
	if not Combat.isAlive(model) then
		return 0
	end
	if model:GetAttribute("Invulnerable") then
		return 0
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local reduction = (model:GetAttribute("DamageReduction") :: number?) or 0
	local dealt = math.max(1, math.floor(amount * (1 - reduction) + 0.5))
	humanoid.Health = math.max(0, humanoid.Health - dealt)

	local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
	local root = Combat.rootOf(model)
	if root then
		local height = (model:GetAttribute("HitHeight") :: number?) or 4
		local kind = if isPlayer then "hurt" elseif crit then "crit" else "normal"
		local attacker = if source and source:IsA("Player") then source else nil
		damageNumberEvent:FireAllClients(model, root.Position + Vector3.new(0, height, 0), dealt, kind, attacker)
	end
	if not isPlayer then
		Combat.flash(model)
	end
	local handler = hitHandlers[model]
	if handler then
		task.spawn(handler, source)
	end
	return dealt
end

function Combat.targets(): { Model }
	local list = {}
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("Model") and inst:IsDescendantOf(workspace) and Combat.isAlive(inst) then
			table.insert(list, inst)
		end
	end
	return list
end

-- Picks the best target in front of `origin`: close, near the aim line, hostile ones first.
function Combat.bestTarget(origin: Vector3, direction: Vector3, range: number, maxAngle: number): Model?
	local best: Model? = nil
	local bestScore = math.huge
	for _, model in Combat.targets() do
		local root = Combat.rootOf(model)
		if root then
			local to = flat(root.Position - origin)
			local distance = to.Magnitude
			local radius = (model:GetAttribute("HitRadius") :: number?) or 2
			if distance <= range + radius then
				local angle = if distance > 0.1 then math.acos(math.clamp(to.Unit:Dot(direction), -1, 1)) else 0
				if angle <= maxAngle or distance <= radius + 3 then
					local score = distance + angle * 20 - (if model:GetAttribute("Hostile") then 15 else 0)
					if score < bestScore then
						best = model
						bestScore = score
					end
				end
			end
		end
	end
	return best
end

local function melee(player: Player, root: BasePart, direction: Vector3, info: ClassData.ClassInfo, attack: number)
	local halfArc = math.rad(info.arc) / 2
	-- A Ninja attacking from Vanish lands a backstab on everything in the swing, then reappears.
	local character = root.Parent
	local backstab = character ~= nil and character:GetAttribute("Vanished") == true
	local hitAny = false
	for _, model in Combat.targets() do
		local targetRoot = Combat.rootOf(model)
		if targetRoot then
			local to = flat(targetRoot.Position - root.Position)
			local radius = (model:GetAttribute("HitRadius") :: number?) or 2
			local distance = to.Magnitude
			if distance <= info.range + radius then
				local inArc = distance <= radius + 1.5 or math.acos(math.clamp(to.Unit:Dot(direction), -1, 1)) <= halfArc
				if inArc then
					local amount, crit = Combat.rollDamage(attack)
					if backstab then
						amount *= SkillData.skills.vanish.backstab
					end
					Combat.damage(model, amount, player, crit or backstab)
					hitAny = true
				end
			end
		end
	end
	if backstab and hitAny and character then
		character:SetAttribute("Vanished", nil)
	end
	effectEvent:FireAllClients("swing", root.Position + direction * (info.range * 0.45), direction, info.color, info.range)
end

local function shoot(player: Player, character: Model, root: BasePart, direction: Vector3, info: ClassData.ClassInfo, locked: Model?, attack: number)
	local start = root.Position + Vector3.new(0, 1.5, 0) + direction * 2
	local target = locked or Combat.bestTarget(root.Position, direction, Config.AUTO_AIM_RANGE, Config.AUTO_AIM_ANGLE)
	local aim = direction
	if target then
		local targetRoot = Combat.rootOf(target)
		if targetRoot then
			aim = (targetRoot.Position - start).Unit
		end
	end
	local amount, crit = Combat.rollDamage(attack)
	local projectile: Projectile = {
		position = start,
		velocity = aim * info.projectileSpeed,
		life = Config.PROJECTILE_LIFETIME,
		shooter = player,
		damage = amount,
		crit = crit,
		voidMultiplier = info.voidMultiplier,
	}
	table.insert(projectiles, projectile)
	effectEvent:FireAllClients("bolt", start, projectile.velocity, info.projectileColor, Config.PROJECTILE_LIFETIME, info.arrow, character)
end

local function onAttack(player: Player, aim: any, locked: any)
	if typeof(aim) ~= "Vector3" or not isFinite(aim) then
		return
	end
	local character = player.Character
	if not character or not Combat.isAlive(character) then
		return
	end
	local info = ClassData.get(player:GetAttribute("Class"))
	if not info then
		return
	end
	local now = os.clock()
	if now - (lastAttack[player] or 0) < info.interval * 0.85 then
		return -- too soon; the client enforces the real cooldown
	end
	lastAttack[player] = now

	local root = Combat.rootOf(character)
	if not root then
		return
	end
	local direction = flat(aim)
	if direction.Magnitude < 0.01 then
		direction = flat(root.CFrame.LookVector)
	end
	direction = direction.Unit

	local lockedModel: Model? = nil
	if typeof(locked) == "Instance" and locked:IsA("Model") and CollectionService:HasTag(locked, TAG) and Combat.isAlive(locked) then
		-- Only honour a lock on something the client could really have locked on to.
		local lockedRoot = Combat.rootOf(locked)
		if lockedRoot and (lockedRoot.Position - root.Position).Magnitude <= Config.LOCK_RANGE * 1.3 then
			lockedModel = locked
		end
	end

	local attack = Progression.attack(info.attack, (player:GetAttribute("Level") :: number?) or 1)
	if info.style == "Melee" then
		melee(player, root, direction, info, attack)
	else
		shoot(player, character, root, direction, info, lockedModel, attack)
	end
end

local function onDash(player: Player)
	local character = player.Character
	if not character or not Combat.isAlive(character) then
		return
	end
	local now = os.clock()
	if now - (lastDash[player] or -100) < Config.DASH_COOLDOWN * 0.85 then
		return
	end
	lastDash[player] = now
	character:SetAttribute("Invulnerable", true)
	task.delay(Config.DASH_IFRAMES, function()
		if character.Parent then
			character:SetAttribute("Invulnerable", nil)
		end
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function findDamageable(part: Instance): Model?
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if CollectionService:HasTag(model, TAG) then
			return model
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

local function stepProjectiles(dt: number)
	if #projectiles == 0 then
		return
	end
	-- Projectiles pass through every player (no friendly fire).
	local exclude: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude

	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		local step = p.velocity * dt
		local result = workspace:Raycast(p.position, step, rayParams)
		p.life -= dt
		if result then
			if p.explodeRadius then
				Combat.explode(p.shooter, result.Position, p.explodeRadius, p.damage, p.crit, p.voidMultiplier, p.explodeColor)
			else
				local model = findDamageable(result.Instance)
				if model then
					local amount = p.damage
					if model:GetAttribute("Void") then
						amount *= p.voidMultiplier
					end
					Combat.damage(model, amount, p.shooter, p.crit)
				end
			end
			table.remove(projectiles, i)
		elseif p.life <= 0 then
			table.remove(projectiles, i)
		else
			p.position += step
		end
	end
end

-- Damageable models (creatures, dummies) within `radius` studs of `position`, measured to their edge.
function Combat.targetsNear(position: Vector3, radius: number): { Model }
	local list = {}
	for _, model in Combat.targets() do
		local root = Combat.rootOf(model)
		if root then
			local size = (model:GetAttribute("HitRadius") :: number?) or 2
			if flat(root.Position - position).Magnitude <= radius + size then
				table.insert(list, model)
			end
		end
	end
	return list
end

-- Living player characters within `radius` studs of `position` (allies, for healing).
function Combat.playersNear(position: Vector3, radius: number): { Model }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and Combat.rootOf(character)
		if character and root and Combat.isAlive(character) and (root.Position - position).Magnitude <= radius then
			table.insert(list, character)
		end
	end
	return list
end

-- An expanding ring of light that every player sees (novas, explosions, heals).
function Combat.burst(position: Vector3, radius: number, color: Color3)
	effectEvent:FireAllClients("burst", position, radius, color)
end

-- Damages everything within `radius` of `position`, with the burst effect.
function Combat.explode(shooter: Player, position: Vector3, radius: number, damage: number, crit: boolean, voidMultiplier: number, color: Color3?)
	for _, model in Combat.targetsNear(position, radius) do
		local amount = damage
		if model:GetAttribute("Void") then
			amount *= voidMultiplier
		end
		Combat.damage(model, amount, shooter, crit)
	end
	Combat.burst(position, radius, color or Color3.fromRGB(255, 140, 60))
end

export type ProjectileOptions = {
	color: Color3,
	arrow: boolean?,
	size: number?, -- diameter of the visible orb
	explodeRadius: number?,
	voidMultiplier: number?,
}

-- Launches a server projectile (it passes through players) and tells every client to draw it.
function Combat.fireProjectile(shooter: Player, start: Vector3, velocity: Vector3, damage: number, crit: boolean, options: ProjectileOptions)
	table.insert(projectiles, {
		position = start,
		velocity = velocity,
		life = Config.PROJECTILE_LIFETIME,
		shooter = shooter,
		damage = damage,
		crit = crit,
		voidMultiplier = options.voidMultiplier or 1,
		explodeRadius = options.explodeRadius,
		explodeColor = options.color,
	})
	effectEvent:FireAllClients("bolt", start, velocity, options.color, Config.PROJECTILE_LIFETIME, options.arrow == true, shooter.Character, options.size)
end

-- Heals a player character and shows a green number. Returns how much was healed.
function Combat.heal(character: Model, amount: number): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = Combat.rootOf(character)
	if not humanoid or humanoid.Health <= 0 or not root then
		return 0
	end
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	local healed = humanoid.Health - before
	if healed >= 1 then
		damageNumberEvent:FireAllClients(character, root.Position + Vector3.new(0, 4, 0), math.floor(healed + 0.5), "heal")
	end
	return healed
end

function Combat.start()
	Net.event("Attack").OnServerEvent:Connect(onAttack)
	Net.event("Dash").OnServerEvent:Connect(onDash)
	RunService.Heartbeat:Connect(stepProjectiles)
	Players.PlayerRemoving:Connect(function(player)
		lastAttack[player] = nil
		lastDash[player] = nil
	end)
end

return Combat
