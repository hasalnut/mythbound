-- Visual effects drawn on each player's own screen: damage numbers, sword swings,
-- bolts and arrows, and hit sparks. The server decides what happens; these only show it.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Effects = {}

local folder: Folder? = nil
local function getFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "LocalEffects"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function effectPart(props: { [string]: any }): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = getFolder()
	return part
end

local KIND_COLORS = {
	normal = Color3.fromRGB(255, 255, 255),
	crit = Color3.fromRGB(255, 210, 70),
	hurt = Color3.fromRGB(255, 90, 80),
	heal = Color3.fromRGB(120, 240, 140),
}

function Effects.damageNumber(position: Vector3, amount: number, kind: string)
	local anchor = Instance.new("Attachment")
	anchor.Parent = workspace.Terrain
	anchor.WorldPosition = position + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(100, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if kind == "crit" then 30 else 22
	label.TextColor3 = KIND_COLORS[kind] or KIND_COLORS.normal
	label.TextStrokeTransparency = 0.3
	label.Text = tostring(amount) .. (if kind == "crit" then "!" else "")
	label.Parent = gui
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.9)
end

function Effects.spark(position: Vector3, color: Color3)
	for _ = 1, 6 do
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		local part = effectPart({ Size = Vector3.new(0.4, 0.4, 0.4), CFrame = CFrame.new(position), Color = color })
		TweenService:Create(part, TweenInfo.new(0.3), {
			CFrame = CFrame.new(position + direction * 3),
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		}):Play()
		Debris:AddItem(part, 0.35)
	end
end

-- Loot lying on the ground: a small bobbing gem in the item's colour with its name. Only the
-- owner is sent drops, so in co-op each player sees just their own.
local drops: { [number]: BasePart } = {}

function Effects.showDrop(id: number, color: Color3, name: string, count: number, position: Vector3)
	local gem = effectPart({
		Name = "Drop",
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = color,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Brightness = 1.5
	light.Parent = gem
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(120, 24)
	tag.StudsOffset = Vector3.new(0, 1.6, 0)
	tag.MaxDistance = 60
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = if count > 1 then `{name} ×{count}` else name
	label.Parent = tag
	tag.Parent = gem
	drops[id] = gem
	local start = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		if not gem.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - start
		gem.CFrame = CFrame.new(position + Vector3.new(0, math.sin(t * 3) * 0.3, 0)) * CFrame.Angles(math.rad(45), t * 1.5, math.rad(45))
	end)
end

function Effects.removeDrop(id: number)
	local gem = drops[id]
	if gem then
		drops[id] = nil
		Effects.spark(gem.Position, gem.Color)
		gem:Destroy()
	end
end

-- A flat ring of light expanding to `radius` (novas, explosions, heals, taunts).
function Effects.burst(position: Vector3, radius: number, color: Color3)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		CFrame = CFrame.new(position) * upright,
		Color = color,
		Transparency = 0.2,
	})
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.4)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(60, radius * 1.5)
	light.Brightness = 3
	light.Parent = ring
end

-- Makes a character see-through while its Vanished attribute is set (Ninja Vanish).
-- Your own character stays a little more visible so you can see where you are.
function Effects.watchCharacter(character: Model, isLocal: boolean)
	local function apply()
		local amount = if character:GetAttribute("Vanished") then (if isLocal then 0.6 else 0.85) else 0
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = amount
			end
		end
	end
	character:GetAttributeChangedSignal("Vanished"):Connect(apply)
end

-- Golden rings rising around a character who just levelled up.
function Effects.levelUp(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local base = root.Position - Vector3.new(0, 2.5, 0)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	for i = 0, 2 do
		task.delay(i * 0.15, function()
			local ring = effectPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.25, 4, 4),
				CFrame = CFrame.new(base) * upright,
				Color = Color3.fromRGB(255, 214, 110),
				Transparency = 0.25,
			})
			TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
				Size = Vector3.new(0.25, 12, 12),
				CFrame = CFrame.new(base + Vector3.new(0, 7, 0)) * upright,
				Transparency = 1,
			}):Play()
			Debris:AddItem(ring, 0.95)
		end)
	end
	Effects.spark(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 230, 150))
end

-- A flat crescent of light in front of a melee attacker.
function Effects.swing(position: Vector3, direction: Vector3, color: Color3, range: number)
	local look = CFrame.lookAt(position, position + direction)
	local part = effectPart({
		Size = Vector3.new(range * 1.3, 0.2, range * 0.55),
		CFrame = look * CFrame.Angles(0, 0, math.rad(math.random(-15, 15))),
		Color = color,
		Transparency = 0.35,
	})
	TweenService:Create(part, TweenInfo.new(0.18), { Transparency = 1, Size = part.Size * Vector3.new(1.15, 1, 1.25) }):Play()
	Debris:AddItem(part, 0.2)
end

-- Draws a bolt or arrow flying from `start`. It stops at the first solid thing it meets,
-- the same way the server's projectile does.
function Effects.bolt(start: Vector3, velocity: Vector3, color: Color3, lifetime: number, arrow: boolean, shooter: Instance?, size: number?)
	local part = if arrow
		then effectPart({ Size = Vector3.new(0.25, 0.25, 3), Color = color, Material = Enum.Material.Wood })
		else effectPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * (size or 1.3), Color = color })
	if not arrow then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 2
		light.Parent = part
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { getFolder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(exclude, other.Character)
		end
	end
	if shooter then
		table.insert(exclude, shooter)
	end
	params.FilterDescendantsInstances = exclude

	local position = start
	local age = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		age += dt
		local step = velocity * dt
		local result = workspace:Raycast(position, step, params)
		if result or age >= lifetime then
			connection:Disconnect()
			if result then
				Effects.spark(result.Position, color)
			end
			part:Destroy()
			return
		end
		position += step
		part.CFrame = CFrame.lookAt(position, position + velocity)
	end)
end

return Effects
