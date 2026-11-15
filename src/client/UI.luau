-- Small helpers and the shared look for all interface pieces.

local UI = {}

UI.INK = Color3.fromRGB(236, 230, 218)
UI.MUTED = Color3.fromRGB(170, 162, 150)
UI.GOLD = Color3.fromRGB(240, 196, 90)
UI.PANEL = Color3.fromRGB(24, 20, 34)
UI.PANEL_EDGE = Color3.fromRGB(120, 96, 60)
UI.RED = Color3.fromRGB(205, 55, 50)
UI.FONT = Enum.Font.Gotham
UI.FONT_BOLD = Enum.Font.GothamBold

-- Creates an instance, sets properties, adds children. Parent is set last.
function UI.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UI.corner(radius: number?): UICorner
	return UI.make("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function UI.stroke(color: Color3?, thickness: number?): UIStroke
	return UI.make("UIStroke", {
		Color = color or UI.PANEL_EDGE,
		Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return UI.make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p })
end

function UI.panel(props: { [string]: any }): Frame
	local frame = UI.make("Frame", {
		BackgroundColor3 = UI.PANEL,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, { UI.corner(10), UI.stroke() })
	for key, value in props do
		if key ~= "Parent" then
			frame[key] = value
		end
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

function UI.label(text: string, size: number?, color: Color3?, bold: boolean?): TextLabel
	return UI.make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size or 18,
		TextColor3 = color or UI.INK,
		Font = if bold then UI.FONT_BOLD else UI.FONT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, (size or 18) + 6),
	})
end

-- A horizontal bar. Returns the background frame and the fill frame.
function UI.bar(color: Color3, height: number): (Frame, Frame)
	local back = UI.make("Frame", {
		BackgroundColor3 = Color3.fromRGB(40, 34, 48),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	}, { UI.corner(4) })
	local fill = UI.make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = back,
	}, { UI.corner(4) })
	return back, fill
end

function UI.button(text: string, props: { [string]: any }?): TextButton
	local button = UI.make("TextButton", {
		BackgroundColor3 = Color3.fromRGB(44, 36, 58),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = text,
		TextColor3 = UI.INK,
		Font = UI.FONT_BOLD,
		TextSize = 18,
	}, { UI.corner(8), UI.stroke() })
	if props then
		for key, value in props do
			if key ~= "Parent" then
				button[key] = value
			end
		end
		if props.Parent then
			button.Parent = props.Parent
		end
	end
	return button
end

return UI
