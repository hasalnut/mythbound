-- Levels and XP. Formulas from docs/game-data.md. One level per player, shared by every class.

local Progression = {}

Progression.MAX_LEVEL = 20

-- XP needed to go from `level` to the next one.
function Progression.xpToNext(level: number): number
	return 40 + 35 * level
end

function Progression.maxHealth(classHealth: number, level: number): number
	return math.floor(classHealth * (1 + 0.12 * (level - 1)) + 0.5)
end

function Progression.maxMana(classMana: number, level: number): number
	return math.floor(classMana * (1 + 0.06 * (level - 1)) + 0.5)
end

-- MP regained per second: 5 plus 2% of max MP.
function Progression.manaRegen(maxMana: number): number
	return 5 + 0.02 * maxMana
end

function Progression.attack(classAttack: number, level: number): number
	return classAttack * (1 + 0.11 * (level - 1))
end

return Progression
