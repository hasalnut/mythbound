-- Builds Hearthmoor when the server starts: terrain, the village, scenery, people,
-- training dummies and creature spawners. Positions match the Godot Phase 1 layout
-- (metres x 3.5 = studs). North is -Z; the village centre is (0, 0).
--
-- Building by code keeps the whole map in Git. Houses, trees, rocks, the well and the campfire
-- go through Assets.place: a model with the same name in ServerStorage.Assets replaces the grey
-- version without code changes (asset names: ElderHall, HouseSmall, HouseWide, AppleTree, Tree,
-- Pine, Rock, Well, Campfire).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local ItemData = require(Shared:WaitForChild("ItemData"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local Build = require(script.Parent:WaitForChild("Build"))
local Creature = require(script.Parent:WaitForChild("Creature"))
local Dummy = require(script.Parent:WaitForChild("Dummy"))
local Interactables = require(script.Parent:WaitForChild("Interactables"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Net = require(Shared:WaitForChild("Net"))
local Quests = require(script.Parent:WaitForChild("Quests"))

local Hearthmoor = {}

local M = 3.5 -- studs per metre (Godot layout -> Roblox)
local HALF = Config.MAP_HALF
local POND = Vector3.new(34 * M, 0, 70 * M)
local POND_RADIUS = 44
local rng = Random.new(1108)

local function v2(x: number, z: number): Vector3
	return Vector3.new(x * M, 0, z * M)
end

local ELDER = v2(-10, -10)

-- An invisible part to hang a gathering prompt on, so it works whatever model stands there.
local function gatherSpot(parent: Instance, cframe: CFrame, kind: string, spotId: string, distance: number?)
	local anchor = Build.part({
		Name = "GatherSpot",
		Size = Vector3.new(2, 2, 2),
		CFrame = cframe,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
	local spec = ItemData.gather[kind]
	Interactables.prompt(anchor, spec.verb, spec.object, function(player)
		Inventory.gather(player, kind, spotId)
	end, distance)
end

-- The point on the ground under `at` (its y is ignored), turned `yaw` radians about the vertical.
local function ground(at: Vector3, yaw: number?): CFrame
	return CFrame.new(at.X, Build.groundY(at.X, at.Z), at.Z) * CFrame.Angles(0, yaw or 0, 0)
end

-- Distance from (x, z) to the nearest path (north road, plaza, path to the pond).
local function segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * abx + (pz - az) * abz) / (abx * abx + abz * abz), 0, 1)
	local cx, cz = ax + abx * t, az + abz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

local function pathDistance(x: number, z: number): number
	local road = segmentDistance(x, z, 0, 10, 0, -HALF)
	local pond = segmentDistance(x, z, 0, 20, POND.X - 30, POND.Z - 25)
	local plaza = math.max(0, math.sqrt(x * x + (z - 14) ^ 2) - 30)
	return math.min(road, pond, plaza)
end

-- Lighting -------------------------------------------------------------------------

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(85, 85, 95)
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 135, 145)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(199, 212, 228)
	atmosphere.Decay = Color3.fromRGB(110, 120, 135)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	grade.Saturation = 0.12
	grade.Contrast = 0.05
	grade.Parent = Lighting
end

-- Terrain --------------------------------------------------------------------------

local function paintSquare(x: number, z: number, size: number, from: Enum.Material, to: Enum.Material)
	local region = Region3.new(Vector3.new(x - size / 2, -40, z - size / 2), Vector3.new(x + size / 2, 120, z + size / 2))
	workspace.Terrain:ReplaceMaterial(region:ExpandToGrid(4), 4, from, to)
end

local function buildTerrain()
	local terrain = workspace.Terrain
	terrain:Clear()
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(96, 150, 62))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(128, 100, 70))
	terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(205, 186, 140))
	pcall(function()
		(terrain :: any).Decoration = true -- animated grass where supported
	end)

	-- Flat ground, top surface at y = 0.
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(HALF * 2 + 120, 12, HALF * 2 + 120), Enum.Material.Grass)

	-- Rolling bumps outside the village.
	for _ = 1, 45 do
		local x = rng:NextNumber(-HALF, HALF)
		local z = rng:NextNumber(-HALF, HALF)
		local r = rng:NextNumber(28, 60)
		local nearVillage = math.sqrt(x * x + z * z) < Config.VILLAGE_RADIUS + r + 20
		local nearPond = (Vector3.new(x, 0, z) - POND).Magnitude < POND_RADIUS + r + 20
		if not nearVillage and not nearPond and pathDistance(x, z) > r + 6 then
			terrain:FillBall(Vector3.new(x, -r * 0.72, z), r, Enum.Material.Grass)
		end
	end

	-- A ring of hills keeps players inside the map, with a gap where the north road leaves.
	local steps = 40
	for i = 0, steps - 1 do
		local angle = i / steps * math.pi * 2
		local x = math.cos(angle) * (HALF + 40)
		local z = math.sin(angle) * (HALF + 40)
		if not (z < 0 and math.abs(x) < 70) then
			local r = rng:NextNumber(80, 110)
			terrain:FillBall(Vector3.new(x, -r * 0.35, z), r, if i % 3 == 0 then Enum.Material.Rock else Enum.Material.Grass)
		end
	end

	-- Paths and the plaza.
	for z = -HALF, 16, 8 do
		paintSquare(0, z, 16, Enum.Material.Grass, Enum.Material.Ground)
	end
	paintSquare(0, 14, 56, Enum.Material.Grass, Enum.Material.Ground)
	local px, pz = POND.X - 30, POND.Z - 25
	for t = 0, 1, 0.04 do
		paintSquare(px * t, 20 + (pz - 20) * t, 12, Enum.Material.Grass, Enum.Material.Ground)
	end

	-- The pond: a sandy shore, then dig out the hole and fill it with water.
	for dx = -POND_RADIUS - 16, POND_RADIUS + 16, 8 do
		for dz = -POND_RADIUS - 16, POND_RADIUS + 16, 8 do
			if math.sqrt(dx * dx + dz * dz) < POND_RADIUS + 14 then
				paintSquare(POND.X + dx, POND.Z + dz, 8, Enum.Material.Grass, Enum.Material.Sand)
			end
		end
	end
	terrain:FillCylinder(CFrame.new(POND.X, -1, POND.Z), 10, POND_RADIUS, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(POND.X, -7, POND.Z), 2, POND_RADIUS, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(POND.X, -3.5, POND.Z), 5, POND_RADIUS - 1, Enum.Material.Water)

	-- Invisible walls at the very edge, in case someone climbs the hills.
	local walls = Build.folder("MapEdge", workspace)
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local size = if side.X ~= 0 then Vector3.new(4, 400, HALF * 2 + 200) else Vector3.new(HALF * 2 + 200, 400, 4)
		Build.part({
			Size = size,
			CFrame = CFrame.new(side * (HALF + 10) + Vector3.new(0, 150, 0)),
			Transparency = 1,
			CanQuery = false,
			Parent = walls,
		})
	end
end

-- Village pieces -----------------------------------------------------------------------

-- The grey house. `cframe` is the ground point with -Z facing the way the door faces (the asset
-- convention); the parts below are laid out with the door on +Z, so turn round first.
local function house(parent: Instance, name: string, cframe: CFrame, w: number, d: number, h: number, roof: Color3): Model
	local model = Build.model(name, parent)
	local base = cframe * CFrame.Angles(0, math.pi, 0)
	Build.at(model, base, Vector3.new(w + 2, 1.5, d + 2), CFrame.new(0, 0.5, 0), Build.STONE, Enum.Material.Slate)
	Build.at(model, base, Vector3.new(w, h, d), CFrame.new(0, h / 2 + 1, 0), Build.WALL, Enum.Material.SmoothPlastic)
	-- Timber corner posts.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.at(model, base, Vector3.new(1, h, 1), CFrame.new(sx * w / 2, h / 2 + 1, sz * d / 2), Build.DARK_WOOD, Enum.Material.Wood)
		end
	end
	-- Roof: two tilted slabs meeting at a ridge along X.
	local rise = h * 0.6
	local half = d / 2 + 1.5
	local angle = math.atan2(rise, half)
	local slab = math.sqrt(rise * rise + half * half) + 0.6
	local top = h + 1
	for _, side in { -1, 1 } do
		Build.at(model, base, Vector3.new(w + 3, 0.8, slab), CFrame.new(0, top + rise / 2, side * half / 2) * CFrame.Angles(side * angle, 0, 0), roof, Enum.Material.SmoothPlastic)
	end
	-- Gable ends fill the triangle under the roof exactly: a strip the depth of the wall up to
	-- where the roof crosses the wall line, then two wedges whose slopes follow the roof.
	local eave = rise * (1 - (d / 2) / half) -- height of the roof above the wall top, at the wall line
	local peak = rise - eave
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(0.6, eave, d), CFrame.new(sx * w / 2, top + eave / 2, 0), Build.WALL, Enum.Material.SmoothPlastic)
		for _, sz in { -1, 1 } do
			-- A wedge is tallest at its +Z end; point that end at the ridge.
			local turn = CFrame.Angles(0, if sz > 0 then math.pi else 0, 0)
			Build.at(model, base, Vector3.new(0.6, peak, d / 2), CFrame.new(sx * w / 2, top + eave + peak / 2, sz * d / 4) * turn, Build.WALL, Enum.Material.SmoothPlastic, { Class = "WedgePart" })
		end
	end
	Build.at(model, base, Vector3.new(w + 3.2, 0.9, 0.9), CFrame.new(0, top + rise + 0.2, 0), Build.DARK_WOOD, Enum.Material.Wood)
	-- Door and glowing windows on the front (+Z) wall.
	Build.at(model, base, Vector3.new(4, 7, 0.4), CFrame.new(0, 4.5, d / 2 + 0.2), Build.DARK_WOOD, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(3, 3, 0.3), CFrame.new(sx * w * 0.3, h * 0.62 + 1, d / 2 + 0.15), Color3.fromRGB(255, 214, 130), Enum.Material.Neon, { Transparency = 0.25 })
		Build.at(model, base, Vector3.new(3.6, 0.5, 0.6), CFrame.new(sx * w * 0.3, h * 0.62 - 0.8, d / 2 + 0.3), Build.DARK_WOOD, Enum.Material.Wood)
	end
	Build.at(model, base, Vector3.new(2.4, 7, 2.4), CFrame.new(w * 0.28, top + rise * 0.7, -d * 0.18), Color3.fromRGB(150, 85, 70), Enum.Material.Brick)
	return model
end

-- Places a house whose door faces `face` quarter turns round from south (0 = +Z, 1 = +X, 2 = -Z,
-- 3 = -X). Houses of the same size share an asset name, so one model can replace several.
local function placeHouse(parent: Instance, asset: string, name: string, at: Vector3, w: number, d: number, h: number, face: number, roof: Color3)
	-- Asset fronts face -Z, so add a half turn: the front then faces the same way as the door.
	local model = Assets.place(asset, ground(at, face * math.pi / 2 + math.pi), parent, function(base, into)
		return house(into, name, base, w, d, h, roof)
	end)
	model.Name = name
end

local function campfire(base: CFrame, parent: Instance): Model
	local model = Build.model("Campfire", parent)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.ball(model, (base * CFrame.new(math.cos(a) * 3.4, 0.4, math.sin(a) * 3.4)).Position, 1.8, Color3.fromRGB(110, 108, 104), Enum.Material.Slate)
	end
	Build.at(model, base, Vector3.new(5, 0.8, 0.8), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(35), 0), Build.WOOD, Enum.Material.Wood)
	Build.at(model, base, Vector3.new(5, 0.8, 0.8), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, math.rad(-35), 0), Build.WOOD, Enum.Material.Wood)
	local flame = Build.at(model, base, Vector3.new(1, 1, 1), CFrame.new(0, 1.2, 0), Color3.new(1, 0.6, 0.2), nil, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Name = "Flame",
	})
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 140, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 26
	light.Brightness = 2
	light.Shadows = true
	light.Parent = flame
	-- A low invisible block so players walk around the fire, not through it.
	Build.at(model, base, Vector3.new(5.5, 2, 5.5), CFrame.new(0, 1, 0), Color3.new(), nil, { Transparency = 1, CanQuery = false })
	return model
end

local function well(base: CFrame, parent: Instance): Model
	local model = Build.model("Well", parent)
	Build.cylinder(model, base, 3.4, 8, Vector3.new(0, 1.7, 0), Build.STONE, Enum.Material.Cobblestone)
	Build.cylinder(model, base, 0.2, 6.6, Vector3.new(0, 3.45, 0), Color3.fromRGB(50, 95, 160), Enum.Material.Glass, { Transparency = 0.2, CanCollide = false })
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(0.6, 6, 0.6), CFrame.new(sx * 3.4, 6, 0), Build.WOOD, Enum.Material.Wood)
	end
	Build.at(model, base, Vector3.new(7.4, 0.5, 0.5), CFrame.new(0, 7.6, 0), Build.WOOD, Enum.Material.Wood)
	for _, side in { -1, 1 } do
		Build.at(model, base, Vector3.new(8.6, 0.5, 4.6), CFrame.new(0, 9.6, side * 1.9) * CFrame.Angles(side * math.rad(28), 0, 0), Color3.fromRGB(110, 75, 50), Enum.Material.WoodPlanks)
	end
	Build.at(model, base, Vector3.new(1, 1.2, 1), CFrame.new(0, 6.4, 0), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
	return model
end

local function workbench(parent: Instance, at: Vector3)
	local model = Build.model("Workbench", parent)
	local base = CFrame.new(at.X, Build.groundY(at.X, at.Z), at.Z)
	local top = Build.at(model, base, Vector3.new(9, 0.7, 4.2), CFrame.new(0, 3.2, 0), Build.WOOD, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.at(model, base, Vector3.new(0.6, 3, 0.6), CFrame.new(sx * 3.9, 1.5, sz * 1.6), Build.DARK_WOOD, Enum.Material.Wood)
		end
	end
	Build.at(model, base, Vector3.new(1.8, 0.6, 1), CFrame.new(-2, 3.85, 0), Color3.fromRGB(150, 150, 160), Enum.Material.Metal)
	Build.at(model, base, Vector3.new(0.3, 0.3, 2.2), CFrame.new(1.5, 3.7, 0.4), Build.DARK_WOOD, Enum.Material.Wood)
	-- Opens the crafting panel on that player's screen; Inventory checks they're still close when crafting.
	local openCrafting = Net.event("OpenCrafting")
	Inventory.setWorkbench(top.Position)
	Interactables.prompt(top, "Craft", "Workbench", function(player)
		openCrafting:FireClient(player)
	end)
end

local function wheatField(parent: Instance, centre: Vector3)
	local model = Build.model("WheatField", parent)
	local base = CFrame.new(centre.X, Build.groundY(centre.X, centre.Z), centre.Z)
	Build.at(model, base, Vector3.new(52, 0.6, 38), CFrame.new(0, 0.2, 0), Color3.fromRGB(120, 88, 55), Enum.Material.Ground)
	for row = 0, 15 do
		local z = -17 + row * 2.3
		Build.at(model, base, Vector3.new(50, 3.2 + rng:NextNumber(-0.3, 0.3), 1.1), CFrame.new(0, 2, z), Color3.fromRGB(232, 196, 92), Enum.Material.Fabric, { CanCollide = false })
	end
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(0.6, 4, 0.6), CFrame.new(sx * 27, 2, -20), Build.WOOD, Enum.Material.Wood)
	end
	gatherSpot(model, base * CFrame.new(0, 3, 0), "wheat", "wheat_field", 24)
end

local function beehive(parent: Instance, at: Vector3, index: number)
	local model = Build.model("Beehive", parent)
	local base = CFrame.new(at.X, Build.groundY(at.X, at.Z), at.Z)
	Build.at(model, base, Vector3.new(3.4, 2, 3.4), CFrame.new(0, 1, 0), Build.WOOD, Enum.Material.WoodPlanks)
	Build.at(model, base, Vector3.new(3, 1.6, 3), CFrame.new(0, 2.8, 0), Color3.fromRGB(220, 165, 70), Enum.Material.SmoothPlastic)
	Build.at(model, base, Vector3.new(3, 1.4, 3), CFrame.new(0, 4.3, 0), Color3.fromRGB(205, 150, 60), Enum.Material.SmoothPlastic)
	Build.at(model, base, Vector3.new(4, 0.5, 4), CFrame.new(0, 5.2, 0), Build.WOOD, Enum.Material.WoodPlanks)
	gatherSpot(model, base * CFrame.new(0, 3, 0), "honey", `beehive_{index}`)
end

local function leafyTree(base: CFrame, parent: Instance, scale: number, apples: boolean): Model
	local model = Build.model(if apples then "AppleTree" else "Tree", parent)
	local at = base.Position
	local trunk = 8 * scale
	Build.cylinder(model, base, trunk, 1.7 * scale, Vector3.new(0, trunk / 2, 0), Build.BARK, Enum.Material.Wood)
	local leafProps = { CanCollide = false, CanQuery = false }
	Build.ball(model, at + Vector3.new(0, trunk + 2.5 * scale, 0), 11 * scale, Build.LEAF, Enum.Material.Grass, leafProps)
	Build.ball(model, at + Vector3.new(2.2 * scale, trunk + 5 * scale, -1.2 * scale), 7 * scale, Color3.fromRGB(85, 155, 70), Enum.Material.Grass, leafProps)
	if apples then
		for i = 0, 5 do
			local a = i * 1.05
			Build.ball(model, at + Vector3.new(math.cos(a) * 5 * scale, trunk + (i % 3) * 1.6 * scale, math.sin(a) * 5 * scale), 1.2, Color3.fromRGB(215, 35, 30), nil, leafProps)
		end
	end
	return model
end

local function pineTree(base: CFrame, parent: Instance, scale: number): Model
	local model = Build.model("Pine", parent)
	local trunk = 6 * scale
	Build.cylinder(model, base, trunk, 1.4 * scale, Vector3.new(0, trunk / 2, 0), Build.BARK, Enum.Material.Wood)
	for tier = 0, 3 do
		local width = (10 - tier * 2.3) * scale
		local height = 3.2 * scale
		Build.at(model, base, Vector3.new(width, height, width), CFrame.new(0, trunk - 1 + tier * 3 * scale, 0) * CFrame.Angles(0, math.rad(45 * tier), 0), Build.PINE, Enum.Material.Grass, { CanCollide = false, CanQuery = false })
	end
	return model
end

local function rock(base: CFrame, parent: Instance, size: number, tiltX: number, tiltZ: number, shade: number): BasePart
	return Build.part({
		Name = "Rock",
		Size = Vector3.new(size * 1.6, size * 0.9, size * 1.3),
		CFrame = base * CFrame.new(0, size * 0.2, 0) * CFrame.Angles(tiltX, 0, tiltZ),
		Color = Color3.fromRGB(128 + shade, 124, 118),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

local function fence(parent: Instance)
	local model = Build.model("Fence", parent)
	local radius = Config.VILLAGE_RADIUS + 4
	local count = 56
	local posts: { Vector3? } = {}
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local x, z = math.cos(a) * radius, math.sin(a) * radius
		if pathDistance(x, z) > 12 then
			posts[i + 1] = Vector3.new(x, Build.groundY(x, z), z)
		end
	end
	for i = 1, count do
		local p = posts[i]
		local q = posts[i % count + 1]
		if p then
			Build.at(model, CFrame.new(p), Vector3.new(1, 5, 1), CFrame.new(0, 2.5, 0), Build.WOOD, Enum.Material.Wood)
			if q then
				local mid = (p + q) / 2
				local length = (q - p).Magnitude
				local look = CFrame.lookAt(mid, mid + Vector3.new(q.X - p.X, 0, q.Z - p.Z))
				for _, railY in { 1.8, 3.6 } do
					Build.at(model, look, Vector3.new(0.4, 0.5, length), CFrame.new(0, railY, 0), Build.WOOD, Enum.Material.Wood)
				end
			end
		end
	end
end

local function signpost(parent: Instance, at: Vector3)
	local model = Build.model("Signpost", parent)
	local base = CFrame.new(at.X, Build.groundY(at.X, at.Z), at.Z)
	local post = Build.cylinder(model, base, 10, 1, Vector3.new(0, 5, 0), Build.WOOD, Enum.Material.Wood)
	local board = Color3.fromRGB(160, 120, 70)
	Build.at(model, base, Vector3.new(6, 1.4, 0.4), CFrame.new(-3.2, 8.6, 0), board, Enum.Material.WoodPlanks) -- west
	Build.at(model, base, Vector3.new(0.4, 1.4, 6), CFrame.new(0, 7, -3.2), board, Enum.Material.WoodPlanks) -- north
	Build.at(model, base, Vector3.new(6, 1.4, 0.4), CFrame.new(3.2, 5.4, 0), board, Enum.Material.WoodPlanks) -- east
	Interactables.add(post, {
		actionText = "Read",
		objectText = "Signpost",
		speaker = "Crossroads signpost",
		lines = {
			"West: Whispering Woods. Wolves and bears; beyond them the Fairy Glade and the Labyrinth Ruins.",
			"North: Ashen Peaks. Ember slimes, lava and the Elder Dragon's den.",
			"East: the Shattered Rift. Sealed until you carry two Sigils.",
		},
	})
end

local function gate(parent: Instance, at: Vector3)
	local model = Build.model("CrossroadsGate", parent)
	local base = CFrame.new(at.X, Build.groundY(at.X, at.Z), at.Z)
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(3, 16, 3), CFrame.new(sx * 11, 8, 0), Build.STONE, Enum.Material.Cobblestone)
	end
	Build.at(model, base, Vector3.new(26, 2.2, 3.4), CFrame.new(0, 17, 0), Build.STONE, Enum.Material.Cobblestone)
	Build.at(model, base, Vector3.new(7, 2, 0.6), CFrame.new(0, 19.4, 0), Color3.fromRGB(240, 200, 90), Enum.Material.Neon)
	local ward = Build.at(model, base, Vector3.new(19, 15, 1), CFrame.new(0, 7.5, -0.5), Color3.fromRGB(140, 110, 255), Enum.Material.ForceField, {
		Name = "Ward",
		Transparency = 0.1,
	})
	Interactables.add(ward, {
		actionText = "Touch the ward",
		objectText = "The Crossroads",
		speaker = "The Crossroads",
		distance = 16,
		lines = {
			"A shimmering ward blocks the road. Beyond it lie the paths to the Whispering Woods, the Ashen Peaks and the Shattered Rift.",
			"The ward will lift when the Whispering Woods open.",
		},
	})
end

local function elder(parent: Instance, at: Vector3)
	local model = Build.model("ElderMaren", parent)
	local y = Build.groundY(at.X, at.Z)
	local base = CFrame.new(at.X, y, at.Z)
	local robe = Color3.fromRGB(90, 80, 120)
	Build.at(model, base, Vector3.new(2.6, 4.2, 1.8), CFrame.new(0, 2.1, 0), robe, Enum.Material.Fabric)
	local torso = Build.at(model, base, Vector3.new(2.8, 2.2, 1.6), CFrame.new(0, 5.2, 0), robe, Enum.Material.Fabric)
	local head = Build.at(model, base, Vector3.new(1.7, 1.7, 1.7), CFrame.new(0, 7.15, 0), Color3.fromRGB(230, 190, 160), nil, { Name = "Head" })
	Build.at(model, base, Vector3.new(1.9, 0.7, 1.9), CFrame.new(0, 8.1, 0.05), Color3.fromRGB(235, 235, 240), Enum.Material.Fabric) -- hair
	Build.at(model, base, Vector3.new(1.3, 1.4, 0.4), CFrame.new(0, 6.3, -0.9), Color3.fromRGB(240, 240, 245), Enum.Material.Fabric) -- beard (front is -Z)
	for _, sx in { -1, 1 } do
		Build.at(model, base, Vector3.new(0.25, 0.2, 0.1), CFrame.new(sx * 0.4, 7.35, -0.86), Color3.fromRGB(30, 25, 25))
		Build.at(model, base, Vector3.new(0.8, 2.4, 0.8), CFrame.new(sx * 1.8, 5.1, 0), robe, Enum.Material.Fabric)
	end
	Build.at(model, base, Vector3.new(0.4, 9, 0.4), CFrame.new(2.4, 4.5, -0.6), Build.WOOD, Enum.Material.Wood) -- staff
	Build.ball(model, (base * CFrame.new(2.4, 9.3, -0.6)).Position, 1.1, Color3.fromRGB(120, 230, 150), Enum.Material.Neon)
	Build.nameTag(head, "Elder Maren", nil, 2.6)
	model.PrimaryPart = torso
	-- Face the plaza and the player's spawn point.
	model:PivotTo(CFrame.lookAt(model:GetPivot().Position, Vector3.new(0, model:GetPivot().Position.Y, 30)))
	Interactables.add(torso, {
		actionText = "Talk",
		objectText = "Elder Maren",
		speaker = "Elder Maren",
		faceModel = model,
		-- What she says depends on the player's quests (Shared/QuestData).
		getLines = function(player: Player)
			return Quests.talk(player, "elder")
		end,
	})
end

local function buildVillage()
	local village = Build.folder("Village", workspace)
	placeHouse(village, "ElderHall", "ElderHall", v2(-14, -16), 31, 24, 15, 0, Color3.fromRGB(160, 50, 40))
	placeHouse(village, "HouseSmall", "HouseNorthEast", v2(15, -18), 21, 21, 11, 0, Color3.fromRGB(110, 78, 52))
	placeHouse(village, "HouseWide", "HouseWest", v2(-24, 8), 24, 21, 11, 1, Color3.fromRGB(160, 50, 40))
	placeHouse(village, "HouseWide", "HouseEast", v2(24, 10), 24, 21, 11, 3, Color3.fromRGB(70, 90, 145))
	placeHouse(village, "HouseSmall", "HouseSouth", v2(-9, 24), 21, 21, 12, 2, Color3.fromRGB(110, 78, 52))
	Assets.place("Campfire", ground(v2(0, 4)), village, campfire)
	Assets.place("Well", ground(v2(7, 9)), village, well)
	workbench(village, v2(9, -7))
	wheatField(village, v2(20, 28))
	for i, p in { v2(-28, 24), v2(-32, 19), v2(-24, 29) } do
		beehive(village, p, i)
	end
	for i, p in { v2(-30, -4), v2(-33, 7), v2(30, -7), v2(34, 2), v2(-4, 36) } do
		gatherSpot(village, ground(p) * CFrame.new(0, 4, 0), "apple", `apple_tree_{i}`)
		Assets.place("AppleTree", ground(p, (p.X * 7.1 + p.Z * 3.7) % (math.pi * 2)), village, function(base, into)
			return leafyTree(base, into, 1, true)
		end)
	end
	fence(village)
	signpost(village, v2(4, -52))
	gate(village, Vector3.new(0, 0, -364))
	elder(village, ELDER)

	local training = Build.folder("TrainingGround", workspace)
	for _, p in { v2(13, -1), v2(16, 1.5), v2(19, -1) } do
		Dummy.create(training, Vector3.new(p.X, Build.groundY(p.X, p.Z), p.Z), Vector3.new(0, 0, p.Z))
	end
end

local function buildScenery()
	local scenery = Build.folder("Scenery", workspace)
	local placed = 0
	for _ = 1, 1400 do
		local x = rng:NextNumber(-HALF + 10, HALF - 10)
		local z = rng:NextNumber(-HALF + 10, HALF - 10)
		local fromCentre = math.sqrt(x * x + z * z)
		local nearPond = (Vector3.new(x, 0, z) - POND).Magnitude < POND_RADIUS + 18
		if fromCentre > Config.VILLAGE_RADIUS + 25 and not nearPond and pathDistance(x, z) > 16 then
			local y = Build.groundY(x, z)
			local roll = rng:NextNumber()
			-- Keep the order of rng calls the same, so the layout doesn't change between builds.
			if roll < 0.24 then
				local scale = rng:NextNumber(0.9, 1.6)
				if rng:NextNumber() < 0.6 then
					local cframe = CFrame.new(x, y, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
					Assets.place("Pine", cframe, scenery, function(base, into)
						return pineTree(base, into, scale)
					end, scale)
				else
					local cframe = CFrame.new(x, y, z) * CFrame.Angles(0, (x * 7.1 + z * 3.7) % (math.pi * 2), 0)
					Assets.place("Tree", cframe, scenery, function(base, into)
						return leafyTree(base, into, scale, false)
					end, scale)
				end
				placed += 1
			elseif roll < 0.32 then
				-- Replacement rock models are made at the size of a size-4 grey rock and scaled.
				local size = rng:NextNumber(2, 6)
				local tiltX, yaw, tiltZ = rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)
				local shade = rng:NextInteger(-10, 10)
				Assets.place("Rock", CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), scenery, function(base, into)
					return rock(base, into, size, tiltX, tiltZ, shade)
				end, size / 4)
			end
		end
	end
	return placed
end

local function buildSpawn()
	Build.part({
		Class = "SpawnLocation",
		Name = "VillageSpawn",
		Size = Vector3.new(8, 1, 8),
		-- New arrivals face Elder Maren (characters spawn looking along the spawn's -Z).
		CFrame = CFrame.lookAt(Config.SPAWN_POSITION, Vector3.new(ELDER.X, Config.SPAWN_POSITION.Y, ELDER.Z)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Duration = 0,
		Neutral = true,
		Parent = workspace,
	})
end

local function buildCreatures()
	Creature.start()
	Creature.spawner(CreatureData.creatures.wolf, v2(-72, -40), 3, 40)
	Creature.spawner(CreatureData.creatures.wolf, v2(74, -30), 3, 40)
	Creature.spawner(CreatureData.creatures.boar, v2(-55, 70), 3, 45)
	-- Foxes in the south meadow, one group each side of the pond path, well away from the wolves.
	Creature.spawner(CreatureData.creatures.fox, v2(-12, 88), 3, 45)
	Creature.spawner(CreatureData.creatures.fox, v2(62, 52), 3, 45)
end

function Hearthmoor.build()
	local started = os.clock()
	setupLighting()
	buildTerrain()
	buildSpawn()
	buildVillage()
	local trees = buildScenery()
	buildCreatures()
	print(string.format("[Mythbound] Hearthmoor built in %.2fs (%d trees)", os.clock() - started, trees))
end

return Hearthmoor
