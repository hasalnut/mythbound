-- Client entry point: class select, HUD, controls and effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local ClassSelect = require(script.Parent:WaitForChild("ClassSelect"))
local Controls = require(script.Parent:WaitForChild("Controls"))
local Effects = require(script.Parent:WaitForChild("Effects"))
local HUD = require(script.Parent:WaitForChild("HUD"))
local InventoryUI = require(script.Parent:WaitForChild("InventoryUI"))
local ItemData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemData"))
local QuestTracker = require(script.Parent:WaitForChild("QuestTracker"))

local player = Players.LocalPlayer

-- Our own health bar replaces Roblox's. SetCore can fail if called too early, so retry briefly.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

HUD.init()
QuestTracker.init(HUD.getGui())
InventoryUI.init(player:WaitForChild("PlayerGui"), function()
	return player.Character ~= nil and not HUD.isDialogueOpen() and not ClassSelect.isOpen()
end)
HUD.onChangeClass = function()
	ClassSelect.open()
end

-- The HUD shows only while you have a character and the class screen is closed.
local classScreenOpen = false
local function refreshHUD()
	HUD.setVisible(player.Character ~= nil and not classScreenOpen)
end
ClassSelect.onToggle = function(open: boolean)
	classScreenOpen = open
	if open then
		InventoryUI.close()
	end
	refreshHUD()
end

Controls.start(function()
	return HUD.isDialogueOpen() or ClassSelect.isOpen() or InventoryUI.isOpen()
end)

local firstSpawn = true
local function onCharacter(character: Model)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	camera.CameraSubject = humanoid
	-- Start behind the character, looking the way it faces (towards the Elder on arrival),
	-- instead of keeping whatever angle the menu camera had.
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if root then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		camera.CFrame = CFrame.lookAt(root.Position - look * 16 + Vector3.new(0, 7, 0), root.Position + Vector3.new(0, 2, 0))
	end
	Controls.reset()
	HUD.bindCharacter(character)
	refreshHUD()
	if firstSpawn then
		firstSpawn = false
		HUD.banner("Hearthmoor Village")
		HUD.toast("Talk to Elder Maren to begin")
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

Net.event("DamageNumber").OnClientEvent:Connect(function(model: Model?, position: Vector3, amount: number, kind: string, attacker: Player?)
	Effects.damageNumber(position, amount, kind)
	if attacker == player and model then
		Controls.noteHit(model)
	end
end)

Net.event("Effect").OnClientEvent:Connect(function(kind: string, ...)
	if kind == "swing" then
		Effects.swing(...)
	elseif kind == "bolt" then
		Effects.bolt(...)
	elseif kind == "burst" then
		Effects.burst(...)
	end
end)

Net.event("Dialogue").OnClientEvent:Connect(function(speaker: string, lines: { string })
	HUD.showDialogue(speaker, lines)
end)

Net.event("Toast").OnClientEvent:Connect(function(text: string)
	HUD.toast(text)
end)

Net.event("SkillUsed").OnClientEvent:Connect(function(slot: number, cooldown: number)
	Controls.onSkillUsed(slot, cooldown)
end)

-- Watch every character (yours and other players') for the Ninja's Vanish.
local function watchPlayer(other: Player)
	other.CharacterAdded:Connect(function(character)
		Effects.watchCharacter(character, other == player)
	end)
	if other.Character then
		Effects.watchCharacter(other.Character, other == player)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, other in Players:GetPlayers() do
	watchPlayer(other)
end

Net.event("Inventory").OnClientEvent:Connect(function(counts)
	InventoryUI.setCounts(counts)
end)

Net.event("OpenCrafting").OnClientEvent:Connect(function()
	InventoryUI.openCrafting()
end)

Net.event("DropSpawned").OnClientEvent:Connect(function(id: number, itemId: string, count: number, position: Vector3)
	local item = ItemData.get(itemId)
	if item then
		Effects.showDrop(id, item.color, item.name, count, position)
	end
end)

Net.event("DropTaken").OnClientEvent:Connect(function(id: number)
	Effects.removeDrop(id)
end)

Net.event("QuestUpdate").OnClientEvent:Connect(function(quests)
	QuestTracker.update(quests)
end)

Net.event("LevelUp").OnClientEvent:Connect(function(who: Player, level: number)
	if who.Character then
		Effects.levelUp(who.Character)
	end
	if who == player then
		HUD.banner(`Level {level}!`)
	end
end)

-- First visit: choose a class. The world must exist before the server will spawn us.
ClassSelect.open()
