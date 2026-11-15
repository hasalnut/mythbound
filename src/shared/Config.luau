-- Game-wide numbers shared by the server and the client.
-- Distances are in studs (1 stud is about 0.28 m; a default character is about 5 studs tall).

local Config = {
	-- Combat
	CRIT_CHANCE = 0.12,
	CRIT_MULT = 1.7,
	AUTO_AIM_RANGE = 95, -- ranged attacks curve towards a target this close in front of you
	AUTO_AIM_ANGLE = math.rad(35),
	PROJECTILE_LIFETIME = 1.6,
	LOCK_RANGE = 110,

	-- Dash: a short burst of speed with a moment of invulnerability
	DASH_SPEED = 75,
	DASH_TIME = 0.2,
	DASH_COOLDOWN = 2.2,
	DASH_IFRAMES = 0.3,

	RESPAWN_DELAY = 3,

	-- World (Hearthmoor is centred on 0, 0; north is -Z)
	SPAWN_POSITION = Vector3.new(0, 0.5, 49),
	VILLAGE_RADIUS = 165,
	MAP_HALF = 440,

	TAG_DAMAGEABLE = "Damageable",
}

return Config
