-- PlayerCamera.client.luau
-- C alterna primeira pessoa com corpo visivel.
-- Cabeca, acessorios e ferramentas ficam ocultos apenas localmente.
-- Compatibilidade com CombatCamera (Lock-On).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local TOGGLE_KEY = Enum.KeyCode.C
local MOUSE_SENSITIVITY = 0.0025
local MAX_PITCH = math.rad(80)
local EYE_OFFSET = Vector3.new(0, 0.15, 0)

local character
local humanoid
local root
local head
local enabled = false
local yaw = 0
local pitch = 0
local savedMouseBehavior
local savedMouseIconEnabled
local savedCameraMode

local function isHiddenPart(part)
    if part == head then return true end
    local ancestor = part:FindFirstAncestorWhichIsA("Accessory")
    if ancestor then return true end
    if part:FindFirstAncestorWhichIsA("Tool") then return true end
    return false
end

local function updateVisibility()
    if not character then return end
    for _, item in ipairs(character:GetDescendants()) do
        if item:IsA("BasePart") then
            if enabled then
                item.LocalTransparencyModifier = isHiddenPart(item) and 1 or 0
            else
                item.LocalTransparencyModifier = 0
            end
        end
    end
end

local function setFirstPerson(value)
    if enabled == value then return end
    enabled = value

    if character then
        character:SetAttribute("IsFirstPerson", enabled)
    end

    local camera = Workspace.CurrentCamera
    if enabled then
        savedMouseBehavior = UserInputService.MouseBehavior
        savedMouseIconEnabled = UserInputService.MouseIconEnabled
        savedCameraMode = player.CameraMode
        player.CameraMode = Enum.CameraMode.Classic

        local look = camera and camera.CFrame.LookVector
            or (root and root.CFrame.LookVector) or Vector3.new(0, 0, -1)
        yaw = math.atan2(-look.X, -look.Z)
        pitch = math.asin(math.clamp(look.Y, -1, 1))
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
        if humanoid then humanoid.AutoRotate = false end
        if camera then camera.CameraType = Enum.CameraType.Scriptable end
    else
        UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = savedMouseIconEnabled ~= false
        if savedCameraMode then player.CameraMode = savedCameraMode end
        local lockTarget = character and character:FindFirstChild("LockOnTarget")
        local locked = lockTarget and lockTarget.Value ~= nil
        if humanoid and not character:GetAttribute("IsRolling") then
            humanoid.AutoRotate = not locked
        end
        if camera then
            camera.CameraType = locked and Enum.CameraType.Scriptable or Enum.CameraType.Custom
            if humanoid then camera.CameraSubject = humanoid end
        end
    end
    updateVisibility()
end

local function setupCharacter(newCharacter)
    enabled = false
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    head = character:WaitForChild("Head")
    character:SetAttribute("IsFirstPerson", false)
    updateVisibility()
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= TOGGLE_KEY then return end
    if UserInputService:GetFocusedTextBox() then return end
    setFirstPerson(not enabled)
end)

UserInputService.InputChanged:Connect(function(input)
    if not enabled or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    yaw -= input.Delta.X * MOUSE_SENSITIVITY
    pitch = math.clamp(pitch - input.Delta.Y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
end)

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

RunService:BindToRenderStep("PlayerCamera", Enum.RenderPriority.Camera.Value + 2, function()
    if not enabled or not character or not character.Parent or not head or not head.Parent then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    camera.CameraType = Enum.CameraType.Scriptable
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    local rotation = CFrame.fromOrientation(pitch, yaw, 0)
    camera.CFrame = CFrame.new(head.Position + EYE_OFFSET) * rotation
    camera.Focus = CFrame.new(head.Position + camera.CFrame.LookVector * 12)

    -- Shift Lock real: o corpo acompanha o yaw da camera.
    -- Durante o Roll, QuickStep controla a rotacao.
    if root and root.Parent and humanoid and humanoid.Health > 0
        and not character:GetAttribute("IsRolling") then
        humanoid.AutoRotate = false
        local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        if forward.Magnitude > 0.001 then
            root.CFrame = CFrame.lookAt(root.Position, root.Position + forward.Unit)
        end
    end

    -- O controlador padrao pode tentar ocultar o corpo; restauramos sua visibilidade.
    updateVisibility()
end)
