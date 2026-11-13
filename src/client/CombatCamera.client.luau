
-- CombatCamera.client.luau
-- V alterna Lock-On, inicialmente desligado.
-- Alvo deve estar na frente da camera e a no maximo 40 studs.
-- Em primeira pessoa, PlayerCamera controla camera e postura.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local LOCK_ON_KEY = Enum.KeyCode.V
local MAX_TARGET_DISTANCE = 40
local MAX_TARGET_ANGLE = 55

local MIN_DISTANCE = 12
local MAX_CAMERA_DISTANCE = 30
local BASE_DISTANCE = 10
local DISTANCE_PER_STUD = 0.55

local HEIGHT = 5
local FOCUS_HEIGHT = 2.5

local SMOOTHNESS = 7
local ROTATION_SMOOTHNESS = 12

-- ==========================================
-- ESTADO
-- ==========================================

local activeCharacter
local humanoid
local root
local targetValue
local lockedTarget

local lockOnEnabled = false
local currentDistance = MIN_DISTANCE
local lastDirection = Vector3.new(0, 0, -1)

-- ==========================================
-- ALVOS
-- ==========================================

local function getTargetRoot(model)
    local targetHumanoid =
        model:FindFirstChildOfClass("Humanoid")

    local targetRoot =
        model:FindFirstChild("HumanoidRootPart")

    if not targetHumanoid
        or targetHumanoid.Health <= 0
        or not targetRoot
        or not targetRoot:IsA("BasePart") then

        return nil
    end

    return targetRoot
end

local function isValidTarget(targetRoot)
    if not root
        or not root.Parent
        or not targetRoot
        or not targetRoot.Parent then

        return false
    end

    local model =
        targetRoot:FindFirstAncestorOfClass("Model")

    if not model or model == activeCharacter then
        return false
    end

    if getTargetRoot(model) ~= targetRoot then
        return false
    end

    return (
        targetRoot.Position - root.Position
    ).Magnitude <= MAX_TARGET_DISTANCE
end

local function findTarget()
    local camera = Workspace.CurrentCamera

    if not camera or not root then
        return nil
    end

    local cameraForward = camera.CFrame.LookVector

    local bestTarget = nil
    local bestScore = math.huge

    local maxAngle = math.rad(MAX_TARGET_ANGLE)

    for _, model in ipairs(Workspace:GetDescendants()) do
        if model:IsA("Model")
            and model ~= activeCharacter then

            local targetRoot = getTargetRoot(model)

            if targetRoot and isValidTarget(targetRoot) then
                local offset =
                    targetRoot.Position - camera.CFrame.Position

                if offset.Magnitude > 0.01 then
                    local angle = math.acos(
                        math.clamp(
                            cameraForward:Dot(offset.Unit),
                            -1,
                            1
                        )
                    )

                    if angle <= maxAngle then
                        local distance = (
                            targetRoot.Position - root.Position
                        ).Magnitude

                        local score =
                            angle * 100 + distance * 0.02

                        if score < bestScore then
                            bestScore = score
                            bestTarget = targetRoot
                        end
                    end
                end
            end
        end
    end

    return bestTarget
end

-- ==========================================
-- LOCK-ON
-- ==========================================

local function isFirstPerson()
    return activeCharacter ~= nil
        and activeCharacter:GetAttribute("IsFirstPerson") == true
end

local function disableLockOn()
    lockOnEnabled = false
    lockedTarget = nil

    if targetValue and targetValue.Parent then
        targetValue.Value = nil
    end

    local camera = Workspace.CurrentCamera

    if camera and not isFirstPerson() then
        camera.CameraType = Enum.CameraType.Custom

        if humanoid and humanoid.Parent then
            camera.CameraSubject = humanoid
        end
    end

    if humanoid
        and humanoid.Parent
        and not (
            activeCharacter
            and activeCharacter:GetAttribute("IsRolling")
        ) then

        -- Primeira pessoa exige rotacao manual pelo PlayerCamera.
        humanoid.AutoRotate = not isFirstPerson()
    end
end

local function enableLockOn(target)
    if not isValidTarget(target) then
        return
    end

    lockedTarget = target
    lockOnEnabled = true

    if targetValue then
        targetValue.Value = target
    end

    currentDistance = MIN_DISTANCE

    if humanoid then
        humanoid.AutoRotate = false
    end
end

-- ==========================================
-- INPUT
-- ==========================================

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= LOCK_ON_KEY then
        return
    end

    if lockOnEnabled then
        disableLockOn()
    else
        local target = findTarget()

        if target then
            enableLockOn(target)
        end
    end
end)

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    disableLockOn()

    activeCharacter = character

    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")

    targetValue = character:FindFirstChild("LockOnTarget")

    if not targetValue then
        targetValue = Instance.new("ObjectValue")
        targetValue.Name = "LockOnTarget"
        targetValue.Parent = character
    end

    targetValue.Value = nil

    humanoid.AutoRotate = true
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

-- ==========================================
-- CAMERA DE COMBATE
-- ==========================================

RunService:BindToRenderStep(
    "CombatCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        if not lockOnEnabled then
            return
        end

        local camera = Workspace.CurrentCamera

        if not camera
            or not root
            or not root.Parent
            or not humanoid
            or humanoid.Health <= 0 then

            disableLockOn()
            return
        end

        -- Desliga ao ultrapassar 40 studs.
        if not isValidTarget(lockedTarget) then
            disableLockOn()
            return
        end

        if targetValue
            and targetValue.Value ~= lockedTarget then

            targetValue.Value = lockedTarget
        end

        -- Em primeira pessoa, PlayerCamera tambem usa Scriptable.
        camera.CameraType = Enum.CameraType.Scriptable

        if not activeCharacter:GetAttribute("IsRolling") then
            humanoid.AutoRotate = false
        end

        local playerPos = root.Position
        local targetPos = lockedTarget.Position

        local flatOffset = Vector3.new(
            targetPos.X - playerPos.X,
            0,
            targetPos.Z - playerPos.Z
        )

        local separation = flatOffset.Magnitude

        if separation > 0.05 then
            lastDirection = flatOffset.Unit
        end

        local desiredDistance = math.clamp(
            BASE_DISTANCE + separation * DISTANCE_PER_STUD,
            MIN_DISTANCE,
            MAX_CAMERA_DISTANCE
        )

        local alpha =
            1 - math.exp(-SMOOTHNESS * dt)

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

        -- PlayerCamera assume a camera em primeira pessoa.
        if not isFirstPerson() then
            local desiredCFrame = CFrame.lookAt(
                cameraPos,
                focusPos
            )

            camera.CFrame = camera.CFrame:Lerp(
                desiredCFrame,
                alpha
            )
        end

        -- Nao disputar a rotacao com Roll ou PlayerCamera.
        if activeCharacter:GetAttribute("IsRolling")
            or isFirstPerson() then

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
