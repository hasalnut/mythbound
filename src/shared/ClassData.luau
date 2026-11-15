-- The five classes. Numbers come from docs/game-data.md, converted to studs
-- (ranges and speeds multiplied by about 3.5, walk speeds tuned for Roblox).

export type ClassInfo = {
	id: string,
	name: string,
	tagline: string,
	description: string,
	maxHealth: number,
	mana: number, -- MP at level 1
	walkSpeed: number,
	attack: number,
	damageReduction: number,
	style: string, -- "Melee" or "Ranged"
	range: number, -- melee reach in studs
	arc: number, -- melee arc in degrees
	interval: number, -- seconds between basic attacks
	projectileSpeed: number,
	projectileColor: Color3,
	arrow: boolean,
	voidMultiplier: number, -- damage multiplier against void creatures
	maxCompanions: number,
	canTameMythic: boolean,
	color: Color3, -- UI and weapon accent colour
	weapon: string,
}

local ClassData = {}

ClassData.order = { "ninja", "tank", "mage", "priest", "tamer" }

ClassData.classes = {
	ninja = {
		id = "ninja",
		name = "Ninja",
		tagline = "Silent assassin",
		description = "Slips through battle unseen. Enemies notice you from half as far away. Lightning-fast twin daggers.",
		maxHealth = 110,
		mana = 80,
		walkSpeed = 22,
		attack = 12,
		damageReduction = 0.10,
		style = "Melee",
		range = 11,
		arc = 120,
		interval = 0.33,
		projectileSpeed = 0,
		projectileColor = Color3.fromRGB(220, 220, 230),
		arrow = false,
		voidMultiplier = 1,
		maxCompanions = 1,
		canTameMythic = false,
		color = Color3.fromRGB(200, 60, 60),
		weapon = "daggers",
	},
	tank = {
		id = "tank",
		name = "Tank",
		tagline = "Unbreakable guardian",
		description = "Shrugs off blows that would fell anyone else. Takes 45% less damage and swings a heavy sword in a wide arc.",
		maxHealth = 230,
		mana = 60,
		walkSpeed = 17,
		attack = 12,
		damageReduction = 0.45,
		style = "Melee",
		range = 13,
		arc = 143,
		interval = 0.7,
		projectileSpeed = 0,
		projectileColor = Color3.fromRGB(220, 220, 230),
		arrow = false,
		voidMultiplier = 1,
		maxCompanions = 1,
		canTameMythic = false,
		color = Color3.fromRGB(90, 140, 220),
		weapon = "sword_shield",
	},
	mage = {
		id = "mage",
		name = "Mage",
		tagline = "Arcane destroyer",
		description = "Hurls bolts of violet fire from range. Fragile up close, devastating from afar.",
		maxHealth = 90,
		mana = 150,
		walkSpeed = 18,
		attack = 13,
		damageReduction = 0,
		style = "Ranged",
		range = 0,
		arc = 0,
		interval = 0.5,
		projectileSpeed = 125,
		projectileColor = Color3.fromRGB(170, 90, 255),
		arrow = false,
		voidMultiplier = 1,
		maxCompanions = 1,
		canTameMythic = false,
		color = Color3.fromRGB(150, 90, 230),
		weapon = "staff",
	},
	priest = {
		id = "priest",
		name = "Priest",
		tagline = "Light and healing",
		description = "Calls down holy light that deals double damage to creatures of the Void. Healing arrives with class skills.",
		maxHealth = 125,
		mana = 130,
		walkSpeed = 18,
		attack = 10,
		damageReduction = 0.12,
		style = "Ranged",
		range = 0,
		arc = 0,
		interval = 0.55,
		projectileSpeed = 120,
		projectileColor = Color3.fromRGB(255, 215, 110),
		arrow = false,
		voidMultiplier = 2,
		maxCompanions = 1,
		canTameMythic = false,
		color = Color3.fromRGB(240, 200, 90),
		weapon = "holy_staff",
	},
	tamer = {
		id = "tamer",
		name = "Beast Tamer",
		tagline = "Master of the wild",
		description = "Fires arrows and befriends beasts. Keeps three companions at once and is the only class that can tame mythic creatures.",
		maxHealth = 135,
		mana = 90,
		walkSpeed = 19,
		attack = 9,
		damageReduction = 0.15,
		style = "Ranged",
		range = 0,
		arc = 0,
		interval = 0.5,
		projectileSpeed = 190,
		projectileColor = Color3.fromRGB(150, 110, 70),
		arrow = true,
		voidMultiplier = 1,
		maxCompanions = 3,
		canTameMythic = true,
		color = Color3.fromRGB(90, 170, 90),
		weapon = "bow",
	},
} :: { [string]: ClassInfo }

function ClassData.get(id: any): ClassInfo?
	if typeof(id) ~= "string" then
		return nil
	end
	return ClassData.classes[id]
end

return ClassData
