-- Straw training dummies. They never die: below half health they patch themselves up.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Build = require(script.Parent:WaitForChild("Build"))

local Dummy = {}

-- `facing` is a point the dummy should look at.
function Dummy.create(parent: Instance, position: Vector3, facing: Vector3): Model
	local model = Build.model("TrainingDummy", parent)
	local base = CFrame.lookAt(position, Vector3.new(facing.X, position.Y, facing.Z))

	local root = Build.at(model, base, Vector3.new(2, 6, 2), CFrame.new(0, 3, 0), Build.STRAW, nil, {
		Name = "HumanoidRootPart",
		Transparency = 1,
		CanCollide = false,
	})
	Build.cylinder(model, base, 6, 0.8, Vector3.new(0, 3, 0), Build.WOOD, Enum.Material.Wood)
	Build.at(model, base, Vector3.new(2.6, 3, 1.5), CFrame.new(0, 3.9, 0), Build.STRAW, Enum.Material.Fabric)
	Build.at(model, base, Vector3.new(5.5, 0.6, 0.6), CFrame.new(0, 4.6, 0), Build.WOOD, Enum.Material.Wood)
	Build.at(model, base, Vector3.new(1.8, 1.8, 1.8), CFrame.new(0, 6.3, 0), Build.STRAW, Enum.Material.Fabric, { Name = "Head" })
	-- Red target painted on the chest (the front is -Z).
	Build.at(model, base, Vector3.new(1.3, 1.3, 0.1), CFrame.new(0, 4.1, -0.8), Color3.fromRGB(200, 50, 45), nil, { CanCollide = false })
	Build.at(model, base, Vector3.new(0.6, 0.6, 0.12), CFrame.new(0, 4.1, -0.82), Color3.fromRGB(245, 240, 230), nil, { CanCollide = false })

	model.PrimaryPart = root

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.DisplayName = "Training Dummy"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	humanoid.HealthChanged:Connect(function(health)
		if health < humanoid.MaxHealth * 0.5 then
			humanoid.Health = humanoid.MaxHealth
		end
	end)

	model:SetAttribute("HitRadius", 2)
	model:SetAttribute("HitHeight", 4.5)
	model:SetAttribute("Hostile", false)
	CollectionService:AddTag(model, Config.TAG_DAMAGEABLE)
	return model
end

return Dummy
