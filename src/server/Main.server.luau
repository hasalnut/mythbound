-- Server entry point. Order matters: remotes and the world must exist before anyone spawns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) -- creates the RemoteEvents

local Combat = require(script.Parent:WaitForChild("Combat"))
local Companions = require(script.Parent:WaitForChild("Companions"))
local Creature = require(script.Parent:WaitForChild("Creature"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local Hearthmoor = require(script.Parent:WaitForChild("Hearthmoor"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PlayerSetup = require(script.Parent:WaitForChild("PlayerSetup"))
local Quests = require(script.Parent:WaitForChild("Quests"))
local Skills = require(script.Parent:WaitForChild("Skills"))
local Taming = require(script.Parent:WaitForChild("Taming"))

PlayerData.start() -- starts loading saves as players join
Quests.start()
Inventory.start()
Drops.start()
Companions.start()
Taming.start() -- before the world is built, so every creature gets its feed prompt

-- Everyone who damaged a creature gets its full XP, quest credit and their own loot.
-- A companion's bites count for its owner.
Creature.onDefeated(function(data, players, position)
	for _, player in players do
		PlayerData.addXP(player, data.xp, `{data.name} defeated`)
		Quests.recordDefeat(player, data.id)
	end
	Drops.forDefeat(data.id, position, players)
end)

PlayerSetup.start() -- turns off automatic spawning first
Combat.start()
Skills.start()
Hearthmoor.build()

workspace:SetAttribute("WorldReady", true)
