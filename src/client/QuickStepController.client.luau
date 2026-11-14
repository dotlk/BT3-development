
-- QuickStepController.client.luau
-- Shift rapido + WASD: Quick Dash
-- Shift mantido + A/D: Quick Roll
-- Com Lock-On: movimento orbital
-- Sem Lock-On: movimento direcional
--
-- Stamina controlada pelo servidor.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local AnimationData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationData")
)

local staminaRequest = ReplicatedStorage:WaitForChild("StaminaRequest")

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local STEP_DISTANCE = 5
local SPRINT_DISTANCE_MULTIPLIER = 2
local STEP_DURATION = 0.15
local STEP_COOLDOWN = 0.25

local ROLL_DISTANCE = 14
local ROLL_COOLDOWN = 0.35
local ROLL_FALLBACK_DURATION = 0.65

local ROLL_HOLD_DURATION = 0.25

local ANIMATION_FADE = 0.04
local COLLISION_MARGIN = 1.5

local LOCK_ON_VALUE_NAME = "LockOnTarget"

local DIRECTIONS = {
    [Enum.KeyCode.W] = Vector3.new(0, 0, -1),
    [Enum.KeyCode.S] = Vector3.new(0, 0, 1),
    [Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
    [Enum.KeyCode.D] = Vector3.new(1, 0, 0),
}

local DASH_ANIMATIONS = {
    [Enum.KeyCode.W] = "QuickDashForward",
    [Enum.KeyCode.S] = "QuickDashBackward",
    [Enum.KeyCode.A] = "QuickDashLeft",
    [Enum.KeyCode.D] = "QuickDashRight",
}

local ROLL_ANIMATIONS = {
    [Enum.KeyCode.A] = "QuickRollLeft",
    [Enum.KeyCode.D] = "QuickRollRight",
}

local KEY_ORDER = {
    Enum.KeyCode.W,
    Enum.KeyCode.S,
    Enum.KeyCode.A,
    Enum.KeyCode.D,
}

-- ==========================================
-- ESTADO
-- ==========================================

local humanoid = nil
local root = nil
local activeCharacter = nil

local animationTracks = {}
local activeTrack = nil

local stepping = false
local rolling = false
local requestingMovement = false

local lastStep = -math.huge
local lastRoll = -math.huge

local movementConnection = nil
local actionId = 0

local savedWalkSpeed = nil
local savedAutoRotate = nil

local shiftPressedAt = nil
local shiftActionId = 0
local shiftRollTriggered = false
local shiftPreferredKey = nil

-- ==========================================
-- STAMINA
-- ==========================================

-- Apenas leitura. O servidor controla o saldo real.
local stamina = player:GetAttribute("QuickStepStamina") or 0

player:GetAttributeChangedSignal(
    "QuickStepStamina"
):Connect(function()
    stamina = player:GetAttribute("QuickStepStamina") or 0
end)

local function requestStamina(action)
    local success, approved = pcall(function()
        return staminaRequest:InvokeServer(action)
    end)

    if not success then
        warn("[Stamina] Falha ao consultar servidor")
        return false
    end

    if approved ~= true then
        print("[Stamina] Movimento recusado:", action)
        return false
    end

    return true
end

-- ==========================================
-- UTILITARIOS
-- ==========================================

local function flatten(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function movementCurve(t)
    return 1 - (1 - t) ^ 2
end

local function shiftHeld()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function isShiftKey(key)
    return key == Enum.KeyCode.LeftShift
        or key == Enum.KeyCode.RightShift
end

local function getHeldDirectionKey()
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        return Enum.KeyCode.A
    end

    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        return Enum.KeyCode.D
    end

    for _, key in ipairs(KEY_ORDER) do
        if UserInputService:IsKeyDown(key) then
            return key
        end
    end

    return Enum.KeyCode.W
end

local function getTargetRoot(target)
    if not target or not target.Parent then
        return nil
    end

    if target:IsA("BasePart") then
        return target
    end

    if target:IsA("Model") then
        return target:FindFirstChild("HumanoidRootPart")
            or target.PrimaryPart
    end

    return nil
end

local function getLockOnTarget()
    if not activeCharacter then
        return nil
    end

    local value = activeCharacter:FindFirstChild(
        LOCK_ON_VALUE_NAME
    )

    if not value or not value:IsA("ObjectValue") then
        return nil
    end

    local targetRoot = getTargetRoot(value.Value)

    if not targetRoot then
        return nil
    end

    if targetRoot:IsDescendantOf(activeCharacter) then
        return nil
    end

    return targetRoot
end

-- ==========================================
-- ANIMACOES
-- ==========================================

local function stopAnimation()
    if activeTrack then
        activeTrack:Stop(ANIMATION_FADE)
        activeTrack = nil
    end
end

local function playAnimation(animationName)
    stopAnimation()

    local data = AnimationData.Movement[animationName]
    local track = animationTracks[animationName]

    if not data or not track then
        warn("[QuickStep] Animacao ausente:", animationName)
        return nil
    end

    activeTrack = track

    track:Play(ANIMATION_FADE)
    track:AdjustSpeed(data.Speed or 1)

    track.Ended:Once(function()
        if activeTrack == track then
            activeTrack = nil
        end
    end)

    return track
end

-- ==========================================
-- CONTROLE DO HUMANOID
-- ==========================================

local function lockMovement()
    if not humanoid or not humanoid.Parent then
        return
    end

    if savedWalkSpeed == nil then
        savedWalkSpeed = humanoid.WalkSpeed
        savedAutoRotate = humanoid.AutoRotate
    end

    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
end

local function unlockMovement()
    if humanoid and humanoid.Parent then
        if savedWalkSpeed ~= nil then
            humanoid.WalkSpeed = savedWalkSpeed
        end

        if savedAutoRotate ~= nil then
            humanoid.AutoRotate = savedAutoRotate
        end
    end

    savedWalkSpeed = nil
    savedAutoRotate = nil
end

-- ==========================================
-- ESTADO DO ROLL
-- ==========================================

local function setRolling(value)
    rolling = value

    if activeCharacter and activeCharacter.Parent then
        activeCharacter:SetAttribute("IsRolling", value)
    end
end

local function finishMovement()
    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end

    stepping = false

    if rolling then
        unlockMovement()
    end

    setRolling(false)
end

local function cancelMovement()
    actionId += 1
    requestingMovement = false
    finishMovement()
    stopAnimation()
end

-- ==========================================
-- DIRECAO
-- ==========================================

local function getDirection(preferredKey)
    if not root then
        return nil, nil
    end

    local input = Vector3.zero
    local selectedKey = preferredKey

    if preferredKey then
        input = DIRECTIONS[preferredKey]
    else
        for _, key in ipairs(KEY_ORDER) do
            if UserInputService:IsKeyDown(key) then
                input += DIRECTIONS[key]
                selectedKey = key
            end
        end
    end

    if input.Magnitude < 0.01 then
        input = DIRECTIONS[Enum.KeyCode.W]
        selectedKey = Enum.KeyCode.W
    end

    local worldDirection =
        root.CFrame.RightVector * input.X
        - root.CFrame.LookVector * input.Z

    worldDirection = flatten(worldDirection)

    if worldDirection.Magnitude < 0.01 then
        return nil, nil
    end

    return worldDirection.Unit, selectedKey
end

-- ==========================================
-- POSTURA DO DASH LATERAL
-- ==========================================

local function getLateralFacing(targetRoot)
    if not root then
        return nil
    end

    local facing

    if targetRoot and targetRoot.Parent then
        facing = flatten(targetRoot.Position - root.Position)
    else
        local camera = workspace.CurrentCamera
        facing = camera and flatten(camera.CFrame.LookVector)
            or flatten(root.CFrame.LookVector)
    end

    if facing.Magnitude < 0.01 then
        return nil
    end

    return facing.Unit
end

-- ==========================================
-- COLISAO
-- ==========================================

local function canMove(position, displacement, rayParams)
    if displacement.Magnitude < 0.0001 then
        return true
    end

    local hit = workspace:Raycast(
        position,
        displacement.Unit * (
            displacement.Magnitude + COLLISION_MARGIN
        ),
        rayParams
    )

    return hit == nil
end

-- ==========================================
-- ORBITA
-- ==========================================

local function calculateOrbitalPosition(center, offset, angle)
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)

    local x =
        offset.X * cosAngle
        - offset.Z * sinAngle

    local z =
        offset.X * sinAngle
        + offset.Z * cosAngle

    return center + Vector3.new(x, 0, z)
end

-- ==========================================
-- EXECUCAO DO MOVIMENTO
-- ==========================================

local function executeMovement(isRoll, preferredKey)
    if stepping or requestingMovement then
        print("[QuickStep] Movimento bloqueado: outro ativo")
        return false
    end

    if not humanoid or not root then
        return false
    end

    if humanoid.Health <= 0 then
        return false
    end

    local direction, selectedKey = getDirection(preferredKey)

    if not direction then
        return false
    end

    -- W/S: Lock-On > First Person > Normal View.
    if not isRoll and (
        selectedKey == Enum.KeyCode.W
        or selectedKey == Enum.KeyCode.S
    ) then
        local target = getLockOnTarget()
        local forward

        if target then
            forward = flatten(target.Position - root.Position)
        else
            forward = flatten(root.CFrame.LookVector)
        end

        if forward.Magnitude < 0.01 then
            return false
        end

        local camera = workspace.CurrentCamera
        local isFirstPerson = false

        if camera then
            local cameraDistance =
                (camera.CFrame.Position - root.Position).Magnitude

            isFirstPerson = cameraDistance < 2
        end

        if target or isFirstPerson then
            direction = selectedKey == Enum.KeyCode.S
                and -forward.Unit or forward.Unit
        else
            direction = forward.Unit
            selectedKey = Enum.KeyCode.W
        end
    end

    -- Corrige a postura do Dash lateral.
    local isLateral =
        selectedKey == Enum.KeyCode.A
        or selectedKey == Enum.KeyCode.D

    local lateralTarget = isLateral and getLockOnTarget() or nil
    local lateralFacing = isLateral and getLateralFacing(lateralTarget) or nil

    if isLateral and lateralFacing then
        local lateralRight = lateralFacing:Cross(Vector3.yAxis).Unit
        direction = selectedKey == Enum.KeyCode.D
            and lateralRight or -lateralRight
    end

    if isRoll
        and selectedKey ~= Enum.KeyCode.A
        and selectedKey ~= Enum.KeyCode.D then
        return false
    end

    local now = os.clock()

    -- Cooldown local para evitar requisicoes desnecessarias.
    -- O servidor tambem valida o cooldown real.
    if isRoll then
        if now - lastRoll < ROLL_COOLDOWN then
            print("[Roll] Cooldown ativo")
            return false
        end
    else
        if now - lastStep < STEP_COOLDOWN then
            return false
        end
    end

    local animationName

    if isRoll then
        animationName = ROLL_ANIMATIONS[selectedKey]
    else
        animationName = DASH_ANIMATIONS[selectedKey]
    end

    if not animationName then
        return false
    end

    -- ======================================
    -- AUTORIZACAO DO SERVIDOR
    -- ======================================

    local characterBeforeRequest = activeCharacter
    local requestActionId = actionId

    requestingMovement = true

    local action = isRoll and "Roll" or "Dash"
    local approved = requestStamina(action)

    -- InvokeServer pode suspender esta funcao.
    -- Confirma que o personagem nao mudou nesse intervalo.
    if characterBeforeRequest ~= activeCharacter
        or requestActionId ~= actionId then
        requestingMovement = false
        return false
    end

    requestingMovement = false

    if not approved then
        return false
    end

    if not humanoid
        or humanoid.Health <= 0
        or not root
        or stepping then
        return false
    end

    now = os.clock()

    -- ======================================
    -- MOVIMENTO AUTORIZADO
    -- ======================================

    if isLateral and lateralFacing then
        root.CFrame = CFrame.lookAt(
            root.Position,
            root.Position + lateralFacing
        )
    end

    stepping = true
    actionId += 1

    local thisAction = actionId

    if isRoll then
        lastRoll = now
    else
        lastStep = now
    end

    local character = activeCharacter
    local currentHumanoid = humanoid
    local currentRoot = root

    local track = playAnimation(animationName)

    local duration = STEP_DURATION
    local distance = STEP_DISTANCE

    local sprintBoost = character
        and character:GetAttribute("IsSprinting") == true
        and SPRINT_DISTANCE_MULTIPLIER or 1

    if isRoll then
        distance = ROLL_DISTANCE

        local data = AnimationData.Movement[animationName]
        local speed = math.max(data.Speed or 1, 0.01)

        if track and track.Length > 0 then
            duration = track.Length / speed
        else
            duration = ROLL_FALLBACK_DURATION
        end

        lockMovement()
        setRolling(true)
    else
        setRolling(false)
    end

    distance *= sprintBoost

    -- Apenas movimentos laterais orbitam.
    local targetRoot = lateralTarget

    local orbital = false
    local orbitOffset = nil
    local orbitAngle = 0

    if targetRoot then
        local offset = flatten(
            currentRoot.Position - targetRoot.Position
        )

        local radius = offset.Magnitude

        if radius >= 1 then
            orbital = true
            orbitOffset = offset

            local tangent = Vector3.new(
                -offset.Z,
                0,
                offset.X
            ).Unit

            local sign =
                tangent:Dot(direction) >= 0
                and 1
                or -1

            orbitAngle = sign * (distance / radius)
        end
    end

    local elapsed = 0
    local traveled = 0
    local blocked = false

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {character}
    rayParams.IgnoreWater = true

    print(
        isRoll and "[Roll] INICIO" or "[Dash] INICIO",
        "| Animacao:", animationName,
        "| Orbital:", orbital,
        "| Distancia:", distance,
        "| Stamina:", stamina
    )

    movementConnection = RunService.Heartbeat:Connect(function(dt)
        if thisAction ~= actionId then
            return
        end

        if not currentRoot.Parent
            or not currentHumanoid.Parent
            or currentHumanoid.Health <= 0 then
            cancelMovement()
            return
        end

        elapsed += dt

        local progress = math.clamp(
            elapsed / duration,
            0,
            1
        )

        local eased = movementCurve(progress)

        if not blocked then
            if orbital and targetRoot and targetRoot.Parent then
                local center = flatten(targetRoot.Position)

                local desiredPosition = calculateOrbitalPosition(
                    center,
                    orbitOffset,
                    orbitAngle * eased
                )

                local displacement =
                    desiredPosition - flatten(currentRoot.Position)

                if canMove(
                    currentRoot.Position,
                    displacement,
                    rayParams
                ) then
                    local newPosition = Vector3.new(
                        desiredPosition.X,
                        currentRoot.Position.Y,
                        desiredPosition.Z
                    )

                    local facing = flatten(
                        targetRoot.Position - newPosition
                    )

                    if facing.Magnitude > 0.01 then
                        currentRoot.CFrame = CFrame.lookAt(
                            newPosition,
                            newPosition + facing.Unit
                        )
                    else
                        currentRoot.CFrame = CFrame.new(newPosition)
                    end
                else
                    blocked = true
                end
            else
                -- Fallback linear sem Lock-On.
                local targetDistance = distance * eased
                local movement = targetDistance - traveled

                local displacement = direction * movement

                if canMove(
                    currentRoot.Position,
                    displacement,
                    rayParams
                ) then
                    local newPosition = currentRoot.Position + displacement

                    if isLateral then
                        local facing = getLateralFacing(
                            getLockOnTarget()
                        ) or lateralFacing

                        if facing then
                            currentRoot.CFrame = CFrame.lookAt(
                                newPosition,
                                newPosition + facing
                            )
                        else
                            currentRoot.CFrame += displacement
                        end
                    else
                        currentRoot.CFrame += displacement
                    end

                    traveled = targetDistance
                else
                    blocked = true
                end
            end
        end

        if progress >= 1 then
            finishMovement()

            print(
                isRoll and "[Roll] FIM" or "[Dash] FIM"
            )
        end
    end)

    return true
end

-- ==========================================
-- CONTROLE DO SHIFT
-- ==========================================

local function resetShiftAction()
    shiftActionId += 1
    shiftPressedAt = nil
    shiftRollTriggered = false
    shiftPreferredKey = nil
end

local function beginShiftAction()
    if shiftPressedAt ~= nil then
        return
    end

    if UserInputService:GetFocusedTextBox() then
        return
    end

    shiftPressedAt = os.clock()
    shiftRollTriggered = false
    shiftPreferredKey = getHeldDirectionKey()

    shiftActionId += 1
    local thisShiftAction = shiftActionId

    task.delay(ROLL_HOLD_DURATION, function()
        if thisShiftAction ~= shiftActionId then
            return
        end

        if shiftPressedAt == nil or not shiftHeld() then
            return
        end

        if UserInputService:GetFocusedTextBox() then
            return
        end

        local key = getHeldDirectionKey()

        if key ~= Enum.KeyCode.A
            and key ~= Enum.KeyCode.D then
            return
        end

        shiftRollTriggered = true

        executeMovement(true, key)
    end)
end

local function endShiftAction()
    if shiftPressedAt == nil then
        return
    end

    local heldDuration = os.clock() - shiftPressedAt
    local rollTriggered = shiftRollTriggered
    local preferredKey = shiftPreferredKey

    resetShiftAction()

    if UserInputService:GetFocusedTextBox() then
        return
    end

    if heldDuration < ROLL_HOLD_DURATION then
        executeMovement(false, preferredKey)
        return
    end

    if not rollTriggered then
        local key = preferredKey

        if key == Enum.KeyCode.W
            or key == Enum.KeyCode.S then
            executeMovement(false, key)
        end
    end
end

-- ==========================================
-- INPUT
-- ==========================================

UserInputService.InputBegan:Connect(function(input, processed)
    local key = input.KeyCode

    if isShiftKey(key) then
        if processed then
            return
        end

        beginShiftAction()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode

    if isShiftKey(key) then
        if shiftHeld() then
            return
        end

        endShiftAction()
    end
end)

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    resetShiftAction()
    cancelMovement()

    for _, track in pairs(animationTracks) do
        track:Stop(0)
        track:Destroy()
    end

    animationTracks = {}

    activeCharacter = character

    -- O servidor reinicia a Stamina.
    -- O cliente apenas acompanha o atributo replicado.
    stamina = player:GetAttribute("QuickStepStamina") or 0

    lastStep = -math.huge
    lastRoll = -math.huge

    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")

    character:SetAttribute("IsRolling", false)

    local animator = humanoid:WaitForChild("Animator")

    for name, data in pairs(AnimationData.Movement) do
        local animation = Instance.new("Animation")
        animation.AnimationId = data.Id

        local track = animator:LoadAnimation(animation)

        track.Priority =
            data.Priority or Enum.AnimationPriority.Action

        track.Looped = data.Looped or false

        animationTracks[name] = track
        animation:Destroy()
    end

    print("[QuickStep] Animacoes carregadas")
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

print("[QuickStep] Sistema carregado")
