
-- CombatCamera.client.luau
-- Camera terrestre com Lock-On dinamico

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local LOCK_ON_ENABLED = true
local TARGET_NAME = "TrainingDummy"

local MIN_DISTANCE = 12
local MAX_DISTANCE = 30
local BASE_DISTANCE = 10
local DISTANCE_PER_STUD = 0.55

local HEIGHT = 5
local FOCUS_HEIGHT = 2.5

local SMOOTHNESS = 7
local ROTATION_SMOOTHNESS = 12

-- ==========================================
-- ESTADO
-- ==========================================

local root = nil
local humanoid = nil
local activeCharacter = nil

local currentDistance = MIN_DISTANCE
local lastDirection = Vector3.new(0, 0, -1)

-- ==========================================
-- ALVO
-- ==========================================

local function getTargetRoot()
    local dummy = Workspace:FindFirstChild(TARGET_NAME)

    if not dummy then
        return nil
    end

    return dummy:FindFirstChild("HumanoidRootPart")
        or dummy.PrimaryPart
end

local function updateLockOnTarget(character)
    local targetValue = character:FindFirstChild("LockOnTarget")

    if not targetValue then
        targetValue = Instance.new("ObjectValue")
        targetValue.Name = "LockOnTarget"
        targetValue.Parent = character
    end

    if LOCK_ON_ENABLED then
        targetValue.Value = getTargetRoot()
    else
        targetValue.Value = nil
    end
end

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    activeCharacter = character

    root = character:WaitForChild("HumanoidRootPart")
    humanoid = character:WaitForChild("Humanoid")

    humanoid.AutoRotate = false
    currentDistance = MIN_DISTANCE

    updateLockOnTarget(character)
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

-- ==========================================
-- CAMERA
-- ==========================================

RunService:BindToRenderStep(
    "CombatCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        local camera = Workspace.CurrentCamera

        if not camera
            or not root
            or not root.Parent
            or not activeCharacter then
            return
        end

        updateLockOnTarget(activeCharacter)

        if not LOCK_ON_ENABLED then
            if camera.CameraType == Enum.CameraType.Scriptable then
                camera.CameraType = Enum.CameraType.Custom
                camera.CameraSubject = humanoid
            end

            if humanoid then
                humanoid.AutoRotate = true
            end

            return
        end

        local targetRoot = getTargetRoot()

        if not targetRoot then
            return
        end

        camera.CameraType = Enum.CameraType.Scriptable

        local playerPos = root.Position
        local targetPos = targetRoot.Position

        local offset = targetPos - playerPos
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)

        local separation = flatOffset.Magnitude

        if separation > 0.05 then
            lastDirection = flatOffset.Unit
        end

        local desiredDistance = math.clamp(
            BASE_DISTANCE + separation * DISTANCE_PER_STUD,
            MIN_DISTANCE,
            MAX_DISTANCE
        )

        local alpha = 1 - math.exp(-SMOOTHNESS * dt)
        local rotationAlpha =
            1 - math.exp(-ROTATION_SMOOTHNESS * dt)

        currentDistance +=
            (desiredDistance - currentDistance) * alpha

        local cameraPos =
            playerPos
            - lastDirection * currentDistance
            + Vector3.new(0, HEIGHT, 0)

        local focusPos =
            playerPos:Lerp(targetPos, 0.35)
            + Vector3.new(0, FOCUS_HEIGHT, 0)

        local desiredCFrame = CFrame.lookAt(
            cameraPos,
            focusPos
        )

        camera.CFrame = camera.CFrame:Lerp(
            desiredCFrame,
            alpha
        )

        -- Evita disputar a rotacao com o Roll.
        if activeCharacter:GetAttribute("IsRolling") then
            return
        end

        local desiredRootCFrame = CFrame.lookAt(
            playerPos,
            playerPos + lastDirection
        )

        root.CFrame = root.CFrame:Lerp(
            desiredRootCFrame,
            rotationAlpha
        )
    end
)

print("[CombatCamera] Sistema carregado")
