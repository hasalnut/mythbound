-- Class choice and character setup. Characters don't load until a player picks a class.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = require(Shared:WaitForChild("Progression"))
local Build = require(script.Parent:WaitForChild("Build"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local PlayerSetup = {}

local METAL = Color3.fromRGB(200, 205, 215)
local CHOOSE_COOLDOWN = 1.5 -- seconds between class changes (each one respawns the character)

local lastChoose: { [Player]: number } = {}

local function limb(character: Model, names: { string }): BasePart?
	for _, name in names do
		local part = character:WaitForChild(name, 3)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- Adds a simple weapon for the class. Parts are welded to the hands; offsets are a first guess
-- and will need tuning with real animations.
local function giveWeapon(character: Model, info: ClassData.ClassInfo)
	local old = character:FindFirstChild("ClassWeapon")
	if old then
		old:Destroy()
	end
	local holder = Instance.new("Model")
	holder.Name = "ClassWeapon"
	holder.Parent = character

	local right = limb(character, { "RightHand", "Right Arm" })
	local left = limb(character, { "LeftHand", "Left Arm" })
	if not right or not left then
		return
	end

	local function piece(hand: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local part = Build.part({
			Name = "WeaponPart",
			Size = size,
			CFrame = hand.CFrame * offset,
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
			CanQuery = false,
			CastShadow = false,
			Parent = holder,
		})
		Build.weld(part, hand)
		return part
	end

	local weapon = info.weapon
	if weapon == "daggers" then
		for _, hand in { right, left } do
			piece(hand, Vector3.new(0.3, 0.3, 0.7), CFrame.new(0, -0.5, -0.2), Build.DARK_WOOD)
			piece(hand, Vector3.new(0.15, 0.4, 2), CFrame.new(0, -0.5, -1.5), METAL, Enum.Material.Metal)
		end
	elseif weapon == "sword_shield" then
		piece(right, Vector3.new(0.35, 0.35, 1), CFrame.new(0, -0.5, -0.3), Build.DARK_WOOD)
		piece(right, Vector3.new(1.4, 0.3, 0.3), CFrame.new(0, -0.5, -0.9), Color3.fromRGB(190, 160, 80), Enum.Material.Metal)
		piece(right, Vector3.new(0.25, 0.6, 4.2), CFrame.new(0, -0.5, -3.1), METAL, Enum.Material.Metal)
		piece(left, Vector3.new(0.4, 3.4, 2.8), CFrame.new(-0.5, -0.3, 0), info.color, Enum.Material.Metal)
		piece(left, Vector3.new(0.45, 1, 1), CFrame.new(-0.55, -0.3, 0), Color3.fromRGB(190, 160, 80), Enum.Material.Metal)
	elseif weapon == "staff" or weapon == "holy_staff" then
		piece(right, Vector3.new(0.35, 7, 0.35), CFrame.new(0, 1.2, -0.3), Build.WOOD, Enum.Material.Wood)
		local orb = piece(right, Vector3.new(1, 1, 1), CFrame.new(0, 5, -0.3), info.projectileColor, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = info.projectileColor
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = orb
	elseif weapon == "bow" then
		local wood = Color3.fromRGB(120, 85, 50)
		piece(left, Vector3.new(0.3, 2.4, 0.3), CFrame.new(0, -0.4, -0.5), wood, Enum.Material.Wood)
		piece(left, Vector3.new(0.3, 1.8, 0.3), CFrame.new(0, 1.3, -0.1) * CFrame.Angles(math.rad(-25), 0, 0), wood, Enum.Material.Wood)
		piece(left, Vector3.new(0.3, 1.8, 0.3), CFrame.new(0, -2.1, -0.1) * CFrame.Angles(math.rad(25), 0, 0), wood, Enum.Material.Wood)
		piece(left, Vector3.new(0.05, 4.6, 0.05), CFrame.new(0, -0.4, 0.4), Color3.fromRGB(240, 235, 220))
	end
end

local function onCharacter(player: Player, character: Model)
	local info = ClassData.get(player:GetAttribute("Class")) or ClassData.classes.ninja
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local maxHealth = Progression.maxHealth(info.maxHealth, (player:GetAttribute("Level") :: number?) or 1)
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = info.walkSpeed
	character:SetAttribute("Class", info.id)
	character:SetAttribute("DamageReduction", info.damageReduction)
	character:SetAttribute("HitHeight", 3.5)
	-- Give the body a moment to settle at the spawn point so the weapon welds in the right place.
	task.delay(0.3, function()
		if character.Parent then
			giveWeapon(character, info)
		end
	end)

	humanoid.Died:Connect(function()
		task.delay(Config.RESPAWN_DELAY, function()
			if player.Parent and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	-- A level-up raises max health and heals fully.
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local info = ClassData.get(player:GetAttribute("Class"))
		if humanoid and humanoid.Health > 0 and info then
			local maxHealth = Progression.maxHealth(info.maxHealth, (player:GetAttribute("Level") :: number?) or 1)
			humanoid.MaxHealth = maxHealth
			humanoid.Health = maxHealth
		end
	end)
end

function PlayerSetup.start()
	Players.CharacterAutoLoads = false

	Net.event("ChooseClass").OnServerEvent:Connect(function(player: Player, classId: any)
		local info = ClassData.get(classId)
		if not info then
			return
		end
		local now = os.clock()
		if now - (lastChoose[player] or -100) < CHOOSE_COOLDOWN then
			return
		end
		lastChoose[player] = now
		-- Spawn only once the save has loaded, so level and health are right from the start.
		if not PlayerData.whenLoaded(player) or not player.Parent then
			return
		end
		PlayerData.setClass(player, info.id)
		player:SetAttribute("Class", info.id)
		player:LoadCharacter()
	end)

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastChoose[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return PlayerSetup
