-- The class choice screen shown on joining (and from the "Change class" button).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local Net = require(Shared:WaitForChild("Net"))
local UI = require(script.Parent:WaitForChild("UI"))

local ClassSelect = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local selected = "ninja"
local orbit: RBXScriptConnection? = nil
local gamepadWatch: RBXScriptConnection? = nil

-- Called with true when the screen opens and false when it closes (Main hides the HUD).
ClassSelect.onToggle = nil :: ((open: boolean) -> ())?

local function isGamepad(inputType: Enum.UserInputType): boolean
	return inputType.Name:sub(1, 7) == "Gamepad"
end

local function statsText(info: ClassData.ClassInfo): string
	local style = if info.style == "Melee" then "Melee" else "Ranged"
	return string.format(
		"Health %d   ·   Damage %d   ·   Damage taken −%d%%   ·   Speed %d   ·   %s   ·   Companions %d",
		info.maxHealth,
		info.attack,
		math.floor(info.damageReduction * 100 + 0.5),
		info.walkSpeed,
		style,
		info.maxCompanions
	)
end

-- Slowly circles the camera over the village behind the menu.
local function startOrbit()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local angle = 0
	orbit = RunService.RenderStepped:Connect(function(dt)
		angle += dt * 0.05
		local position = Vector3.new(math.cos(angle) * 150, 70, math.sin(angle) * 150)
		camera.CFrame = CFrame.lookAt(position, Vector3.new(0, 5, 0))
	end)
end

local function stopOrbit()
	if orbit then
		orbit:Disconnect()
		orbit = nil
	end
end

function ClassSelect.isOpen(): boolean
	return gui ~= nil
end

function ClassSelect.close()
	stopOrbit()
	if gamepadWatch then
		gamepadWatch:Disconnect()
		gamepadWatch = nil
	end
	if gui then
		local selectedObject = GuiService.SelectedObject
		if selectedObject and selectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		gui:Destroy()
		gui = nil
		if ClassSelect.onToggle then
			ClassSelect.onToggle(false)
		end
	end
end

-- `onChosen` runs after the class is sent to the server.
function ClassSelect.open(onChosen: (() -> ())?)
	if gui then
		return
	end
	-- Returning players start on the class they last played (saved by the server).
	selected = (player:GetAttribute("Class") :: string?) or (player:GetAttribute("SavedClass") :: string?) or "ninja"
	if not ClassData.classes[selected] then
		selected = "ninja"
	end
	local function beginText(): string
		if player.Character then
			return "Switch class"
		end
		return if player:GetAttribute("SavedClass") then "Continue journey" else "Begin journey"
	end
	if not player.Character then
		startOrbit()
	end

	local screen = UI.make("ScreenGui", {
		Name = "ClassSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	gui = screen

	local shade = UI.make("Frame", {
		BackgroundColor3 = Color3.fromRGB(12, 10, 22),
		BackgroundTransparency = if player.Character then 0.25 else 0.35,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})

	local column = UI.make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 470),
		Parent = shade,
	}, {
		UI.make("UISizeConstraint", { MaxSize = Vector2.new(980, 470) }),
		UI.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local title = UI.label("MYTHBOUND", 64, UI.GOLD, true)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Size = UDim2.new(1, 0, 0, 72)
	title.LayoutOrder = 1
	title.Parent = column

	local subtitle = UI.label("Choose your class · Choose your path · Tame the myths", 20, UI.MUTED)
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.LayoutOrder = 2
	subtitle.Parent = column

	local row = UI.make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 74),
		LayoutOrder = 3,
		Parent = column,
	}, {
		UI.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})

	local details = UI.panel({ Size = UDim2.new(1, 0, 0, 96), LayoutOrder = 4, Parent = column })
	UI.padding(14).Parent = details
	local description = UI.label("", 18)
	description.TextWrapped = true
	description.Size = UDim2.new(1, 0, 0, 46)
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Parent = details
	local stats = UI.label("", 15, UI.MUTED)
	stats.Position = UDim2.fromOffset(0, 50)
	stats.Parent = details

	local buttons: { [string]: TextButton } = {}
	local function refresh()
		local info = ClassData.classes[selected]
		description.Text = info.description
		stats.Text = statsText(info)
		for id, button in buttons do
			local chosen = id == selected
			button.BackgroundColor3 = if chosen then Color3.fromRGB(150, 110, 45) else Color3.fromRGB(44, 36, 58)
		end
	end

	for index, id in ClassData.order do
		local info = ClassData.classes[id]
		local button = UI.button(`{info.name}\n{info.tagline}`, {
			Size = UDim2.new(0.19, -8, 1, 0),
			TextSize = 17,
			LayoutOrder = index,
			Parent = row,
		})
		button.Activated:Connect(function()
			selected = id
			refresh()
		end)
		buttons[id] = button
	end

	local begin = UI.button(beginText(), {
		Size = UDim2.fromOffset(260, 52),
		TextSize = 22,
		BackgroundColor3 = Color3.fromRGB(60, 44, 80),
		LayoutOrder = 5,
		Parent = column,
	})
	local hint = UI.label("Click a class, then begin. Controller: D-pad to choose, A to confirm.", 14, UI.MUTED)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.LayoutOrder = 6
	hint.Parent = column

	if player.Character then
		local cancel = UI.button("Back to the game", {
			Size = UDim2.fromOffset(200, 40),
			TextSize = 16,
			LayoutOrder = 7,
			Parent = column,
		})
		cancel.Activated:Connect(function()
			ClassSelect.close()
		end)
	end

	-- Wait until the server has built the world before letting anyone in.
	if not workspace:GetAttribute("WorldReady") then
		begin.Text = "Building Hearthmoor…"
		begin.Active = false
		task.spawn(function()
			while not workspace:GetAttribute("WorldReady") do
				workspace:GetAttributeChangedSignal("WorldReady"):Wait()
			end
			begin.Text = beginText()
			begin.Active = true
		end)
	end

	begin.Activated:Connect(function()
		if not workspace:GetAttribute("WorldReady") then
			return
		end
		Net.event("ChooseClass"):FireServer(selected)
		ClassSelect.close()
		if onChosen then
			onChosen()
		end
	end)

	refresh()
	-- The save may finish loading while this screen is already open.
	local savedWatch = player:GetAttributeChangedSignal("SavedClass"):Connect(function()
		local saved = player:GetAttribute("SavedClass") :: string?
		if not player.Character and saved and ClassData.classes[saved] then
			selected = saved
			refresh()
			if begin.Active then
				begin.Text = beginText()
			end
		end
	end)
	screen.Destroying:Connect(function()
		savedWatch:Disconnect()
	end)
	screen.Parent = player:WaitForChild("PlayerGui")
	if ClassSelect.onToggle then
		ClassSelect.onToggle(true)
	end

	-- Controllers can't point and click: put the selection on the chosen class so the D-pad
	-- moves between buttons and A presses them. Also when a controller is picked up later.
	local function focusForGamepad()
		if gui and not GuiService.SelectedObject then
			GuiService.SelectedObject = buttons[selected]
		end
	end
	if UserInputService.GamepadEnabled and isGamepad(UserInputService:GetLastInputType()) then
		focusForGamepad()
	end
	gamepadWatch = UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if isGamepad(inputType) then
			focusForGamepad()
		end
	end)
end

return ClassSelect
