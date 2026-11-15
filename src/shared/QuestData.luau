-- Quests and the people who give them. Progress is per player and saved (see Quests.luau).
-- Objective kinds: "defeat" (target = creature id). Later: "collect" (item id), "reach" (place).

export type Quest = {
	id: string,
	title: string,
	summary: string, -- one line for the tracker
	giver: string, -- key into QuestData.givers
	objective: { kind: string, target: string, count: number },
	rewardXp: number,
	gift: { [string]: number }?, -- items handed over when the quest is given
	lines: {
		offer: { string }, -- said when the quest is given
		active: { string }, -- said while it's under way
		ready: { string }, -- said when it's handed in (the reward follows)
	},
}

local QuestData = {}

QuestData.givers = {
	elder = {
		name = "Elder Maren",
		-- Said once every quest from this giver is done.
		idle = {
			"The fence holds, thanks to you. Rest by the fire a while, traveller.",
			"When the ward at the northern gate lifts, the Crossroads will be open to you. Bring friends; the Rift is no place to go alone.",
		},
	},
}

-- Quests in the order they are offered.
QuestData.order = { "wolves_at_the_fence" }

QuestData.quests = {
	wolves_at_the_fence = {
		id = "wolves_at_the_fence",
		title = "Wolves at the Fence",
		summary = "Defeat wolves outside the fence",
		giver = "elder",
		objective = { kind = "defeat", target = "wolf", count = 4 },
		rewardXp = 50,
		gift = { healing_potion = 3 },
		lines = {
			offer = {
				"Welcome to Hearthmoor, traveller. You've arrived in troubled times.",
				"Three nights ago the eastern sky split open. Something vast coils inside the Rift.",
				"Since then the wolves have grown bold. They prowl right up to our fence, west and east of the village.",
				"Drive off four of them. When they glow red they're about to bite: dash out of the way!",
				"The training dummies east of the campfire will take any punishment while you find your feet.",
				"Take these three potions. Press H to drink one when you're hurt. The workbench by the well can make more.",
			},
			active = {
				"The wolves still circle the fence. Four of them, traveller. West or east of the village.",
			},
			ready = {
				"You're back, and in one piece! The village can sleep tonight.",
				"Take this, and my thanks. You grow stronger with every fight.",
			},
		},
	},
} :: { [string]: Quest }

return QuestData
