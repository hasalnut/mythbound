-- Items, recipes and where things come from. From docs/game-data.md.
-- Inventories are saved per player (PlayerData.inventory: { [itemId]: count }).

export type Item = {
	id: string,
	name: string,
	description: string,
	color: Color3, -- placeholder icon colour until real icons exist
	usable: boolean?, -- can be used from the inventory (or its hotkey)
}

export type Recipe = {
	id: string, -- the item it makes
	ingredients: { [string]: number },
	count: number,
}

local ItemData = {}

ItemData.MAX_STACK = 99

ItemData.items = {
	meat = { id = "meat", name = "Meat", description = "From hunted animals. Foxes love it.", color = Color3.fromRGB(190, 80, 70) },
	apple = { id = "apple", name = "Apple", description = "Crisp and red, from the village trees.", color = Color3.fromRGB(220, 50, 45) },
	wheat = { id = "wheat", name = "Wheat", description = "A golden bundle from the field.", color = Color3.fromRGB(232, 196, 92) },
	honey = { id = "honey", name = "Honey", description = "Sticky and sweet. Mind the bees.", color = Color3.fromRGB(240, 165, 40) },
	cookie = { id = "cookie", name = "Cookie", description = "Fairies adore them. The Fairy Queen wants three.", color = Color3.fromRGB(190, 135, 80) },
	healing_potion = { id = "healing_potion", name = "Healing Potion", description = "Restores 45% of your health. Use with H.", color = Color3.fromRGB(235, 70, 120), usable = true },
} :: { [string]: Item }

-- The order items are shown in the inventory.
ItemData.order = { "healing_potion", "meat", "apple", "wheat", "honey", "cookie" }

ItemData.recipes = {
	{ id = "cookie", ingredients = { wheat = 1, honey = 1 }, count = 1 },
	{ id = "healing_potion", ingredients = { apple = 1, honey = 1 }, count = 1 },
} :: { Recipe }

ItemData.POTION_HEAL = 0.45 -- fraction of max health
ItemData.POTION_COOLDOWN = 1

-- What creatures drop when defeated: item, min, max, chance (0-1).
ItemData.drops = {
	wolf = { { item = "meat", min = 1, max = 2, chance = 1 } },
	boar = { { item = "meat", min = 1, max = 2, chance = 1 } },
}

-- Gathering spots in Hearthmoor: seconds between gathers (per player).
ItemData.gather = {
	wheat = { item = "wheat", min = 1, max = 1, cooldown = 30, verb = "Harvest", object = "Wheat field" },
	honey = { item = "honey", min = 1, max = 1, cooldown = 35, verb = "Collect honey", object = "Beehive", sting = { chance = 0.25, damage = 6 } },
	apple = { item = "apple", min = 1, max = 2, cooldown = 40, verb = "Pick apples", object = "Apple tree" },
}

function ItemData.get(id: any): Item?
	return if typeof(id) == "string" then ItemData.items[id] else nil
end

function ItemData.recipe(id: any): Recipe?
	for _, recipe in ItemData.recipes do
		if recipe.id == id then
			return recipe
		end
	end
	return nil
end

return ItemData
