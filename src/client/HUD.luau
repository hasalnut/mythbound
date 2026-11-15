-- In-game interface: health, cooldowns, target frame, dialogue, controls panel,
-- toasts, the area banner, the hurt flash, the first-person crosshair and the death screen.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClassData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassData"))
local SkillData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SkillData"))
local UI = require(script.Parent:WaitForChild("UI"))

local HUD = {}

local player = Players.LocalPlayer

local CONTROLS = table.concat({
	"<b>Move</b>  WASD · left stick",
	"<b>Look</b>  X mouse-look on/off · arrow keys · right mouse · right stick",
	"<b>Attack</b>  click or J · right trigger      <b>Skills</b>  Q · L1   E · R1",
	"<b>Jump</b>  Space · A      <b>Dash</b>  C · B      <b>Bag</b>  Tab · D-pad up",
	"<b>Potion</b>  H · D-pad down",
	"<b>Talk</b>  F · Y      <b>Lock on</b>  T · R3",
	"<b>Zoom</b>  scroll or I / O      <b>First person</b>  V · L3",
	"<b>This panel</b>  F1",
}, "\n")

local gui: ScreenGui
local classLabel: TextLabel
local hpFill: Frame
local hpText: TextLabel
local xpFill: Frame
local manaFill: Frame
local skillFills: { Frame } = {}
local skillLabels: { TextLabel } = {}
local className = "Adventurer"
local attackFill: Frame
local dashFill: Frame
local targetPanel: Frame
local targetName: TextLabel
local targetFill: Frame
local dialogue: TextButton
local dialogueSpeaker: TextLabel
local dialogueText: TextLabel
local controls: Frame
local controlsHint: TextLabel
local toastList: Frame
local banner: TextLabel
local vignette: Frame
local crosshair: Frame
local deathScreen: Frame

local dialogueLines: { string } = {}
local dialogueIndex = 0
local dialogueClosedAt = 0
local controlsOpen = true
local controlsTimer = 30
local lastHealth = 0

HUD.onChangeClass = nil :: (() -> ())?

-- The HUD's ScreenGui, so other HUD pieces (the quest tracker) show and hide with it.
function HUD.getGui(): ScreenGui
	return gui
end

-- Class, level and the XP bar, from the Level / XP / XPNext attributes the server keeps up to date.
local function refreshProgress()
	local level = (player:GetAttribute("Level") :: number?) or 1
	local xp = (player:GetAttribute("XP") :: number?) or 0
	local nextXp = (player:GetAttribute("XPNext") :: number?) or 1
	classLabel.Text = `{className} · Level {level}`
	xpFill.Size = UDim2.fromScale(math.clamp(xp / math.max(nextXp, 1), 0, 1), 1)
end

local function refreshMana()
	local mana = (player:GetAttribute("Mana") :: number?) or 0
	local maxMana = (player:GetAttribute("MaxMana") :: number?) or 1
	manaFill.Size = UDim2.fromScale(math.clamp(mana / math.max(maxMana, 1), 0, 1), 1)
end

-- 0 = just used, 1 = ready.
function HUD.setSkillCooldowns(q: number, e: number)
	skillFills[1].Size = UDim2.fromScale(math.clamp(q, 0, 1), 1)
	skillFills[2].Size = UDim2.fromScale(math.clamp(e, 0, 1), 1)
end

function HUD.isDialogueOpen(): boolean
	return dialogue ~= nil and dialogue.Visible
end

local function closeDialogue()
	dialogue.Visible = false
	dialogueClosedAt = os.clock()
	ContextActionService:UnbindAction("MythboundDialogue")
	-- Prompts come back a moment later, so the key that closed the dialogue can't reopen it.
	task.delay(0.3, function()
		if not dialogue.Visible then
			ProximityPromptService.Enabled = true
		end
	end)
end

local function advanceDialogue()
	dialogueIndex += 1
	if dialogueIndex > #dialogueLines then
		closeDialogue()
	else
		dialogueText.Text = dialogueLines[dialogueIndex]
	end
end

function HUD.showDialogue(speaker: string, lines: { string })
	-- The key that closed the last dialogue can re-trigger the prompt; ignore that.
	if dialogue.Visible or os.clock() - dialogueClosedAt < 0.4 or #lines == 0 then
		return
	end
	-- While talking, prompts are switched off on this client. Otherwise F (the prompt key) would
	-- trigger the prompt again and restart the conversation instead of advancing it.
	ProximityPromptService.Enabled = false
	dialogueLines = lines
	dialogueIndex = 1
	dialogueSpeaker.Text = speaker
	dialogueText.Text = lines[1]
	dialogue.Visible = true
	ContextActionService:BindActionAtPriority("MythboundDialogue", function(_, state)
		if state == Enum.UserInputState.Begin then
			advanceDialogue()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.F, Enum.KeyCode.E, Enum.KeyCode.Return, Enum.KeyCode.ButtonA, Enum.KeyCode.ButtonY)
end

function HUD.toast(text: string)
	local label = UI.make("TextLabel", {
		BackgroundColor3 = UI.PANEL,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(340, 34),
		Text = text,
		TextColor3 = UI.INK,
		Font = UI.FONT_BOLD,
		TextSize = 16,
		Parent = toastList,
	}, { UI.corner(8) })
	task.delay(3, function()
		local fade = TweenInfo.new(0.5)
		TweenService:Create(label, fade, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.5)
		label:Destroy()
	end)
end

function HUD.banner(text: string)
	banner.Text = text
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	TweenService:Create(banner, TweenInfo.new(0.8), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	task.delay(3.5, function()
		TweenService:Create(banner, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

function HUD.setCooldowns(attack: number, dash: number)
	attackFill.Size = UDim2.fromScale(math.clamp(attack, 0, 1), 1)
	dashFill.Size = UDim2.fromScale(math.clamp(dash, 0, 1), 1)
end

function HUD.setTarget(model: Model?)
	if not model or not model.Parent then
		targetPanel.Visible = false
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		targetPanel.Visible = false
		return
	end
	targetPanel.Visible = true
	targetName.Text = humanoid.DisplayName ~= "" and humanoid.DisplayName or model.Name
	targetFill.Size = UDim2.fromScale(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 1)
end

-- A dot in the middle of the screen, for first person and mouse-look.
function HUD.setCrosshair(on: boolean)
	crosshair.Visible = on
end

-- Hides the whole HUD (behind the class select screen, and before the first spawn).
function HUD.setVisible(on: boolean)
	gui.Enabled = on
end

function HUD.toggleControls()
	controlsOpen = not controlsOpen
	controlsTimer = 0 -- once toggled by hand it stays as the player left it
end

function HUD.update(dt: number)
	if controlsTimer > 0 then
		controlsTimer -= dt
		if controlsTimer <= 0 then
			controlsOpen = false
		end
	end
	controls.Visible = controlsOpen and not dialogue.Visible
	controlsHint.Visible = not controls.Visible and not dialogue.Visible
	vignette.BackgroundTransparency = math.min(1, vignette.BackgroundTransparency + dt * 1.5)
end

local function onHealth(health: number, maxHealth: number)
	hpFill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
	hpText.Text = string.format("%d / %d", math.ceil(health), maxHealth)
	if health < lastHealth then
		vignette.BackgroundTransparency = 0.72
	end
	lastHealth = health
end

function HUD.bindCharacter(character: Model)
	deathScreen.Visible = false
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local info = ClassData.get(player:GetAttribute("Class"))
	className = if info then info.name else "Adventurer"
	refreshProgress()
	for slot, key in { "Q", "E" } do
		local skill = info and SkillData.forClass(info.id, slot)
		skillLabels[slot].Text = if skill then `{key} · {skill.name}` else key
	end
	lastHealth = humanoid.Health
	onHealth(humanoid.Health, humanoid.MaxHealth)
	humanoid.HealthChanged:Connect(function(health)
		onHealth(health, humanoid.MaxHealth)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		onHealth(humanoid.Health, humanoid.MaxHealth)
	end)
	humanoid.Died:Connect(function()
		deathScreen.Visible = true
	end)
end

function HUD.init()
	gui = UI.make("ScreenGui", {
		Name = "MythboundHUD",
		Enabled = false, -- shown once the character spawns
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})

	vignette = UI.make("Frame", {
		BackgroundColor3 = UI.RED,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 60),
		Position = UDim2.fromOffset(0, -60),
		ZIndex = 0,
		Parent = gui,
	})

	-- Health and cooldowns, top left.
	local status = UI.panel({ Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(280, 132), Parent = gui })
	UI.padding(10).Parent = status
	classLabel = UI.label("", 17, UI.GOLD, true)
	classLabel.Parent = status
	local hpBack
	hpBack, hpFill = UI.bar(UI.RED, 18)
	hpBack.Position = UDim2.fromOffset(0, 26)
	hpBack.Parent = status
	hpText = UI.label("", 13, UI.INK, true)
	hpText.TextXAlignment = Enum.TextXAlignment.Center
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.ZIndex = 3
	hpText.Parent = hpBack
	local chips = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18), Parent = status })
	local manaBack
	manaBack, manaFill = UI.bar(Color3.fromRGB(80, 130, 230), 7)
	manaBack.Name = "ManaBar"
	manaBack.Position = UDim2.fromOffset(0, 46)
	manaBack.Parent = status
	for _, name in { "Mana", "MaxMana" } do
		player:GetAttributeChangedSignal(name):Connect(refreshMana)
	end
	local skillRow = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 78), Size = UDim2.new(1, 0, 0, 18), Parent = status })
	local function chip(text: string, x: number, row: Frame?): (Frame, TextLabel)
		local back, fill = UI.bar(Color3.fromRGB(150, 120, 60), 18)
		back.Size = UDim2.new(0.5, -4, 1, 0)
		back.Position = UDim2.new(x, if x > 0 then 4 else 0, 0, 0)
		back.Parent = row or chips
		local label = UI.label(text, 12, UI.INK, true)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 3
		label.Parent = back
		return fill, label
	end
	attackFill = chip("Attack", 0)
	dashFill = chip("Dash", 0.5)
	for slot = 1, 2 do
		skillFills[slot], skillLabels[slot] = chip(if slot == 1 then "Q" else "E", (slot - 1) * 0.5, skillRow)
	end
	refreshMana()
	local xpBack
	xpBack, xpFill = UI.bar(Color3.fromRGB(110, 175, 245), 8)
	xpBack.Name = "XPBar"
	xpBack.Position = UDim2.fromOffset(0, 102)
	xpBack.Parent = status
	for _, name in { "Level", "XP", "XPNext" } do
		player:GetAttributeChangedSignal(name):Connect(refreshProgress)
	end
	refreshProgress()

	local change = UI.button("Change class", {
		Name = "ChangeClass",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(140, 34),
		TextSize = 14,
		Parent = gui,
	})
	change.Activated:Connect(function()
		if HUD.onChangeClass then
			HUD.onChangeClass()
		end
	end)

	-- Target frame, top centre.
	targetPanel = UI.panel({
		Name = "TargetFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(300, 56),
		Visible = false,
		Parent = gui,
	})
	UI.padding(8).Parent = targetPanel
	targetName = UI.label("", 15, UI.INK, true)
	targetName.TextXAlignment = Enum.TextXAlignment.Center
	targetName.Parent = targetPanel
	local targetBack
	targetBack, targetFill = UI.bar(UI.RED, 12)
	targetBack.Position = UDim2.fromOffset(0, 24)
	targetBack.Parent = targetPanel

	-- Area banner.
	banner = UI.make("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(600, 50),
		Font = UI.FONT_BOLD,
		TextSize = 40,
		TextColor3 = Color3.fromRGB(255, 240, 210),
		TextStrokeColor3 = Color3.fromRGB(40, 25, 10),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Text = "",
		Parent = gui,
	})

	-- Toasts, right side.
	toastList = UI.make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 180), -- below the quest tracker
		Size = UDim2.fromOffset(340, 300),
		Parent = gui,
	}, {
		UI.make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right }),
	})

	-- Dialogue box, bottom centre. Clicking it also advances.
	dialogue = UI.make("TextButton", {
		Name = "Dialogue",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = UI.PANEL,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0.6, 0, 0, 140),
		Visible = false,
		Parent = gui,
	}, { UI.corner(10), UI.stroke(UI.GOLD), UI.padding(16), UI.make("UISizeConstraint", { MinSize = Vector2.new(320, 0), MaxSize = Vector2.new(760, 200) }) })
	dialogueSpeaker = UI.label("", 20, UI.GOLD, true)
	dialogueSpeaker.Parent = dialogue
	dialogueText = UI.label("", 18)
	dialogueText.TextWrapped = true
	dialogueText.TextYAlignment = Enum.TextYAlignment.Top
	dialogueText.Position = UDim2.fromOffset(0, 30)
	dialogueText.Size = UDim2.new(1, 0, 1, -50)
	dialogueText.Parent = dialogue
	local more = UI.label("F, Enter or click to continue", 13, UI.MUTED)
	more.TextXAlignment = Enum.TextXAlignment.Right
	more.AnchorPoint = Vector2.new(0, 1)
	more.Position = UDim2.fromScale(0, 1)
	more.Parent = dialogue
	dialogue.Activated:Connect(advanceDialogue)

	-- Controls panel, bottom left; tucks itself away after 30 seconds.
	controls = UI.panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(470, 194),
		Parent = gui,
	})
	UI.padding(12).Parent = controls
	local controlsText = UI.label(CONTROLS, 14)
	controlsText.RichText = true
	controlsText.TextYAlignment = Enum.TextYAlignment.Top
	controlsText.Size = UDim2.fromScale(1, 1)
	controlsText.LineHeight = 1.15
	controlsText.Parent = controls
	controlsHint = UI.label("F1  Controls", 13, UI.MUTED)
	controlsHint.AnchorPoint = Vector2.new(0, 1)
	controlsHint.Position = UDim2.new(0, 18, 1, -10)
	controlsHint.Size = UDim2.fromOffset(200, 20)
	controlsHint.Parent = gui

	crosshair = UI.make("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	}, { UI.corner(3) })

	deathScreen = UI.make("Frame", {
		Name = "DeathScreen",
		BackgroundColor3 = Color3.fromRGB(20, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.new(1, 0, 1, 60),
		Position = UDim2.fromOffset(0, -60),
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	local fell = UI.label("You fell. Returning to Hearthmoor…", 34, Color3.fromRGB(255, 220, 210), true)
	fell.TextXAlignment = Enum.TextXAlignment.Center
	fell.AnchorPoint = Vector2.new(0.5, 0.5)
	fell.Position = UDim2.fromScale(0.5, 0.5)
	fell.Size = UDim2.fromOffset(700, 50)
	fell.ZIndex = 11
	fell.Parent = deathScreen

	gui.Parent = player:WaitForChild("PlayerGui")
end

return HUD
