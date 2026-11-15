-- All RemoteEvents live in ReplicatedStorage.Remotes. The server creates them; clients wait for them.
--
-- Client -> server:  ChooseClass(classId), Attack(aimDirection, lockedTarget?), Dash(),
--                    UseSkill(slot, aimDirection, lockedTarget?)
-- Server -> client:  SkillUsed(slot, cooldown) when a skill goes off (starts the HUD cooldown)
-- Items:  client -> server UseItem(itemId), Craft(recipeId)
--         server -> client Inventory(counts), OpenCrafting(), DropSpawned(id, itemId, count, position), DropTaken(id)
-- Server -> client:  DamageNumber(model, position, amount, kind, attacker?), Effect(kind, ...),
--                    Dialogue(speaker, lines), Toast(text), QuestUpdate(quests), LevelUp(player, level)
-- Companions:  client -> server CompanionSetActive(uid, active), CompanionRelease(uid)
--              server -> client Companions(list, limit, stableSize) where each list entry is
--                { uid, id, name, active, allowed, knockedOut (seconds left) }
--              server -> client Taming(creatureModel?, trust 0-1, state, detail): state is
--                "progress" (detail = feeds left), "tamed" (detail = name) or "failed" (detail = why)
--              Feeding itself is a ProximityPrompt, which the server hears directly.
-- Level, XP, XPNext and SavedClass travel as Player attributes, not events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "ChooseClass", "Attack", "Dash", "DamageNumber", "Effect", "Dialogue", "Toast", "QuestUpdate", "LevelUp", "UseSkill", "SkillUsed",
	"Inventory", "UseItem", "Craft", "OpenCrafting", "DropSpawned", "DropTaken",
	"Companions", "Taming", "CompanionSetActive", "CompanionRelease" }

local Net = {}

local isServer = RunService:IsServer()
local folder: Folder

if isServer then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	if isServer then
		return folder:FindFirstChild(name) :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
