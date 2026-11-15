-- Swappable art. The world builder asks for pieces by name. If a finished model with that name
-- is in ServerStorage.Assets (directly, or inside a zone folder such as Assets/Hearthmoor),
-- a copy of it is placed; otherwise the grey version is built from code. To change how a
-- house, tree or creature looks, drop a model with the same name into ServerStorage.Assets.
-- No code changes are needed. See docs/art-direction.md.
--
-- Rules for replacement models:
--   * Scenery (HouseSmall, Well, Pine, ...): a Model whose PrimaryPart sits at ground level,
--     with the front facing -Z. Without a PrimaryPart the bottom of its bounding box is used.
--   * Creatures (wolf, boar, ...): a Model named after the creature id, with a
--     HumanoidRootPart and a Humanoid whose HipHeight holds the body off the ground.
--     Creature.luau reads these with Assets.find.

local ServerStorage = game:GetService("ServerStorage")

local Assets = {}

export type Builder = (cframe: CFrame, parent: Instance) -> Instance

local cache: { [string]: Model | false } = {}
local warned: { [string]: boolean } = {}

function Assets.folder(): Folder
	local existing = ServerStorage:FindFirstChild("Assets")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Assets"
	folder.Parent = ServerStorage
	return folder
end

local function warnOnce(name: string, message: string)
	if not warned[name] then
		warned[name] = true
		warn(`[Assets] {name}: {message}`)
	end
end

-- The replacement model called `name`, or nil if there isn't one. Looks in Assets and one
-- level of zone folders below it, so models nested inside other models are never picked.
function Assets.find(name: string): Model?
	local cached = cache[name]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local found: Model? = nil
	for _, child in Assets.folder():GetChildren() do
		if child:IsA("Model") and child.Name == name then
			found = child
			break
		elseif child:IsA("Folder") then
			local inner = child:FindFirstChild(name)
			if inner and inner:IsA("Model") then
				found = inner
				break
			end
		end
	end
	if found and found:FindFirstChildWhichIsA("LuaSourceContainer", true) then
		warnOnce(name, "contains scripts. Remove them unless you wrote them (free models can hide malicious code).")
	end
	cache[name] = found or false
	return found
end

-- Moves `model` so its PrimaryPart (or the bottom centre of its bounding box) lands on `cframe`.
local function standOn(model: Model, cframe: CFrame)
	if model.PrimaryPart then
		model:PivotTo(cframe)
		return
	end
	local box, size = model:GetBoundingBox()
	local bottom = box * CFrame.new(0, -size.Y / 2, 0)
	model:PivotTo(cframe * bottom:ToObjectSpace(model:GetPivot()))
end

-- Places the scenery piece `name` at `cframe` (ground level, front facing -Z) under `parent`.
-- Uses the replacement model if there is one, otherwise calls `build(cframe, parent)` for the
-- grey version. `scale` resizes a replacement model; the grey builder handles its own size.
function Assets.place(name: string, cframe: CFrame, parent: Instance, build: Builder, scale: number?): Instance
	local template = Assets.find(name)
	if not template then
		return build(cframe, parent)
	end
	local model = template:Clone()
	if scale and math.abs(scale - 1) > 0.001 then
		model:ScaleTo(model:GetScale() * scale)
	end
	standOn(model, cframe)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true -- scenery never moves
		end
	end
	model.Parent = parent
	return model
end

return Assets
