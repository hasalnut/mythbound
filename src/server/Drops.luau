-- Loot on the ground. In co-op every player gets their own drops: only the owner sees a drop
-- (DropSpawned goes to them alone) and only they can pick it up, by walking over it.
-- The server tracks every drop and decides pickups; clients just draw them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local Net = require(Shared:WaitForChild("Net"))
local Build = require(script.Parent:WaitForChild("Build"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))

local Drops = {}

local PICKUP_RANGE = 7
local LIFETIME = 90
local CHECK_INTERVAL = 0.2

type Drop = { id: number, owner: Player, item: string, count: number, position: Vector3, expires: number }

local drops: { Drop } = {}
local nextId = 0

local spawnedEvent = Net.event("DropSpawned")
local takenEvent = Net.event("DropTaken")
local toastEvent = Net.event("Toast")

function Drops.spawn(owner: Player, itemId: string, count: number, near: Vector3)
	local angle = math.random() * math.pi * 2
	local x = near.X + math.cos(angle) * 2.5
	local z = near.Z + math.sin(angle) * 2.5
	local position = Vector3.new(x, Build.groundY(x, z) + 1, z)
	nextId += 1
	table.insert(drops, { id = nextId, owner = owner, item = itemId, count = count, position = position, expires = os.clock() + LIFETIME })
	spawnedEvent:FireClient(owner, nextId, itemId, count, position)
end

-- Rolls a creature's loot table separately for every player who helped defeat it.
function Drops.forDefeat(creatureId: string, position: Vector3, players: { Player })
	local loot = ItemData.drops[creatureId]
	if not loot then
		return
	end
	for _, player in players do
		for _, entry in loot do
			if math.random() < entry.chance then
				Drops.spawn(player, entry.item, math.random(entry.min, entry.max), position)
			end
		end
	end
end

local function check()
	local now = os.clock()
	for i = #drops, 1, -1 do
		local drop = drops[i]
		local owner = drop.owner
		if not owner.Parent then
			table.remove(drops, i)
		elseif now > drop.expires then
			table.remove(drops, i)
			takenEvent:FireClient(owner, drop.id)
		else
			local character = owner.Character
			local root = character and Combat.rootOf(character)
			if root and Combat.isAlive(character) and (root.Position - drop.position).Magnitude <= PICKUP_RANGE then
				local added = Inventory.add(owner, drop.item, drop.count)
				if added > 0 then
					toastEvent:FireClient(owner, `+{added} {ItemData.items[drop.item].name}`)
				end
				if added >= drop.count then
					table.remove(drops, i)
					takenEvent:FireClient(owner, drop.id)
				else
					drop.count -= added -- bag full: the rest stays on the ground
				end
			end
		end
	end
end

function Drops.start()
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= CHECK_INTERVAL then
			accumulated = 0
			check()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for i = #drops, 1, -1 do
			if drops[i].owner == player then
				table.remove(drops, i)
			end
		end
	end)
end

return Drops
