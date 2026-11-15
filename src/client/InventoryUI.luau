-- The bag (Tab, controller D-pad up) and the workbench panel (opened by the workbench prompt).
-- Counts come from the server (Inventory event); buttons only send requests (UseItem, Craft).
-- H (controller D-pad down) drinks a healing potion. Works with mouse, controller and touch.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemData = require(Shared:WaitForChild("ItemData"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent:WaitForChild("UI"))

local InventoryUI = {}

local player = Players.LocalPlayer
local useEvent = Net.event("UseItem")
local craftEvent = Net.event("Craft")

local counts: { [string]: number } = {}
local gui: ScreenGui
local bagPanel: Frame
local grid: Frame
local detailName: TextLabel
local detailText: TextLabel
local useButton: TextButton
local craftPanel: Frame
local craftList: Frame
local selectedItem: string? = nil
local canOpen: () -> boolean = function()
	return true
end

-- Called when the bag or the workbench opens, so other panels can close.
InventoryUI.onOpen = nil :: (() -> ())?

function InventoryUI.isOpen(): boolean
	return gui ~= nil and (bagPanel.Visible or craftPanel.Visible)
end

function InventoryUI.count(itemId: string): number
	return counts[itemId] or 0
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function refreshDetail()
	local item = selectedItem and ItemData.items[selectedItem]
	if item and (counts[item.id] or 0) > 0 then
		detailName.Text = `{item.name} ×{counts[item.id]}`
		detailText.Text = item.description
		useButton.Visible = item.usable == true
	else
		detailName.Text = ""
		detailText.Text = if next(counts) then "Choose an item." else "Your bag is empty. Defeat creatures, or gather wheat, honey and apples in the village."
		useButton.Visible = false
	end
end

local function slot(item: ItemData.Item, count: number, order: number)
	local button = UI.button("", {
		Name = item.id,
		Size = UDim2.fromOffset(84, 84),
		LayoutOrder = order,
		BackgroundColor3 = if selectedItem == item.id then Color3.fromRGB(110, 85, 45) else Color3.fromRGB(44, 36, 58),
		Parent = grid,
	})
	UI.make("Frame", {
		BackgroundColor3 = item.color,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(34, 34),
		Parent = button,
	}, { UI.corner(17) })
	local name = UI.label(item.name, 12, UI.INK, true)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.Position = UDim2.fromOffset(0, 46)
	name.TextWrapped = true
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Parent = button
	local amount = UI.label(`×{count}`, 13, UI.GOLD, true)
	amount.TextXAlignment = Enum.TextXAlignment.Center
	amount.Position = UDim2.fromOffset(0, 62)
	amount.Size = UDim2.new(1, 0, 0, 18)
	amount.Parent = button
	button.Activated:Connect(function()
		selectedItem = item.id
		InventoryUI.refresh()
	end)
	return button
end

local function recipeRow(recipe: ItemData.Recipe, order: number)
	local item = ItemData.items[recipe.id]
	local parts = {}
	local ready = true
	for itemId, need in recipe.ingredients do
		local have = counts[itemId] or 0
		if have < need then
			ready = false
		end
		table.insert(parts, `{need} {ItemData.items[itemId].name} ({have})`)
	end
	table.sort(parts)
	local row = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order, Parent = craftList })
	local title = UI.label(item.name, 16, UI.GOLD, true)
	title.Size = UDim2.new(1, -110, 0, 22)
	title.Parent = row
	local needs = UI.label(table.concat(parts, " + "), 13, if ready then UI.INK else UI.MUTED)
	needs.Position = UDim2.fromOffset(0, 24)
	needs.Size = UDim2.new(1, -110, 0, 20)
	needs.Parent = row
	local craft = UI.button("Craft", {
		Name = "Craft_" .. recipe.id,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(96, 36),
		TextSize = 15,
		BackgroundColor3 = if ready then Color3.fromRGB(70, 110, 60) else Color3.fromRGB(50, 44, 58),
		AutoButtonColor = ready,
		Parent = row,
	})
	craft.Activated:Connect(function()
		if ready then
			craftEvent:FireServer(recipe.id)
		end
	end)
	return craft
end

function InventoryUI.refresh()
	if not gui then
		return
	end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local first: GuiObject? = nil
	for order, itemId in ItemData.order do
		local count = counts[itemId] or 0
		if count > 0 then
			local button = slot(ItemData.items[itemId], count, order)
			first = first or button
		end
	end
	refreshDetail()
	for _, child in craftList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local firstCraft: GuiObject? = nil
	for order, recipe in ItemData.recipes do
		local button = recipeRow(recipe, order)
		firstCraft = firstCraft or button
	end
	-- Keep controller selection inside an open panel after rebuilding it.
	if usingGamepad() then
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = if craftPanel.Visible then firstCraft elseif bagPanel.Visible then first else nil
		end
	end
end

function InventoryUI.setCounts(newCounts: { [string]: number })
	counts = newCounts
	InventoryUI.refresh()
end

local function close()
	bagPanel.Visible = false
	craftPanel.Visible = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

function InventoryUI.toggleBag()
	if bagPanel.Visible then
		close()
	elseif canOpen() then
		if InventoryUI.onOpen then
			InventoryUI.onOpen()
		end
		bagPanel.Visible = true
		InventoryUI.refresh()
	end
end

-- The workbench prompt calls this (through OpenCrafting): shows recipes beside the bag.
function InventoryUI.openCrafting()
	if not canOpen() then
		return
	end
	if InventoryUI.onOpen then
		InventoryUI.onOpen()
	end
	bagPanel.Visible = true
	craftPanel.Visible = true
	InventoryUI.refresh()
end

-- `allowed` says whether the bag may open now (not during dialogue or class select).
function InventoryUI.init(parent: Instance, allowed: () -> boolean)
	canOpen = allowed
	gui = UI.make("ScreenGui", {
		Name = "Inventory",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	bagPanel = UI.panel({
		Name = "Bag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 10, 0.5, 0),
		Size = UDim2.fromOffset(420, 360),
		Visible = false,
		Parent = gui,
	})
	UI.padding(14).Parent = bagPanel
	local title = UI.label("Bag", 20, UI.GOLD, true)
	title.Parent = bagPanel
	local closeButton = UI.button("Close", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(80, 28),
		TextSize = 14,
		Parent = bagPanel,
	})
	closeButton.Activated:Connect(close)
	grid = UI.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 180),
		Parent = bagPanel,
	}, {
		UI.make("UIGridLayout", { CellSize = UDim2.fromOffset(84, 84), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	detailName = UI.label("", 17, UI.INK, true)
	detailName.Position = UDim2.fromOffset(0, 226)
	detailName.Parent = bagPanel
	detailText = UI.label("", 14, UI.MUTED)
	detailText.TextWrapped = true
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	detailText.Position = UDim2.fromOffset(0, 252)
	detailText.Size = UDim2.new(1, -110, 0, 60)
	detailText.Parent = bagPanel
	useButton = UI.button("Use", {
		Name = "Use",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(96, 36),
		TextSize = 15,
		Visible = false,
		Parent = bagPanel,
	})
	useButton.Activated:Connect(function()
		if selectedItem then
			useEvent:FireServer(selectedItem)
		end
	end)

	craftPanel = UI.panel({
		Name = "Workbench",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -10, 0.5, 0),
		Size = UDim2.fromOffset(380, 360),
		Visible = false,
		Parent = gui,
	})
	UI.padding(14).Parent = craftPanel
	local craftTitle = UI.label("Workbench", 20, UI.GOLD, true)
	craftTitle.Parent = craftPanel
	craftList = UI.make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Parent = craftPanel,
	}, {
		UI.make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	ContextActionService:BindAction("MythboundBag", function(_, state)
		if state == Enum.UserInputState.Begin then
			InventoryUI.toggleBag()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.DPadUp)
	-- Roblox's player list claims Tab before ContextActionService sees it, so listen directly
	-- (but not while the player is typing in a text box).
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab and not UserInputService:GetFocusedTextBox() then
			InventoryUI.toggleBag()
		end
	end)
	pcall(function()
		ContextActionService:SetTitle("MythboundBag", "Bag")
		ContextActionService:SetPosition("MythboundBag", UDim2.new(1, -300, 1, -90))
	end)
	ContextActionService:BindAction("MythboundPotion", function(_, state)
		if state == Enum.UserInputState.Begin and canOpen() then
			-- Always ask: the server explains if there are none left.
			useEvent:FireServer("healing_potion")
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.H, Enum.KeyCode.DPadDown)
	pcall(function()
		ContextActionService:SetTitle("MythboundPotion", "Potion")
		ContextActionService:SetPosition("MythboundPotion", UDim2.new(1, -300, 1, -160))
	end)

	refreshDetail()
	gui.Parent = parent
end

-- Closes everything (when the class screen or a dialogue opens, or the character dies).
function InventoryUI.close()
	if gui then
		close()
	end
end

return InventoryUI
