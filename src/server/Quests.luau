-- Quest progress per player (stored in PlayerData), objectives counted from game events, and
-- what each quest giver says at each stage. Quest definitions live in Shared/QuestData.
-- In co-op a kill counts for everyone who damaged the creature; each player has their own quests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local QuestData = require(Shared:WaitForChild("QuestData"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Quests = {}

local updateEvent = Net.event("QuestUpdate")
local toastEvent = Net.event("Toast")

-- Every quest with this player's status: "available", "active", "ready" or "done".
function Quests.snapshot(player: Player): { { [string]: any } }
	local data = PlayerData.get(player)
	local list = {}
	for _, id in QuestData.order do
		local quest = QuestData.quests[id]
		local state = data and data.quests[id]
		table.insert(list, {
			id = id,
			title = quest.title,
			summary = quest.summary,
			giver = quest.giver,
			giverName = QuestData.givers[quest.giver].name,
			status = if state then state.status else "available",
			progress = if state then state.progress else 0,
			count = quest.objective.count,
		})
	end
	return list
end

function Quests.send(player: Player)
	updateEvent:FireClient(player, Quests.snapshot(player))
end

-- What `giver` says to `player`, moving their quest on where the conversation allows:
-- offering the next quest, reminding them of the current one, or taking it in for the reward.
function Quests.talk(player: Player, giver: string): { string }
	local data = PlayerData.get(player)
	if not data then
		return { "One moment, traveller..." }
	end
	for _, id in QuestData.order do
		local quest = QuestData.quests[id]
		if quest.giver == giver then
			local state = data.quests[id]
			if not state then
				data.quests[id] = { status = "active", progress = 0 }
				PlayerData.markDirty(player)
				toastEvent:FireClient(player, `New quest: {quest.title}`)
				for itemId, count in quest.gift or {} do
					Inventory.add(player, itemId, count)
				end
				Quests.send(player)
				return quest.lines.offer
			elseif state.status == "active" then
				return quest.lines.active
			elseif state.status == "ready" then
				state.status = "done"
				PlayerData.markDirty(player)
				PlayerData.addXP(player, quest.rewardXp, `Quest complete: {quest.title}`)
				Quests.send(player)
				return quest.lines.ready
			end
		end
	end
	return QuestData.givers[giver].idle
end

-- Called for each player who helped defeat a creature.
function Quests.recordDefeat(player: Player, creatureId: string)
	local data = PlayerData.get(player)
	if not data then
		return
	end
	for _, id in QuestData.order do
		local quest = QuestData.quests[id]
		local state = data.quests[id]
		local objective = quest.objective
		if state and state.status == "active" and objective.kind == "defeat" and objective.target == creatureId then
			state.progress = math.min(objective.count, state.progress + 1)
			if state.progress >= objective.count then
				state.status = "ready"
				toastEvent:FireClient(player, `Return to {QuestData.givers[quest.giver].name}`)
			end
			PlayerData.markDirty(player)
			Quests.send(player)
		end
	end
end

function Quests.start()
	PlayerData.onLoaded(Quests.send)
end

return Quests
