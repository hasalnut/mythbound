-- Each player's items (saved in PlayerData), gathering, crafting at the workbench and using items.
-- The server owns every count; clients only ask (UseItem, Craft) and are sent their counts back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local Net = require(Shared:WaitForChild("Net"))
local Combat = require(script.Parent:WaitForChild("Combat"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Inventory = {}

local WORKBENCH_RANGE = 20 -- studs; crafting only works standing at the workbench

local inventoryEvent = Net.event("Inventory")
local toastEvent = Net.event("Toast")

local lastPotion: { [Player]: number } = {}
local lastGather: { [Player]: { [string]: number } } = {}
local workbenchPosition: Vector3? = nil

local function items(player: Player): { [string]: number }?
	local data = PlayerData.get(player)
	return data and data.inventory
end

function Inventory.count(player: Player, itemId: string): number
	local bag = items(player)
	return bag and bag[itemId] or 0
end

function Inventory.send(player: Player)
	inventoryEvent:FireClient(player, items(player) or {})
end

-- Adds items, up to the stack limit. Returns how many fitted.
function Inventory.add(player: Player, itemId: string, count: number): number
	local bag = items(player)
	if not bag or not ItemData.get(itemId) or count <= 0 then
		return 0
	end
	local have = bag[itemId] or 0
	local added = math.min(count, ItemData.MAX_STACK - have)
	if added <= 0 then
		return 0
	end
	bag[itemId] = have + added
	PlayerData.markDirty(player)
	Inventory.send(player)
	return added
end

-- Takes items away if the player has enough. Returns true if it did.
function Inventory.remove(player: Player, itemId: string, count: number): boolean
	local bag = items(player)
	if not bag or (bag[itemId] or 0) < count then
		return false
	end
	bag[itemId] -= count
	if bag[itemId] <= 0 then
		bag[itemId] = nil
	end
	PlayerData.markDirty(player)
	Inventory.send(player)
	return true
end

function Inventory.setWorkbench(position: Vector3)
	workbenchPosition = position
end

-- Gathers from a spot (`kind` is a key of ItemData.gather; `spotId` names the particular
-- beehive, tree or field, so each has its own timer per player).
function Inventory.gather(player: Player, kind: string, spotId: string)
	local spec = ItemData.gather[kind]
	local character = player.Character
	if not spec or not character or not Combat.isAlive(character) or not items(player) then
		return
	end
	local timers = lastGather[player] or {}
	lastGather[player] = timers
	local now = os.clock()
	local waitLeft = (timers[spotId] or -math.huge) + spec.cooldown - now
	if waitLeft > 0 then
		toastEvent:FireClient(player, `Nothing to gather yet ({math.ceil(waitLeft)}s)`)
		return
	end
	timers[spotId] = now
	local count = math.random(spec.min, spec.max)
	local added = Inventory.add(player, spec.item, count)
	local item = ItemData.items[spec.item]
	if added > 0 then
		toastEvent:FireClient(player, `+{added} {item.name}`)
	else
		toastEvent:FireClient(player, `You can't carry more {item.name}`)
	end
	if spec.sting and math.random() < spec.sting.chance then
		Combat.damage(character, spec.sting.damage, nil)
		toastEvent:FireClient(player, "Ouch! A bee stung you")
	end
end

local function onUseItem(player: Player, itemId: any)
	local item = ItemData.get(itemId)
	local character = player.Character
	if not item or not item.usable or not character or not Combat.isAlive(character) then
		return
	end
	if item.id == "healing_potion" then
		local now = os.clock()
		if now - (lastPotion[player] or -100) < ItemData.POTION_COOLDOWN then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		if humanoid.Health >= humanoid.MaxHealth then
			toastEvent:FireClient(player, "You're already at full health")
			return
		end
		if not Inventory.remove(player, item.id, 1) then
			toastEvent:FireClient(player, "No healing potions. Craft one at the workbench")
			return
		end
		lastPotion[player] = now
		Combat.heal(character, humanoid.MaxHealth * ItemData.POTION_HEAL)
		local root = Combat.rootOf(character)
		if root then
			Combat.burst(root.Position, 6, Color3.fromRGB(235, 90, 140))
		end
	end
end

local function onCraft(player: Player, recipeId: any)
	local recipe = ItemData.recipe(recipeId)
	local character = player.Character
	local root = character and Combat.rootOf(character)
	if not recipe or not root or not workbenchPosition then
		return
	end
	if (root.Position - workbenchPosition).Magnitude > WORKBENCH_RANGE then
		toastEvent:FireClient(player, "Stand at the workbench to craft")
		return
	end
	for itemId, need in recipe.ingredients do
		if Inventory.count(player, itemId) < need then
			toastEvent:FireClient(player, `You need {need} {ItemData.items[itemId].name}`)
			return
		end
	end
	if Inventory.count(player, recipe.id) + recipe.count > ItemData.MAX_STACK then
		toastEvent:FireClient(player, "You can't carry any more of those")
		return
	end
	for itemId, need in recipe.ingredients do
		Inventory.remove(player, itemId, need)
	end
	Inventory.add(player, recipe.id, recipe.count)
	toastEvent:FireClient(player, `Crafted {ItemData.items[recipe.id].name}`)
end

function Inventory.start()
	Net.event("UseItem").OnServerEvent:Connect(onUseItem)
	Net.event("Craft").OnServerEvent:Connect(onCraft)
	PlayerData.onLoaded(Inventory.send)
	Players.PlayerRemoving:Connect(function(player)
		lastPotion[player] = nil
		lastGather[player] = nil
	end)
end

return Inventory
