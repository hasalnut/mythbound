-- Creatures that live around Hearthmoor. Numbers from docs/game-data.md, converted to studs.

export type CreatureInfo = {
	id: string,
	name: string,
	maxHealth: number,
	damage: number,
	walkSpeed: number,
	behaviour: string, -- "Hostile" attacks on sight, "Neutral" only fights back, "Passive" flees
	pack: boolean, -- when one is attacked or spots a player, nearby ones of the same kind join in
	aggroRange: number,
	attackRange: number,
	attackInterval: number,
	windup: number, -- seconds of red warning before a bite lands
	leash: number, -- gives up the chase this far from home
	xp: number,
	scale: number,
	color: Color3,
	accent: Color3,
	respawn: number,
	isVoid: boolean,
}

local CreatureData = {}

CreatureData.creatures = {
	wolf = {
		id = "wolf",
		name = "Wolf",
		maxHealth = 60,
		damage = 8,
		walkSpeed = 18,
		behaviour = "Hostile",
		pack = true,
		aggroRange = 55,
		attackRange = 6,
		attackInterval = 1.3,
		windup = 0.45,
		leash = 150,
		xp = 15,
		scale = 1.1,
		color = Color3.fromRGB(120, 124, 132),
		accent = Color3.fromRGB(215, 215, 220),
		respawn = 20,
		isVoid = false,
	},
	boar = {
		id = "boar",
		name = "Boar",
		maxHealth = 55,
		damage = 7,
		walkSpeed = 15,
		behaviour = "Neutral",
		pack = false,
		aggroRange = 0,
		attackRange = 6,
		attackInterval = 1.4,
		windup = 0.5,
		leash = 120,
		xp = 12,
		scale = 1.0,
		color = Color3.fromRGB(105, 72, 48),
		accent = Color3.fromRGB(235, 225, 205),
		respawn = 25,
		isVoid = false,
	},
} :: { [string]: CreatureInfo }

return CreatureData
