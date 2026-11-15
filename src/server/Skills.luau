-- Class skills (Q and E) and mana. The server checks cooldowns and mana and does everything;
-- the client only asks (UseSkill) and draws the cooldown once SkillUsed comes back.
-- Mana lives here and is shown to clients through the Mana / MaxMana player attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))
local SkillData = require(Shared:WaitForChild("SkillData"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Companions = require(script.Parent:WaitForChild("Companions"))
local Creature = require(script.Parent:WaitForChild("Creature"))
local Taming = require(script.Parent:WaitForChild("Taming"))

local Skills = {}

local REGEN_STEP = 0.25

local mana: { [Player]: number } = {}
local readyAt: { [Player]: { [number]: number } } = {}
type Regen = { character: Model, perSecond: number, untilTime: number }
local regens: { Regen } = {}

local toastEvent = Net.event("Toast")
local usedEvent = Net.event("SkillUsed")

local function level(player: Player): number
	return (player:GetAttribute("Level") :: number?) or 1
end

function Skills.maxMana(player: Player): number
	local info = ClassData.get(player:GetAttribute("Class"))
	return if info then Progression.maxMana(info.mana, level(player)) else 0
end

local function publish(player: Player)
	player:SetAttribute("MaxMana", Skills.maxMana(player))
	player:SetAttribute("Mana", math.floor(mana[player] or 0))
end

function Skills.refill(player: Player)
	mana[player] = Skills.maxMana(player)
	readyAt[player] = {}
	publish(player)
end

local function isFinite(v: Vector3): boolean
	local m = v.Magnitude
	return m == m and m < math.huge
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

type Context = {
	player: Player,
	character: Model,
	root: BasePart,
	humanoid: Humanoid,
	info: ClassData.ClassInfo,
	attack: number, -- the player's attack at their level
	aim: Vector3, -- flat unit direction
	locked: Model?,
}

-- Points from the player's chest at the locked target, or the best target near the aim line.
local function aimAt(ctx: Context, range: number): Vector3
	local target = ctx.locked or Combat.bestTarget(ctx.root.Position, ctx.aim, range, Config.AUTO_AIM_ANGLE)
	local targetRoot = target and Combat.rootOf(target)
	if targetRoot then
		return (targetRoot.Position - (ctx.root.Position + Vector3.new(0, 1.5, 0))).Unit
	end
	return ctx.aim
end

-- Everyone a heal reaches: player characters and companions within `radius`.
local function alliesNear(position: Vector3, radius: number): { Model }
	local list = Combat.playersNear(position, radius)
	for _, model in Companions.near(position, radius) do
		table.insert(list, model)
	end
	return list
end

local function healAllies(ctx: Context, radius: number, fraction: number)
	for _, character in alliesNear(ctx.root.Position, radius) do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			Combat.heal(character, humanoid.MaxHealth * fraction)
		end
	end
end

-- Each handler does the skill and returns true, or returns false to cancel (no mana spent).
local handlers: { [string]: (Context, SkillData.Skill) -> boolean } = {}

handlers.vanish = function(ctx, skill)
	local character, humanoid = ctx.character, ctx.humanoid
	local baseSpeed = ctx.info.walkSpeed
	character:SetAttribute("Vanished", true)
	humanoid.WalkSpeed = baseSpeed * (1 + skill.speedBonus)
	Combat.burst(ctx.root.Position, 8, Color3.fromRGB(120, 110, 160))
	local connection: RBXScriptConnection
	connection = character:GetAttributeChangedSignal("Vanished"):Connect(function()
		if not character:GetAttribute("Vanished") then
			connection:Disconnect()
			humanoid.WalkSpeed = baseSpeed
		end
	end)
	task.delay(skill.duration, function()
		if character.Parent then
			character:SetAttribute("Vanished", nil)
		end
	end)
	return true
end

handlers.shuriken_fan = function(ctx, skill)
	local start = ctx.root.Position + Vector3.new(0, 1, 0) + ctx.aim * 2
	-- The middle star flies at the target (so the fan tilts down onto low creatures like wolves).
	local centre = aimAt(ctx, Config.AUTO_AIM_RANGE)
	local half = (skill.count - 1) / 2
	for i = 0, skill.count - 1 do
		local angle = math.rad((i - half) * skill.spread)
		local direction = CFrame.Angles(0, angle, 0):VectorToWorldSpace(centre)
		local amount, crit = Combat.rollDamage(ctx.attack * skill.multiplier)
		Combat.fireProjectile(ctx.player, start, direction * skill.speed, amount, crit, {
			color = Color3.fromRGB(215, 220, 230),
			size = 0.8,
		})
	end
	return true
end

handlers.taunt = function(ctx, skill)
	local character = ctx.character
	local count = Creature.taunt(character, ctx.root.Position, skill.radius, skill.duration)
	local base = ctx.info.damageReduction
	character:SetAttribute("DamageReduction", math.min(skill.maxReduction, base + skill.reduction))
	character:SetAttribute("Taunting", true)
	Combat.burst(ctx.root.Position, 20, Color3.fromRGB(230, 80, 60))
	task.delay(skill.duration, function()
		if character.Parent then
			character:SetAttribute("DamageReduction", base)
			character:SetAttribute("Taunting", nil)
		end
	end)
	if count == 0 then
		toastEvent:FireClient(ctx.player, "Nothing nearby to taunt")
	end
	return true
end

handlers.shield_slam = function(ctx, skill)
	for _, model in Combat.targetsNear(ctx.root.Position, skill.radius) do
		local amount, crit = Combat.rollDamage(ctx.attack * skill.multiplier)
		Combat.damage(model, amount, ctx.player, crit)
		local creature = Creature.find(model)
		local root = Combat.rootOf(model)
		if creature and root then
			creature:stun(skill.stun, Color3.fromRGB(255, 240, 200))
			creature:knockback(flat(root.Position - ctx.root.Position), skill.knockback)
		end
	end
	Combat.burst(ctx.root.Position, skill.radius, Color3.fromRGB(110, 160, 235))
	return true
end

handlers.fireball = function(ctx, skill)
	local direction = aimAt(ctx, Config.AUTO_AIM_RANGE)
	local start = ctx.root.Position + Vector3.new(0, 1.5, 0) + ctx.aim * 2
	local amount, crit = Combat.rollDamage(ctx.attack * skill.multiplier)
	Combat.fireProjectile(ctx.player, start, direction * skill.speed, amount, crit, {
		color = Color3.fromRGB(255, 120, 40),
		size = 2.6,
		explodeRadius = skill.radius,
	})
	return true
end

handlers.frost_nova = function(ctx, skill)
	for _, model in Combat.targetsNear(ctx.root.Position, skill.radius) do
		local amount, crit = Combat.rollDamage(ctx.attack * skill.multiplier)
		Combat.damage(model, amount, ctx.player, crit)
		local creature = Creature.find(model)
		if creature then
			creature:stun(skill.freeze, Color3.fromRGB(140, 210, 255))
		end
	end
	Combat.burst(ctx.root.Position, skill.radius, Color3.fromRGB(150, 220, 255))
	return true
end

handlers.healing_light = function(ctx, skill)
	local now = os.clock()
	for _, character in alliesNear(ctx.root.Position, skill.healRadius) do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			Combat.heal(character, humanoid.MaxHealth * skill.heal)
			table.insert(regens, { character = character, perSecond = humanoid.MaxHealth * skill.regen, untilTime = now + skill.regenTime })
		end
	end
	Combat.burst(ctx.root.Position, 14, Color3.fromRGB(255, 225, 120))
	return true
end

handlers.holy_nova = function(ctx, skill)
	for _, model in Combat.targetsNear(ctx.root.Position, skill.radius) do
		local amount, crit = Combat.rollDamage(ctx.attack * skill.multiplier)
		if model:GetAttribute("Void") then
			amount *= skill.voidMultiplier
		end
		Combat.damage(model, amount, ctx.player, crit)
	end
	healAllies(ctx, skill.healRadius, skill.heal)
	Combat.burst(ctx.root.Position, skill.radius, Color3.fromRGB(255, 235, 150))
	return true
end

-- Beast Tamer. Taming.luau and Companions.luau do the work.
handlers.tame_beast = function(ctx, skill)
	return Taming.tameBeast(ctx.player, ctx.root.Position, skill)
end

handlers.call_of_the_wild = function(ctx, skill)
	return Companions.callOfTheWild(ctx.player, skill)
end

local function onUseSkill(player: Player, slot: any, aim: any, locked: any)
	if slot ~= 1 and slot ~= 2 then
		return
	end
	local character = player.Character
	if not character or not Combat.isAlive(character) then
		return
	end
	local info = ClassData.get(player:GetAttribute("Class"))
	local skill = info and SkillData.forClass(info.id, slot)
	local root = Combat.rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not info or not skill or not root or not humanoid then
		return
	end
	if skill.pending then
		toastEvent:FireClient(player, skill.pending)
		return
	end
	local now = os.clock()
	local ready = readyAt[player] or {}
	readyAt[player] = ready
	if now < (ready[slot] or 0) - 0.15 then
		return -- still cooling down (a little slack for network delay)
	end
	if (mana[player] or 0) < skill.mana then
		toastEvent:FireClient(player, "Not enough mana")
		return
	end

	local direction = if typeof(aim) == "Vector3" and isFinite(aim) then flat(aim) else Vector3.zero
	if direction.Magnitude < 0.01 then
		direction = flat(root.CFrame.LookVector)
	end
	local lockedModel: Model? = nil
	if typeof(locked) == "Instance" and locked:IsA("Model") and Combat.isAlive(locked) then
		local lockedRoot = Combat.rootOf(locked)
		if lockedRoot and (lockedRoot.Position - root.Position).Magnitude <= Config.LOCK_RANGE * 1.3 then
			lockedModel = locked
		end
	end
	local ctx: Context = {
		player = player,
		character = character,
		root = root,
		humanoid = humanoid,
		info = info,
		attack = Progression.attack(info.attack, level(player)),
		aim = direction.Unit,
		locked = lockedModel,
	}
	local handler = handlers[skill.id]
	if not handler or not handler(ctx, skill) then
		return
	end
	Combat.noteAction(player, "skill") -- sudden moves startle passive creatures
	mana[player] = (mana[player] or 0) - skill.mana
	ready[slot] = now + skill.cooldown
	publish(player)
	usedEvent:FireClient(player, slot, skill.cooldown)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		Skills.refill(player)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		Skills.refill(player) -- levelling up tops up mana, like health
	end)
end

function Skills.start()
	Net.event("UseSkill").OnServerEvent:Connect(onUseSkill)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		mana[player] = nil
		readyAt[player] = nil
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < REGEN_STEP then
			return
		end
		local step = accumulated
		accumulated = 0
		for player, current in mana do
			local max = Skills.maxMana(player)
			if current < max and player.Character and Combat.isAlive(player.Character) then
				mana[player] = math.min(max, current + Progression.manaRegen(max) * step)
				publish(player)
			end
		end
		-- Healing Light's heal over time.
		local now = os.clock()
		for i = #regens, 1, -1 do
			local regen = regens[i]
			if now > regen.untilTime or not regen.character.Parent then
				table.remove(regens, i)
			else
				local humanoid = regen.character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + regen.perSecond * step)
				end
			end
		end
	end)
end

return Skills
