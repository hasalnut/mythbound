-- Talk to NPCs and read signs. Uses ProximityPrompts, which work with keyboard (F),
-- controller (Y) and touch automatically.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Interactables = {}

local dialogueEvent = Net.event("Dialogue")

export type Options = {
	actionText: string, -- e.g. "Talk"
	objectText: string, -- e.g. "Elder Maren"
	speaker: string,
	lines: { string }?,
	getLines: ((player: Player) -> { string })?, -- decides the lines per player (e.g. quest givers)
	distance: number?,
	faceModel: Model?, -- turns this model to face the player when used
}

function Interactables.add(anchor: BasePart, options: Options): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = options.actionText
	prompt.ObjectText = options.objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = options.distance or 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local face = options.faceModel
		local character = player.Character
		if face and character and character.PrimaryPart then
			local pivot = face:GetPivot()
			local target = character.PrimaryPart.Position
			face:PivotTo(CFrame.lookAt(pivot.Position, Vector3.new(target.X, pivot.Position.Y, target.Z)))
		end
		local lines = if options.getLines then options.getLines(player) else options.lines
		if lines then
			dialogueEvent:FireClient(player, options.speaker, lines)
		end
	end)
	return prompt
end

-- A prompt that runs `onTriggered(player)` (gathering, the workbench). F / controller Y / touch.
function Interactables.prompt(anchor: BasePart, actionText: string, objectText: string, onTriggered: (Player) -> (), distance: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(onTriggered)
	return prompt
end

return Interactables
