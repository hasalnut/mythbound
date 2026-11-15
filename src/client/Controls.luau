-- Player input: attack, dash, lock-on, first person, mouse-look and the controls panel.
--
-- Mouse-look (X) locks the mouse to the middle of the screen so moving it turns the camera,
-- like Roblox's Shift Lock but without needing it switched on in Roblox's settings. It is for
-- trackpads and anyone who doesn't want to hold the right button. It pauses by itself while a
-- menu or dialogue is open, so the pointer is free to click.
-- Uses ContextActionService so keyboard, controller and touch all work; on phones the
-- `true` argument adds an on-screen button for that action.

local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local Net = require(Shared:WaitForChild("Net"))
local HUD = require(script.Parent:WaitForChild("HUD"))

local Controls = {}

local player = Players.LocalPlayer
local attackEvent = Net.event("Attack")
local dashEvent = Net.event("Dash")
local skillEvent = Net.event("UseSkill")

local attackHeld = false
local attackInput: InputObject? = nil
local attackCooldown = 0
local dashCooldown = 0
local skillCooldown = { 0, 0 } -- seconds left, per slot (Q, E); set when the server confirms
local skillDuration = { 1, 1 }
local lockTarget: Model? = nil
local recentTarget: Model? = nil
local recentTargetTime = 0
local lockMarker: BillboardGui? = nil
local firstPerson = false
local mouseLook = false
local lockingMouse = false -- true while mouse-look is holding the pointer in the middle

local function character(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	if not c then
		return nil, nil, nil
	end
	local humanoid = c:FindFirstChildOfClass("Humanoid")
	local root = c:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return c, humanoid, root
end

local function alive(model: Model?): boolean
	if not model or not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function rootOf(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Lock-on --------------------------------------------------------------------------------

local function setLock(model: Model?)
	if lockMarker then
		lockMarker:Destroy()
		lockMarker = nil
	end
	lockTarget = model
	if model then
		local root = rootOf(model)
		if root then
			local marker = Instance.new("BillboardGui")
			marker.Name = "LockOnMarker"
			marker.Size = UDim2.fromOffset(36, 36)
			marker.StudsOffset = Vector3.new(0, ((model:GetAttribute("HitHeight") :: number?) or 4) + 1.5, 0)
			marker.AlwaysOnTop = true
			marker.Adornee = root
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Text = "◎"
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 220, 120)
			label.TextStrokeTransparency = 0.3
			label.Parent = marker
			marker.Parent = player:WaitForChild("PlayerGui")
			lockMarker = marker
		end
	end
end

local function findLockTarget(): Model?
	local _, _, root = character()
	if not root then
		return nil
	end
	local camera = workspace.CurrentCamera
	local look = flat(camera.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else flat(root.CFrame.LookVector).Unit
	local best: Model? = nil
	local bestScore = math.huge
	for _, inst in CollectionService:GetTagged(Config.TAG_DAMAGEABLE) do
		if inst:IsA("Model") and alive(inst) then
			local targetRoot = rootOf(inst)
			if targetRoot then
				local to = flat(targetRoot.Position - root.Position)
				local distance = to.Magnitude
				if distance <= Config.LOCK_RANGE and distance > 0.1 then
					local angle = math.acos(math.clamp(to.Unit:Dot(look), -1, 1))
					if angle < math.rad(70) or distance < 25 then
						local score = distance + angle * 40 - (if inst:GetAttribute("Hostile") then 20 else 0)
						if score < bestScore then
							best = inst
							bestScore = score
						end
					end
				end
			end
		end
	end
	return best
end

-- Actions ----------------------------------------------------------------------------------

local function attack()
	local _, _, root = character()
	local info = ClassData.get(player:GetAttribute("Class"))
	if not root or not info then
		return
	end
	attackCooldown = info.interval
	local aim = workspace.CurrentCamera.CFrame.LookVector
	if lockTarget and alive(lockTarget) then
		local targetRoot = rootOf(lockTarget)
		if targetRoot then
			aim = targetRoot.Position - root.Position
		end
	end
	-- Turn to face the attack.
	local facing = flat(aim)
	if facing.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
	end
	attackEvent:FireServer(aim, lockTarget)
end

-- Asks the server to use skill `slot` (1 = Q, 2 = E), aimed like a basic attack.
local function useSkill(slot: number)
	local _, _, root = character()
	if not root or skillCooldown[slot] > 0 then
		return
	end
	local aim = workspace.CurrentCamera.CFrame.LookVector
	if lockTarget and alive(lockTarget) then
		local targetRoot = rootOf(lockTarget)
		if targetRoot then
			aim = targetRoot.Position - root.Position
		end
	end
	local facing = flat(aim)
	if facing.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + facing)
	end
	skillEvent:FireServer(slot, aim, lockTarget)
end

local function dash()
	local _, humanoid, root = character()
	if not humanoid or not root or dashCooldown > 0 then
		return
	end
	dashCooldown = Config.DASH_COOLDOWN
	local direction = flat(humanoid.MoveDirection)
	if direction.Magnitude < 0.1 then
		direction = flat(root.CFrame.LookVector)
	end
	direction = direction.Unit

	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Name = "Dash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Config.DASH_SPEED
	push.MaxForce = 1e6
	push.Parent = root
	Debris:AddItem(push, Config.DASH_TIME)
	Debris:AddItem(attachment, Config.DASH_TIME)
	dashEvent:FireServer()
end

local function setMouseLook(on: boolean)
	mouseLook = on
	HUD.setCrosshair(firstPerson or mouseLook)
	HUD.toast(if on then "Mouse-look on (X to turn off)" else "Mouse-look off")
end

local function setFirstPerson(on: boolean)
	firstPerson = on
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		-- Push the camera back out to a normal third-person distance.
		player.CameraMinZoomDistance = 12
		task.delay(0.1, function()
			player.CameraMinZoomDistance = 0.5
		end)
	end
	HUD.setCrosshair(firstPerson or mouseLook)
end

-- Called by Main when the server reports damage, so the target frame can follow your last hit.
function Controls.noteHit(model: Model)
	recentTarget = model
	recentTargetTime = os.clock()
end

function Controls.reset()
	attackHeld = false
	setLock(nil)
	skillCooldown[1], skillCooldown[2] = 0, 0
end

-- Called when the server says a skill went off, to start its cooldown on the HUD.
function Controls.onSkillUsed(slot: number, cooldown: number)
	if slot == 1 or slot == 2 then
		skillCooldown[slot] = cooldown
		skillDuration[slot] = math.max(cooldown, 0.01)
	end
end

local function stillHeld(input: InputObject): boolean
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 then
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	elseif kind == Enum.UserInputType.Keyboard then
		return UserInputService:IsKeyDown(input.KeyCode)
	elseif kind.Name:sub(1, 7) == "Gamepad" then
		return UserInputService:IsGamepadButtonDown(kind, input.KeyCode)
	end
	return true -- touch buttons report their own release
end

-- Labels and places the on-screen button that phones get for an action (does nothing on PC).
local function touchButton(action: string, title: string, position: UDim2)
	pcall(function()
		ContextActionService:SetTitle(action, title)
		ContextActionService:SetPosition(action, position)
	end)
end

function Controls.start(isBlocked: () -> boolean)
	ContextActionService:BindAction("MythboundAttack", function(_, state, input)
		attackHeld = state == Enum.UserInputState.Begin
		attackInput = if attackHeld then input else nil
		return Enum.ContextActionResult.Pass
	end, true, Enum.UserInputType.MouseButton1, Enum.KeyCode.J, Enum.KeyCode.ButtonR2)
	touchButton("MythboundAttack", "Attack", UDim2.new(1, -150, 1, -150))

	ContextActionService:BindAction("MythboundDash", function(_, state)
		if state == Enum.UserInputState.Begin and not isBlocked() then
			dash()
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.C, Enum.KeyCode.ButtonB)
	touchButton("MythboundDash", "Dash", UDim2.new(1, -220, 1, -90))

	ContextActionService:BindAction("MythboundLockOn", function(_, state)
		if state == Enum.UserInputState.Begin and not isBlocked() then
			if lockTarget then
				setLock(nil)
			else
				setLock(findLockTarget())
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.T, Enum.KeyCode.ButtonR3, Enum.UserInputType.MouseButton3)
	touchButton("MythboundLockOn", "Lock", UDim2.new(1, -220, 1, -170))

	for slot, binding in { { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 }, { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 } } do
		local action = `MythboundSkill{slot}`
		ContextActionService:BindAction(action, function(_, state)
			if state == Enum.UserInputState.Begin and not isBlocked() then
				useSkill(slot)
			end
			return Enum.ContextActionResult.Pass
		end, true, binding[1], binding[2])
		touchButton(action, if slot == 1 then "Q" else "E", UDim2.new(1, -90 - slot * 70, 1, -230))
	end

	ContextActionService:BindAction("MythboundView", function(_, state)
		if state == Enum.UserInputState.Begin and not isBlocked() then
			setFirstPerson(not firstPerson)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.V, Enum.KeyCode.ButtonL3)

	ContextActionService:BindAction("MythboundMouseLook", function(_, state)
		if state == Enum.UserInputState.Begin and not isBlocked() then
			setMouseLook(not mouseLook)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.X)

	-- Runs just after Roblox's camera each frame, so this has the last word on the mouse.
	RunService:BindToRenderStep("MythboundMouseLook", Enum.RenderPriority.Camera.Value + 1, function()
		local want = mouseLook and not firstPerson and not isBlocked() and character() ~= nil
		if want then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			lockingMouse = true
		elseif lockingMouse then
			lockingMouse = false
			UserInputService.MouseIconEnabled = true
			if not firstPerson then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
	end)

	ContextActionService:BindAction("MythboundHelp", function(_, state)
		if state == Enum.UserInputState.Begin then
			HUD.toggleControls()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F1)

	RunService.RenderStepped:Connect(function(dt)
		attackCooldown = math.max(0, attackCooldown - dt)
		dashCooldown = math.max(0, dashCooldown - dt)
		local info = ClassData.get(player:GetAttribute("Class"))
		local interval = if info then info.interval else 1
		HUD.setCooldowns(1 - attackCooldown / interval, 1 - dashCooldown / Config.DASH_COOLDOWN)
		for slot = 1, 2 do
			skillCooldown[slot] = math.max(0, skillCooldown[slot] - dt)
		end
		HUD.setSkillCooldowns(1 - skillCooldown[1] / skillDuration[1], 1 - skillCooldown[2] / skillDuration[2])
		HUD.update(dt)

		-- If the button was released over a menu we never hear about it, so double-check.
		if attackHeld and attackInput and not stillHeld(attackInput) then
			attackHeld = false
		end

		local _, humanoid, root = character()
		if lockTarget then
			local targetRoot = if alive(lockTarget) then rootOf(lockTarget :: Model) else nil
			if not targetRoot or not root or (targetRoot.Position - root.Position).Magnitude > Config.LOCK_RANGE * 1.3 then
				setLock(nil)
			end
		end
		if humanoid and root then
			if lockTarget then
				-- Keep facing the locked target while moving.
				humanoid.AutoRotate = false
				local targetRoot = rootOf(lockTarget)
				if targetRoot then
					local to = flat(targetRoot.Position - root.Position)
					if to.Magnitude > 0.5 then
						root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
					end
				end
			else
				humanoid.AutoRotate = true
			end
			if attackHeld and attackCooldown <= 0 and not isBlocked() then
				attack()
			end
		end

		-- Target frame: the locked target, otherwise whatever you hit in the last few seconds.
		local shown = lockTarget
		if not shown and recentTarget and os.clock() - recentTargetTime < 4 and alive(recentTarget) then
			shown = recentTarget
		end
		HUD.setTarget(shown)
	end)
end

return Controls
