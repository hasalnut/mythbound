-- Taming. Two ways to gain a companion, both decided here on the server:
--
-- Feeding (any class): creatures with `tameFood` (the fox) get a Feed prompt. Each feed uses one
-- item and fills the trust meter by 1 / tameFeeds; the creature stands still while it eats.
-- The attempt fails if the tamer attacks, dashes, uses a skill, jumps or steps too far away, if
-- anyone startles or hurts the creature, or if it isn't fed again in time. Then it bolts, the
-- food already given is lost, and it stays wary for a while. Only one player can tame a
-- creature at a time, and whoever finishes the taming owns it.
-- A player carrying food a passive creature likes doesn't scare it, so they can walk up to it.
--
-- Tame Beast (the Beast Tamer's Q): works on `tamerOnly` creatures (wolves, boars) that are
-- below the skill's health threshold. Chance = baseChance + missingBonus x missing health.
--
-- Either way the wild creature leaves through Creature.remove (no XP, loot or quest credit)
-- and Companions.add puts a companion where it stood.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CompanionData = require(Shared:WaitForChild("CompanionData"))
local ItemData = require(Shared:WaitForChild("ItemData"))
local Net = require(Shared:WaitForChild("Net"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Companions = require(script.Parent:WaitForChild("Companions"))
local Creature = require(script.Parent:WaitForChild("Creature"))
local Interactables = require(script.Parent:WaitForChild("Interactables"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))

local Taming = {}

local TAMED_COLOR = Color3.fromRGB(255, 214, 110)
local FAILED_COLOR = Color3.fromRGB(190, 190, 200)

type Session = {
	player: Player,
	creature: any, -- a Creature
	feeds: number,
	origin: Vector3, -- where the tamer stood at the first feed
	lastFeed: number,
}

local sessions: { [any]: Session } = {} -- by creature
local byPlayer: { [Player]: Session } = {}
local waryUntil: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- by creature

local tamingEvent = Net.event("Taming")
local toastEvent = Net.event("Toast")

local function lower(name: string): string
	return string.lower(name)
end

local function clear(session: Session)
	if sessions[session.creature] == session then
		sessions[session.creature] = nil
	end
	if byPlayer[session.player] == session then
		byPlayer[session.player] = nil
	end
end

-- Ends an attempt: the creature bolts from `from` (or the tamer) and won't eat for a while.
local function fail(session: Session, reason: string, from: Vector3?)
	clear(session)
	local creature = session.creature
	waryUntil[creature] = os.clock() + CompanionData.WARY_TIME
	if session.player.Parent then
		tamingEvent:FireClient(session.player, creature.model, 0, "failed", reason)
	end
	if creature.state ~= "Dead" then
		Combat.spark(creature.root.Position + Vector3.new(0, 2, 0), FAILED_COLOR)
	end
	if creature.state == "Held" then
		local character = session.player.Character
		local root = character and Combat.rootOf(character)
		creature:flee(from or (if root then root.Position else session.origin), 4)
	end
end

local function succeed(session: Session)
	clear(session)
	local creature = session.creature
	local data = creature.data
	local position = creature.root.Position
	local _, yaw = creature.root.CFrame:ToOrientation()
	creature:remove("tamed")
	Companions.add(session.player, data, position, yaw)
	tamingEvent:FireClient(session.player, nil, 1, "tamed", data.name)
	Combat.burst(position, 8, TAMED_COLOR)
end

-- The Feed prompt on a creature was used by `player`.
local function feed(creature: any, player: Player)
	local data = creature.data
	local item = ItemData.items[data.tameFood]
	local character = player.Character
	local root = character and Combat.rootOf(character)
	if not item or not character or not root or not Combat.isAlive(character) or creature.state == "Dead" then
		return
	end
	if (root.Position - creature.root.Position).Magnitude > CompanionData.FEED_RANGE + 6 then
		return -- further than the prompt reaches
	end
	local now = os.clock()
	local name = lower(data.name)
	local session = sessions[creature]
	if session and session.player ~= player then
		toastEvent:FireClient(player, `Someone else is taming this {name}`)
		return
	end
	if not session then
		if (waryUntil[creature] or 0) > now then
			toastEvent:FireClient(player, `The {name} is too wary to eat right now`)
			return
		end
		local ok, reason = Companions.canTame(player, data)
		if not ok then
			toastEvent:FireClient(player, reason or "You can't tame that")
			return
		end
	elseif now - session.lastFeed < CompanionData.FEED_GAP then
		toastEvent:FireClient(player, `The {name} is still eating`)
		return
	end
	if not Inventory.remove(player, item.id, 1) then
		toastEvent:FireClient(player, `You need {item.name} to feed a {name}. Wolves and boars drop it`)
		return
	end
	if not session then
		local other = byPlayer[player]
		if other then
			fail(other, "You turned to another creature")
		end
		local new: Session = { player = player, creature = creature, feeds = 0, origin = root.Position, lastFeed = now }
		sessions[creature] = new
		byPlayer[player] = new
		creature:hold(character)
		session = new
	end
	session.feeds += 1
	session.lastFeed = now
	Combat.spark(creature.root.Position + Vector3.new(0, 2, 0), item.color)
	local needed = data.tameFeeds or 1
	if session.feeds >= needed then
		succeed(session)
	else
		tamingEvent:FireClient(player, creature.model, session.feeds / needed, "progress", needed - session.feeds)
	end
end

-- The calm checks, every frame for the few attempts in progress.
local function watch()
	local now = os.clock()
	for creature, session in sessions do
		local player = session.player
		local character = player.Character
		local root = character and Combat.rootOf(character)
		local name = lower(creature.data.name)
		if creature.state == "Dead" then
			clear(session)
			if player.Parent then
				tamingEvent:FireClient(player, nil, 0, "failed", `The {name} is gone`)
			end
		elseif not player.Parent or not character or not root or not Combat.isAlive(character) then
			fail(session, "", session.origin)
		elseif creature.state ~= "Held" then
			fail(session, `Something startled the {name}`)
		elseif (root.Position - session.origin).Magnitude > CompanionData.CALM_RADIUS then
			fail(session, `You moved too far and the {name} bolted`)
		elseif root.AssemblyLinearVelocity.Y > CompanionData.JUMP_SPEED then
			fail(session, `You jumped and startled the {name}`)
		elseif now - session.lastFeed > CompanionData.FEED_TIMEOUT then
			fail(session, `The {name} lost interest`)
		end
	end
end

-- The Beast Tamer's Tame Beast, cast from `origin`. Returns true if the skill was used (mana
-- is spent whether or not the beast gives in), false if there was nothing to use it on.
function Taming.tameBeast(player: Player, origin: Vector3, skill: { [string]: any }): boolean
	local function weakened(creature: any): boolean
		return creature.data.tamerOnly == true and creature.humanoid.Health < creature.humanoid.MaxHealth * skill.threshold
	end
	local creature = Creature.nearest(origin, skill.range, weakened)
	if not creature then
		local healthy = Creature.nearest(origin, skill.range, function(other: any): boolean
			return other.data.tamerOnly == true
		end)
		toastEvent:FireClient(player, if healthy
			then `Weaken the {lower(healthy.data.name)} below half health first`
			else "No beast in range. Tame Beast works on weakened wolves and boars")
		return false
	end
	local data = creature.data
	local ok, reason = Companions.canTame(player, data)
	if not ok then
		toastEvent:FireClient(player, reason or "You can't tame that")
		return false
	end
	local missing = 1 - creature.humanoid.Health / creature.humanoid.MaxHealth
	local chance = math.clamp(skill.baseChance + skill.missingBonus * missing, 0, 1)
	local position = creature.root.Position
	if math.random() < chance then
		local _, yaw = creature.root.CFrame:ToOrientation()
		creature:remove("tamed")
		Companions.add(player, data, position, yaw)
		tamingEvent:FireClient(player, nil, 1, "tamed", data.name)
		Combat.burst(position, 10, TAMED_COLOR)
	else
		toastEvent:FireClient(player, `The {lower(data.name)} resists! ({math.floor(chance * 100 + 0.5)}% chance)`)
		Combat.spark(position + Vector3.new(0, 3, 0), FAILED_COLOR)
	end
	return true
end

local started = false
function Taming.start()
	if started then
		return
	end
	started = true

	-- Every creature that can be fed gets a Feed prompt as it spawns.
	Creature.onSpawned(function(creature: any)
		local data = creature.data
		local item = data.tameFood and ItemData.items[data.tameFood]
		if item then
			Interactables.prompt(creature.root, `Feed {item.name}`, data.name, function(player: Player)
				feed(creature, player)
			end, CompanionData.FEED_RANGE)
		end
	end)

	-- A player carrying food a passive creature likes doesn't scare it.
	Creature.setCalmCheck(function(creature: any, player: Player): boolean
		local food = creature.data.tameFood
		return food ~= nil and Inventory.count(player, food) > 0
	end)

	-- Sudden moves (attacks, dashes, skills) end any attempt nearby and scatter passive creatures.
	Combat.onAction(function(player: Player, _kind: string, position: Vector3)
		for creature, session in sessions do
			if creature.state ~= "Dead" and (creature.root.Position - position).Magnitude <= CompanionData.STARTLE_RADIUS then
				local name = lower(creature.data.name)
				fail(session, if session.player == player then `You startled the {name}` else `Something startled the {name}`, position)
			end
		end
		Creature.startle(position, CompanionData.STARTLE_RADIUS)
	end)

	-- Hurting a creature that is being fed ends the attempt.
	Combat.onDamage(function(model: Model)
		local creature = Creature.find(model)
		local session = creature and sessions[creature]
		if session then
			fail(session, `Something hurt the {lower(creature.data.name)}`)
		end
	end)

	RunService.Heartbeat:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local session = byPlayer[player]
		if session then
			fail(session, "", session.origin)
		end
	end)
end

return Taming
