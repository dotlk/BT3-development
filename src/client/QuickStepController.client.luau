
-- QuickStepController.client.luau
-- Shift + WASD: Quick Dash
-- Duplo toque A/D: Quick Roll
-- Com Lock-On: movimento orbital
-- Sem Lock-On: movimento direcional

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local AnimationData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationData")
)

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local STEP_DISTANCE = 5
local STEP_DURATION = 0.15
local STEP_COOLDOWN = 0.25

local ROLL_DISTANCE = 14
local ROLL_COOLDOWN = 0.35
local ROLL_FALLBACK_DURATION = 0.65

local DOUBLE_TAP_WINDOW = 0.30

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

local lastStep = -math.huge
local lastRoll = -math.huge

local lastTap = {
    [Enum.KeyCode.A] = -math.huge,
    [Enum.KeyCode.D] = -math.huge,
}

local released = {
    [Enum.KeyCode.A] = true,
    [Enum.KeyCode.D] = true,
}

local movementConnection = nil
local actionId = 0

local savedWalkSpeed = nil
local savedAutoRotate = nil

-- ==========================================
-- UTILITARIOS
-- ==========================================

local function flatten(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function movementCurve(t)
    -- Ease-out: inicio rapido, final suave.
    return 1 - (1 - t) ^ 2
end

local function shiftHeld()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function resetDoubleTap()
    lastTap[Enum.KeyCode.A] = -math.huge
    lastTap[Enum.KeyCode.D] = -math.huge
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
    if stepping then
        print("[QuickStep] Movimento bloqueado: outro ativo")
        return
    end

    if not humanoid or not root then
        return
    end

    if humanoid.Health <= 0 then
        return
    end

    local direction, selectedKey = getDirection(preferredKey)

    if not direction then
        return
    end

    if isRoll
        and selectedKey ~= Enum.KeyCode.A
        and selectedKey ~= Enum.KeyCode.D then
        return
    end

    local now = os.clock()

    if isRoll then
        if now - lastRoll < ROLL_COOLDOWN then
            print("[Roll] Cooldown ativo")
            return
        end
    else
        if now - lastStep < STEP_COOLDOWN then
            return
        end
    end

    local animationName

    if isRoll then
        animationName = ROLL_ANIMATIONS[selectedKey]
    else
        animationName = DASH_ANIMATIONS[selectedKey]
    end

    if not animationName then
        return
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

    -- Apenas movimentos laterais orbitam.
    local isLateral =
        selectedKey == Enum.KeyCode.A
        or selectedKey == Enum.KeyCode.D

    local targetRoot = isLateral and getLockOnTarget() or nil

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
        "| Distancia:", distance
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
                    currentRoot.CFrame += displacement
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
end

-- ==========================================
-- INPUT
-- ==========================================

UserInputService.InputBegan:Connect(function(input, processed)
    local key = input.KeyCode

    -- A/D sao detectados mesmo com processed = true.
    -- Isso e necessario porque o Roblox ja usa
    -- essas teclas para movimentacao padrao.
    if key == Enum.KeyCode.A or key == Enum.KeyCode.D then
        if not released[key] then
            return
        end

        released[key] = false

        -- Impede ativacao enquanto digita no chat.
        if UserInputService:GetFocusedTextBox() then
            lastTap[key] = -math.huge
            return
        end

        -- Shift + A/D nao conta como Roll.
        if shiftHeld() then
            lastTap[key] = -math.huge
            return
        end

        local now = os.clock()
        local interval = now - lastTap[key]

        print("[DoubleTap]", key.Name, "Intervalo:", interval)

        if interval <= DOUBLE_TAP_WINDOW then
            lastTap[key] = -math.huge

            print("[DoubleTap] ROLL DETECTADO:", key.Name)

            executeMovement(true, key)
        else
            lastTap[key] = now
        end

        return
    end

    -- Outros inputs continuam respeitando processed.
    if processed then
        return
    end

    -- Shift + WASD = Dash.
    if key == Enum.KeyCode.LeftShift
        or key == Enum.KeyCode.RightShift then

        resetDoubleTap()
        executeMovement(false)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode

    if released[key] ~= nil then
        released[key] = true
    end
end)

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    cancelMovement()

    for _, track in pairs(animationTracks) do
        track:Stop(0)
        track:Destroy()
    end

    animationTracks = {}

    activeCharacter = character
    lastStep = -math.huge
    lastRoll = -math.huge

    resetDoubleTap()

    released[Enum.KeyCode.A] = true
    released[Enum.KeyCode.D] = true

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
