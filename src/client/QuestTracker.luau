-- The quest tracker (top right) and the "!" / "?" markers over quest givers. The server sends
-- this player's quests through QuestUpdate; markers exist only on this player's screen, so in
-- co-op each player sees their own.

local Players = game:GetService("Players")

local UI = require(script.Parent:WaitForChild("UI"))

local QuestTracker = {}

local player = Players.LocalPlayer
local panel: Frame
local rows: Frame
local markers: { [string]: BillboardGui } = {}
local lastQuests: { { [string]: any } } = {}

-- Where each quest giver's head is in the world.
local GIVER_PATHS = {
	elder = { "Village", "ElderMaren", "Head" },
}

local function giverHead(giver: string): BasePart?
	local inst: Instance? = workspace
	for _, name in GIVER_PATHS[giver] or {} do
		inst = inst and inst:FindFirstChild(name)
	end
	return if inst and inst:IsA("BasePart") then inst else nil
end

-- Shows `symbol` over the giver, or hides the marker when it is nil. Returns false if the giver
-- hasn't streamed in yet.
local function setMarker(giver: string, symbol: string?): boolean
	local gui = markers[giver]
	if gui and not gui.Parent then
		gui = nil -- removed (e.g. the giver's model was rebuilt); make a new one
	end
	if not gui then
		local head = giverHead(giver)
		if not head then
			return false
		end
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "QuestMarker"
		billboard.ResetOnSpawn = false -- keep it when the player respawns
		billboard.Size = UDim2.fromOffset(44, 56)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 250
		billboard.Adornee = head
		local label = Instance.new("TextLabel")
		label.Name = "Symbol"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = UI.GOLD
		label.TextStrokeTransparency = 0.2
		label.Parent = billboard
		billboard.Parent = player:WaitForChild("PlayerGui")
		markers[giver] = billboard
		gui = billboard
	end
	gui.Enabled = symbol ~= nil
	(gui:FindFirstChild("Symbol") :: TextLabel).Text = symbol or ""
	return true
end

local function row(title: string, detail: string)
	local frame = UI.make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		Parent = rows,
	})
	local heading = UI.label(title, 16, UI.GOLD, true)
	heading.Parent = frame
	local line = UI.label(detail, 14, UI.INK)
	line.Position = UDim2.fromOffset(0, 22)
	line.Parent = frame
end

function QuestTracker.update(quests: { { [string]: any } })
	lastQuests = quests
	for _, child in rows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local shown = 0
	local giverSymbol: { [string]: string } = {}
	for _, quest in quests do
		if quest.status == "active" then
			row(quest.title, `{quest.summary}: {quest.progress} / {quest.count}`)
			shown += 1
		elseif quest.status == "ready" then
			row(quest.title, `Return to {quest.giverName}`)
			shown += 1
			if giverSymbol[quest.giver] ~= "!" then
				giverSymbol[quest.giver] = "?"
			end
		elseif quest.status == "available" then
			giverSymbol[quest.giver] = "!"
		end
	end
	panel.Size = UDim2.fromOffset(300, 34 + shown * 48)
	panel.Visible = shown > 0
	local missing = false
	for giver in GIVER_PATHS do
		if not setMarker(giver, giverSymbol[giver]) then
			missing = true
		end
	end
	if missing then
		-- A giver hasn't arrived yet; try again shortly.
		task.delay(1, function()
			if lastQuests == quests then
				QuestTracker.update(quests)
			end
		end)
	end
end

function QuestTracker.init(parent: ScreenGui)
	panel = UI.panel({
		Name = "QuestTracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 60),
		Size = UDim2.fromOffset(300, 80),
		Visible = false,
		Parent = parent,
	})
	UI.padding(10).Parent = panel
	local heading = UI.label("Quests", 13, UI.MUTED, true)
	heading.Parent = panel
	rows = UI.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 1, -20),
		Parent = panel,
	}, {
		UI.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

return QuestTracker
