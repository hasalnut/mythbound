-- Small helpers for building scenery out of anchored parts.

local Build = {}

Build.WALL = Color3.fromRGB(222, 205, 168)
Build.WOOD = Color3.fromRGB(115, 78, 45)
Build.DARK_WOOD = Color3.fromRGB(85, 58, 35)
Build.STONE = Color3.fromRGB(140, 136, 128)
Build.STRAW = Color3.fromRGB(226, 196, 110)
Build.LEAF = Color3.fromRGB(70, 140, 60)
Build.PINE = Color3.fromRGB(40, 95, 55)
Build.BARK = Color3.fromRGB(100, 68, 42)

-- Creates an anchored part. `props` can hold any Part property, plus Class = "Part" | "SpawnLocation" | ...
function Build.part(props: { [string]: any }): BasePart
	local className = props.Class or "Part"
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	for key, value in props do
		if key ~= "Class" and key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	if parent then
		part.Parent = parent
	end
	return part
end

-- A part placed relative to `base`.
function Build.at(parent: Instance, base: CFrame, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Size = size,
		CFrame = base * offset,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return Build.part(props)
end

-- A vertical cylinder (Roblox cylinders lie along X, so rotate them upright).
function Build.cylinder(parent: Instance, base: CFrame, height: number, diameter: number, offset: Vector3, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = base * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return Build.part(props)
end

function Build.ball(parent: Instance, position: Vector3, diameter: number, color: Color3, material: Enum.Material?, extra: { [string]: any }?): BasePart
	local props: { [string]: any } = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(position),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return Build.part(props)
end

-- Welds `part` to `to` where it currently is and makes it ride along without physics of its own.
function Build.weld(part: BasePart, to: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

function Build.model(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Build.folder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- A floating name tag, for NPCs and signs.
function Build.nameTag(adornee: BasePart, text: string, color: Color3?, height: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, height or 2.5, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = color or Color3.fromRGB(255, 225, 140)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = adornee
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

-- Height of the terrain at (x, z). Ignores water so things never sit on the pond.
function Build.groundY(x: number, z: number): number
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	groundParams.IgnoreWater = true
	local result = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), groundParams)
	return if result then result.Position.Y else 0
end

return Build
