-- Class skills. Numbers from docs/game-data.md; distances converted to studs (metres x 3.5).
-- Slot 1 is Q (controller L1), slot 2 is E (controller R1). Skills.luau on the server runs them.
-- `pending` marks a skill that needs a later slice (the Beast Tamer's need companions, Slice 4).

export type Skill = {
	id: string,
	name: string,
	mana: number,
	cooldown: number,
	pending: string?, -- message shown instead of using the skill
	[string]: any, -- skill-specific numbers below
}

local SkillData = {}

SkillData.skills = {
	-- Ninja
	vanish = { id = "vanish", name = "Vanish", mana = 25, cooldown = 10, duration = 6, speedBonus = 0.35, backstab = 3 },
	shuriken_fan = { id = "shuriken_fan", name = "Shuriken Fan", mana = 18, cooldown = 4, count = 5, spread = 10, multiplier = 1.1, speed = 150 },
	-- Tank
	taunt = { id = "taunt", name = "Taunt", mana = 15, cooldown = 8, radius = 77, duration = 6, reduction = 0.4, maxReduction = 0.8 },
	shield_slam = { id = "shield_slam", name = "Shield Slam", mana = 20, cooldown = 6, radius = 19, multiplier = 1.8, stun = 2, knockback = 10.5 },
	-- Mage
	fireball = { id = "fireball", name = "Fireball", mana = 22, cooldown = 2.5, multiplier = 3, radius = 17.5, speed = 110 },
	frost_nova = { id = "frost_nova", name = "Frost Nova", mana = 35, cooldown = 9, radius = 31.5, multiplier = 1.4, freeze = 3 },
	-- Priest (heals reach allies within healRadius)
	healing_light = { id = "healing_light", name = "Healing Light", mana = 30, cooldown = 6, healRadius = 70, heal = 0.35, regen = 0.04, regenTime = 5 },
	holy_nova = { id = "holy_nova", name = "Holy Nova", mana = 30, cooldown = 7, radius = 28, multiplier = 2.2, voidMultiplier = 2, healRadius = 70, heal = 0.10 },
	-- Beast Tamer
	tame_beast = { id = "tame_beast", name = "Tame Beast", mana = 20, cooldown = 2, pending = "Tame Beast arrives with taming" },
	call_of_the_wild = { id = "call_of_the_wild", name = "Call of the Wild", mana = 30, cooldown = 14, pending = "Call of the Wild arrives with companions" },
} :: { [string]: Skill }

-- Each class's skills, in slot order (Q, E).
SkillData.byClass = {
	ninja = { "vanish", "shuriken_fan" },
	tank = { "taunt", "shield_slam" },
	mage = { "fireball", "frost_nova" },
	priest = { "healing_light", "holy_nova" },
	tamer = { "tame_beast", "call_of_the_wild" },
}

function SkillData.forClass(classId: any, slot: number): Skill?
	local ids = if typeof(classId) == "string" then SkillData.byClass[classId] else nil
	local id = ids and ids[slot]
	return if id then SkillData.skills[id] else nil
end

return SkillData
