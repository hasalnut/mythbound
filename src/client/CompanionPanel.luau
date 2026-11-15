-- The companion panel (P, controller D-pad left, a Pets button on phones): every companion you
-- own, which ones are out, and buttons to bring one out, send it home or release it.
-- The list comes from the server (Companions event); the buttons only send requests
-- (CompanionSetActive, CompanionRelease). Works with mouse, controller and touch.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent:WaitForChild("UI"))

local CompanionPanel = {}

export type Row = { uid: number, id: string, name: string, active: boolean, allowed: boolean, knockedOut: number }

local setActiveEvent = Net.event("CompanionSetActive")
local releaseEvent = Net.event("CompanionRelease")

local ROW_HEIGHT = 46
local RELEASE_RED = Color3.fromRGB(150, 50, 45)

local gui: ScreenGui
local panel: Frame
local header: TextLabel
local list: Frame
local empty: TextLabel
local roster: { Row } = {}
local limit = 1
local stableSize = 6
local receivedAt = 0 -- when the list arrived, to count knock-out timers down
local confirmUid: number? = nil -- Release was pressed once for this one; the next press confirms
local statusLabels: { [number]: TextLabel } = {}
local canOpen: () -> boolean = function()
	return true
end

-- Called when the panel opens, so other panels can close.
CompanionPanel.onOpen = nil :: (() -> ())?

function CompanionPanel.isOpen(): boolean
	return gui ~= nil and panel.Visible
end

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function statusText(row: Row): string
	local left = math.ceil(row.knockedOut - (os.clock() - receivedAt))
	if row.knockedOut > 0 and left > 0 then
		return if row.active then `Knocked out · {left} s` else `Recovering · {left} s`
	elseif row.active then
		return "Out with you"
	elseif not row.allowed then
		return "Needs a Beast Tamer"
	end
	return "At home"
end

local function addRow(row: Row, order: number): GuiObject
	local creature = CreatureData.creatures[row.id]
	local frame = UI.make("Frame", {
		Name = `Companion{row.uid}`,
		BackgroundColor3 = Color3.fromRGB(36, 30, 48),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Parent = list,
	}, { UI.corner(8) })
	UI.make("Frame", {
		BackgroundColor3 = if creature then creature.color else UI.MUTED,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		Parent = frame,
	}, { UI.corner(12) })
	local name = UI.label(row.name, 15, UI.INK, true)
	name.Position = UDim2.fromOffset(42, 4)
	name.Size = UDim2.new(1, -250, 0, 20)
	name.Parent = frame
	local status = UI.label(statusText(row), 12, if row.active then UI.GOLD else UI.MUTED)
	status.Position = UDim2.fromOffset(42, 23)
	status.Size = UDim2.new(1, -250, 0, 18)
	status.Parent = frame
	statusLabels[row.uid] = status

	local toggle = UI.button(if row.active then "Send home" else "Bring out", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -96, 0.5, 0),
		Size = UDim2.fromOffset(104, 32),
		TextSize = 14,
		-- Green when it can come out; plain for Send home, or when this class can't bring it out.
		BackgroundColor3 = if row.active or not row.allowed then Color3.fromRGB(44, 36, 58) else Color3.fromRGB(70, 110, 60),
		Parent = frame,
	})
	toggle.Activated:Connect(function()
		confirmUid = nil
		setActiveEvent:FireServer(row.uid, not row.active) -- the server explains if it can't
	end)
	local confirming = confirmUid == row.uid
	local release = UI.button(if confirming then "Sure?" else "Release", {
		Name = "Release",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(80, 32),
		TextSize = 14,
		BackgroundColor3 = if confirming then RELEASE_RED else Color3.fromRGB(44, 36, 58),
		Parent = frame,
	})
	release.Activated:Connect(function()
		if confirmUid == row.uid then
			confirmUid = nil
			releaseEvent:FireServer(row.uid)
		else
			confirmUid = row.uid -- ask once more: releasing can't be undone
			release.Text = "Sure?"
			release.BackgroundColor3 = RELEASE_RED
		end
	end)
	return toggle
end

function CompanionPanel.refresh()
	if not gui then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(statusLabels)
	local outCount = 0
	local first: GuiObject? = nil
	for order, row in roster do
		if row.active then
			outCount += 1
		end
		local button = addRow(row, order)
		first = first or button
	end
	header.Text = `Companions · {outCount} / {limit} out · {#roster} / {stableSize} owned`
	empty.Visible = #roster == 0
	-- Keep controller selection inside the panel after rebuilding it.
	if panel.Visible and usingGamepad() then
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(gui) then
			GuiService.SelectedObject = first
		end
	end
end

-- The server's list: every companion the player owns, how many can be out, and how many can be owned.
function CompanionPanel.setRoster(rows: { Row }, newLimit: number, newStableSize: number)
	roster = rows
	limit = newLimit
	stableSize = newStableSize
	receivedAt = os.clock()
	if confirmUid then
		local still = false
		for _, row in rows do
			if row.uid == confirmUid then
				still = true
			end
		end
		if not still then
			confirmUid = nil
		end
	end
	CompanionPanel.refresh()
end

function CompanionPanel.close()
	if not gui then
		return
	end
	panel.Visible = false
	confirmUid = nil
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

function CompanionPanel.toggle()
	if panel.Visible then
		CompanionPanel.close()
	elseif canOpen() then
		if CompanionPanel.onOpen then
			CompanionPanel.onOpen()
		end
		panel.Visible = true
		CompanionPanel.refresh()
		-- Knock-out timers count down while the panel is open.
		task.spawn(function()
			while panel.Visible do
				task.wait(1)
				for _, row in roster do
					local label = statusLabels[row.uid]
					if label and label.Parent then
						label.Text = statusText(row)
					end
				end
			end
		end)
	end
end

-- `allowed` says whether the panel may open now (not during dialogue or class select).
function CompanionPanel.init(parent: Instance, allowed: () -> boolean)
	canOpen = allowed
	gui = UI.make("ScreenGui", {
		Name = "Companions",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	panel = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 380),
		Visible = false,
		Parent = gui,
	})
	UI.padding(14).Parent = panel
	header = UI.label("Companions", 18, UI.GOLD, true)
	header.Size = UDim2.new(1, -90, 0, 24)
	header.Parent = panel
	local closeButton = UI.button("Close", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(80, 28),
		TextSize = 14,
		Parent = panel,
	})
	closeButton.Activated:Connect(CompanionPanel.close)
	list = UI.make("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Parent = panel,
	}, {
		UI.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	empty = UI.label("No companions yet. Carry Meat to a fox in the south meadow and feed it (F) to earn its trust. Beast Tamers can also weaken a wolf or boar and use Tame Beast.", 14, UI.MUTED)
	empty.TextWrapped = true
	empty.TextYAlignment = Enum.TextYAlignment.Top
	empty.Position = UDim2.fromOffset(0, 40)
	empty.Size = UDim2.new(1, 0, 0, 80)
	empty.Parent = panel

	ContextActionService:BindAction("MythboundCompanions", function(_, state)
		if state == Enum.UserInputState.Begin then
			CompanionPanel.toggle()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.P, Enum.KeyCode.DPadLeft)
	pcall(function()
		ContextActionService:SetTitle("MythboundCompanions", "Pets")
		ContextActionService:SetPosition("MythboundCompanions", UDim2.new(1, -300, 1, -230))
	end)

	CompanionPanel.refresh()
	gui.Parent = parent
end

return CompanionPanel
