
-- CombatMovement.client.luau
-- Movimentação terrestre com lock-on

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local dummy = Workspace:WaitForChild("TrainingDummy")

local WALK_SPEED = 12
local DEADZONE = 0.05

local humanoid
local root

local input = {
    Forward = false,
    Backward = false,
    Left = false,
    Right = false
}

local function setupCharacter(character)
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")

    humanoid.AutoRotate = false
    humanoid.WalkSpeed = WALK_SPEED
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

local function handleMovement(actionName, inputState)
    local pressed = inputState == Enum.UserInputState.Begin

    if inputState ~= Enum.UserInputState.Begin
        and inputState ~= Enum.UserInputState.End
        and inputState ~= Enum.UserInputState.Cancel then
        return Enum.ContextActionResult.Pass
    end

    input[actionName] = pressed

    return Enum.ContextActionResult.Sink
end

ContextActionService:BindActionAtPriority(
    "Forward",
    handleMovement,
    false,
    3000,
    Enum.KeyCode.W
)

ContextActionService:BindActionAtPriority(
    "Backward",
    handleMovement,
    false,
    3000,
    Enum.KeyCode.S
)

ContextActionService:BindActionAtPriority(
    "Left",
    handleMovement,
    false,
    3000,
    Enum.KeyCode.A
)

ContextActionService:BindActionAtPriority(
    "Right",
    handleMovement,
    false,
    3000,
    Enum.KeyCode.D
)

RunService:BindToRenderStep(
    "CombatMovement",
    Enum.RenderPriority.Input.Value + 1,
    function()
        if not humanoid or not root or humanoid.Health <= 0 then
            return
        end

        local targetRoot = dummy:FindFirstChild("HumanoidRootPart")

        if not targetRoot then
            humanoid:Move(Vector3.zero, false)
            return
        end

        local offset = targetRoot.Position - root.Position
        local forward = Vector3.new(offset.X, 0, offset.Z)

        if forward.Magnitude < DEADZONE then
            humanoid:Move(Vector3.zero, false)
            return
        end

        forward = forward.Unit
        local right = forward:Cross(Vector3.yAxis).Unit

        local forwardInput =
            (input.Forward and 1 or 0)
            - (input.Backward and 1 or 0)

        local rightInput =
            (input.Right and 1 or 0)
            - (input.Left and 1 or 0)

        local moveDirection =
            forward * forwardInput
            + right * rightInput

        if moveDirection.Magnitude > 1 then
            moveDirection = moveDirection.Unit
        end

        humanoid:Move(moveDirection, false)
    end
)
