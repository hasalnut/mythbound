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
	fleeRange: number?, -- passive creatures run from players this close (unless calmed by food they like)
	fleeSpeed: number?, -- how fast it runs away
	tameFood: string?, -- item id any class can feed it to tame it
	tameFeeds: number?, -- feeds needed to fill the trust meter
	tamerOnly: boolean?, -- tamed only with the Beast Tamer's Tame Beast skill; only a Beast Tamer can bring it out
}

local CreatureData = {}

CreatureData.TAMED_RESPAWN = 60 -- seconds before a tamed creature's place in the wild is refilled

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
		respawn = 45,
		isVoid = false,
		tamerOnly = true,
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
		respawn = 45,
		isVoid = false,
		tamerOnly = true,
	},
	fox = {
		id = "fox",
		name = "Fox",
		maxHealth = 30,
		damage = 6,
		walkSpeed = 17,
		behaviour = "Passive",
		pack = false,
		aggroRange = 0,
		attackRange = 5,
		attackInterval = 1.2,
		windup = 0.35,
		leash = 140,
		xp = 0,
		scale = 0.7,
		color = Color3.fromRGB(214, 120, 50),
		accent = Color3.fromRGB(245, 238, 225),
		respawn = 45,
		isVoid = false,
		fleeRange = 25,
		fleeSpeed = 24,
		tameFood = "meat",
		tameFeeds = 3,
	},
} :: { [string]: CreatureInfo }

-- True for creatures that can become companions (by feeding, or with Tame Beast).
function CreatureData.tameable(id: any): boolean
	local data = if typeof(id) == "string" then CreatureData.creatures[id] else nil
	return data ~= nil and (data.tameFood ~= nil or data.tamerOnly == true)
end

return CreatureData
