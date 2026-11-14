-- CombatMovement.client.luau
-- Apenas movimentacao direcional durante Lock-On.
-- Fora do Lock-On, o controlador padrao do Roblox assume o WASD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local DEADZONE = 0.05

local humanoid
local root
local activeCharacter
local targetValue

local function getTarget()
    if not targetValue or not targetValue.Parent then return nil end

    local part = targetValue.Value
    if not part or not part:IsA("BasePart") or not part.Parent then
        return nil
    end

    local model = part:FindFirstAncestorOfClass("Model")
    local enemyHumanoid = model and model:FindFirstChildOfClass("Humanoid")
    if not enemyHumanoid or enemyHumanoid.Health <= 0 then
        return nil
    end

    return part
end

local function getInput()
    if UserInputService:GetFocusedTextBox() then return 0, 0 end

    local forward =
        (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
        - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)

    local right =
        (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
        - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)

    return forward, right
end

local function setupCharacter(character)
    activeCharacter = character
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")

    targetValue = character:FindFirstChild("LockOnTarget")
    if not targetValue then
        targetValue = Instance.new("ObjectValue")
        targetValue.Name = "LockOnTarget"
        targetValue.Parent = character
    end
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

RunService:BindToRenderStep(
    "CombatMovement",
    Enum.RenderPriority.Character.Value + 1,
    function()
        if not humanoid or not humanoid.Parent
            or not root or not root.Parent
            or humanoid.Health <= 0 then
            return
        end

        local target = getTarget()
        local rolling = activeCharacter
            and activeCharacter:GetAttribute("IsRolling")

        if rolling then
            humanoid:Move(Vector3.zero, false)
            return
        end

        -- Sem alvo: nao interferir no movimento padrao.
        if not target then return end

        local offset = target.Position - root.Position
        local forward = Vector3.new(offset.X, 0, offset.Z)

        if forward.Magnitude < DEADZONE then
            humanoid:Move(Vector3.zero, false)
            return
        end

        forward = forward.Unit
        local right = forward:Cross(Vector3.yAxis).Unit
        local forwardInput, rightInput = getInput()

        local direction =
            forward * forwardInput + right * rightInput

        if direction.Magnitude > 1 then
            direction = direction.Unit
        end

        humanoid:Move(direction, false)
    end
)
