-- Companions: limits, taming numbers and stat formulas (docs/game-data.md, CLAUDE.md > Taming).
-- A player owns up to STABLE_SIZE companions (saved in PlayerData.companions) and can have
-- LIMIT of them out at once, or TAMER_LIMIT as a Beast Tamer.

local CreatureData = require(script.Parent:WaitForChild("CreatureData"))

local CompanionData = {}

CompanionData.STABLE_SIZE = 6 -- companions a player can own
CompanionData.LIMIT = 1 -- how many can be out at once
CompanionData.TAMER_LIMIT = 3 -- ... for the Beast Tamer
CompanionData.TAMER_CLASS = "tamer"
CompanionData.MAX_NAME = 24

CompanionData.KNOCKOUT_TIME = 30 -- seconds a knocked-out companion takes to recover
CompanionData.FOCUS_TIME = 8 -- seconds a companion keeps attacking what its owner last hit
CompanionData.THREAT_TIME = 6 -- ... and what last bit its owner or itself

-- Taming by feeding (the trust meter). Distances in studs.
CompanionData.FEED_RANGE = 14 -- how close you must be for the Feed prompt
CompanionData.FEED_GAP = 2 -- seconds between feeds (it is still eating)
CompanionData.FEED_TIMEOUT = 12 -- it loses interest if not fed again within this
CompanionData.CALM_RADIUS = 10 -- stepping this far from where you started feeding fails
CompanionData.STARTLE_RADIUS = 30 -- a dash, attack or skill this close scares passive creatures
CompanionData.JUMP_SPEED = 25 -- moving upwards faster than this counts as a jump
CompanionData.WARY_TIME = 8 -- after a failed attempt it won't take food for this long

-- How many companions a class can have out at once.
function CompanionData.limit(classId: any): number
	return if classId == CompanionData.TAMER_CLASS then CompanionData.TAMER_LIMIT else CompanionData.LIMIT
end

-- Whether a class can bring this creature out. Beasts tamed with Tame Beast need a Beast Tamer.
function CompanionData.canBringOut(classId: any, creatureId: string): boolean
	local creature = CreatureData.creatures[creatureId]
	if not creature then
		return false
	end
	return not creature.tamerOnly or classId == CompanionData.TAMER_CLASS
end

-- Companion HP = creature HP x 1.6 x (1 + 0.1 x (player level - 1)).
function CompanionData.maxHealth(creature: CreatureData.CreatureInfo, level: number): number
	return math.floor(creature.maxHealth * 1.6 * (1 + 0.1 * (level - 1)) + 0.5)
end

-- Companion damage = creature damage (6 if none) x 1.5 x (1 + 0.12 x (player level - 1)),
-- x 1.25 for a Beast Tamer.
function CompanionData.damage(creature: CreatureData.CreatureInfo, level: number, classId: any): number
	local base = if creature.damage > 0 then creature.damage else 6
	local amount = base * 1.5 * (1 + 0.12 * (level - 1))
	if classId == CompanionData.TAMER_CLASS then
		amount *= 1.25
	end
	return amount
end

return CompanionData
