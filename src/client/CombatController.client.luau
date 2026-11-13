
-- CombatController.client.luau
-- Combo de quatro golpes, confirmacao de impacto e Hitstop
-- Integracao com Roll por meio do atributo IsRolling

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local attackEvent = ReplicatedStorage:WaitForChild("CombatAttack")
local hitstopEvent = ReplicatedStorage:WaitForChild("CombatHitstop")

local StateMachine = require(shared:WaitForChild("StateMachine"))
local AnimationData = require(shared:WaitForChild("AnimationData"))

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local FIRST_ATTACK = "Punch1"
local DEFAULT_ATTACK_DURATION = 0.4
local MIN_ATTACK_DURATION = 0.15
local RECOVERY_NORMAL = 0.15
local RECOVERY_FINISHER = 0.60
local COMBO_WINDOW_START = 0.25
local COMBO_TRANSITION = 0.75
local HIT_CONFIRM_TIMEOUT = 0.60
local END_POSE_MARGIN = 0.02

-- ==========================================
-- ESTADO
-- ==========================================

local fighter = StateMachine.new()

local humanoid = nil
local attackTracks = {}

local currentAttack = nil
local attackStartedAt = 0
local attackDuration = 0
local queuedAttack = nil
local attackSequence = 0

local hitRequested = false
local hitResponse = nil
local hitResolved = false
local hitRequestedAt = 0

local hitstopStartedAt = nil
local hitstopEndsAt = 0
local totalPausedTime = 0

-- ==========================================
-- INTEGRACAO COM MOVIMENTACAO
-- ==========================================

local function isRolling()
    local character = player.Character

    return character ~= nil
        and character:GetAttribute("IsRolling") == true
end

-- ==========================================
-- TEMPO DO ATAQUE
-- ==========================================

local function getAttackElapsed()
    local paused = totalPausedTime

    if hitstopStartedAt then
        paused += os.clock() - hitstopStartedAt
    end

    return math.max(
        0,
        os.clock() - attackStartedAt - paused
    )
end

local function clearHitstop()
    hitstopStartedAt = nil
    hitstopEndsAt = 0
    totalPausedTime = 0
end

local function printAnimationDurations(tracks, character)
    local names = {
        "Punch1",
        "Punch2",
        "Punch3",
        "Finisher4",
    }

    local deadline = os.clock() + 10

    while os.clock() < deadline do
        if player.Character ~= character then
            return
        end

        local ready = true

        for _, name in ipairs(names) do
            if not tracks[name] or tracks[name].Length <= 0 then
                ready = false
                break
            end
        end

        if ready then
            break
        end

        task.wait(0.1)
    end

    if player.Character ~= character then
        return
    end

    print("========== ANIMATION DURATIONS ==========")

    for _, name in ipairs(names) do
        local track = tracks[name]
        local data = AnimationData.Combat[name]

        if track and data then
            local speed = data.Speed or 1

            print(
                "[AnimationDuration]",
                name,
                "| Length:",
                track.Length,
                "| Effective:",
                speed > 0 and track.Length / speed or 0
            )
        end
    end

    print("=========================================")
end

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    attackSequence += 1

    fighter:ForceState("Idle")

    currentAttack = nil
    queuedAttack = nil
    attackStartedAt = 0
    attackDuration = 0

    hitRequested = false
    hitResolved = false
    hitResponse = nil
    hitRequestedAt = 0

    clearHitstop()

    for _, track in pairs(attackTracks) do
        track:Stop(0)
        track:Destroy()
    end

    attackTracks = {}

    humanoid = character:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    for name, data in pairs(AnimationData.Combat) do
        local animation = Instance.new("Animation")
        animation.AnimationId = data.Id

        local track = animator:LoadAnimation(animation)

        track.Priority = data.Priority
        track.Looped = data.Looped

        attackTracks[name] = track

        animation:Destroy()
    end

    local loadedTracks = attackTracks

    task.spawn(function()
        printAnimationDurations(loadedTracks, character)
    end)

    print("[Combat] Animacoes carregadas")
end

-- ==========================================
-- FINALIZACAO DO COMBO
-- ==========================================

local function finishCombo(sequence)
    if sequence ~= attackSequence then
        return
    end

    local lastAttack = currentAttack

    queuedAttack = nil
    currentAttack = nil

    hitRequested = false
    hitResolved = false
    hitResponse = nil

    clearHitstop()

    local recoveryDuration = RECOVERY_NORMAL
    if lastAttack == "Finisher4" then
        recoveryDuration = RECOVERY_FINISHER
    end

    if fighter:GetState() == "Attack" then
        fighter:Transition("Recovery")
    end

    print("[Combat] Recovery iniciado:", recoveryDuration)

    task.delay(recoveryDuration, function()
        if sequence ~= attackSequence then
            return
        end

        if fighter:GetState() == "Recovery" then
            fighter:Transition("Idle")
        end

        print("[Combat] Idle")
    end)
end

-- ==========================================
-- RESULTADO DO IMPACTO
-- ==========================================

local function applyHitResult(attackName, duration, confirmed)
    if hitResolved or currentAttack ~= attackName then
        return
    end

    hitResolved = true

    if not confirmed then
        print("[Combat] Golpe nao confirmado:", attackName)
        return
    end

    if duration <= 0 or duration > 2 then
        return
    end

    local track = attackTracks[attackName]

    if not track then
        return
    end

    if not track.IsPlaying then
        track:Play(0, 1, 0)

        if track.Length > 0 then
            track.TimePosition = math.max(
                0,
                track.Length - END_POSE_MARGIN
            )
        end
    end

    local now = os.clock()

    hitstopStartedAt = now
    hitstopEndsAt = now + duration

    track:AdjustSpeed(0)

    print(
        "[Hitstop] INICIO:",
        attackName,
        "| Duracao:",
        duration
    )
end

-- ==========================================
-- INICIO DO ATAQUE
-- ==========================================

local function startAttack(attackName)
    -- Nao permite iniciar novos golpes durante o Roll.
    if isRolling() then
        return
    end

    local data = AnimationData.Combat[attackName]
    local track = attackTracks[attackName]

    if not data or not track then
        return
    end

    local state = fighter:GetState()

    if state == "Idle" then
        if not fighter:Transition("Attack") then
            return
        end
    elseif state ~= "Attack" then
        return
    end

    attackSequence += 1

    if currentAttack then
        local previousTrack = attackTracks[currentAttack]

        if previousTrack then
            previousTrack:Stop(0.08)
        end
    end

    currentAttack = attackName
    queuedAttack = nil

    attackStartedAt = os.clock()

    hitRequested = false
    hitResolved = false
    hitResponse = nil
    hitRequestedAt = 0

    clearHitstop()

    track:Stop(0)
    track:Play(0.08)
    track:AdjustSpeed(data.Speed or 1)

    local duration = data.Duration or track.Length

    if duration <= 0 then
        duration = DEFAULT_ATTACK_DURATION
    end

    attackDuration = math.max(
        duration / (data.Speed or 1),
        MIN_ATTACK_DURATION
    )

    -- Registra o inicio do ataque no servidor.
    if humanoid and humanoid.Health > 0 then
        attackEvent:FireServer(
            attackName,
            attackSequence,
            attackDuration
        )
    end

    print(
        "[Combat] Ataque:",
        attackName,
        "#",
        attackSequence
    )
end

-- ==========================================
-- CONFIRMACAO DO SERVIDOR
-- ==========================================

hitstopEvent.OnClientEvent:Connect(function(
    attackName,
    duration,
    confirmed,
    attackId
)
    if typeof(attackName) ~= "string"
        or typeof(duration) ~= "number"
        or typeof(confirmed) ~= "boolean"
        or typeof(attackId) ~= "number" then

        return
    end

    if fighter:GetState() ~= "Attack"
        or currentAttack ~= attackName then

        return
    end

    if attackId ~= attackSequence or hitResolved then
        return
    end

    if not hitRequested then
        hitResponse = {
            Duration = duration,
            Confirmed = confirmed,
        }

        return
    end

    applyHitResult(
        attackName,
        duration,
        confirmed
    )
end)

-- ==========================================
-- ATUALIZACAO DO COMBATE
-- ==========================================

RunService.Heartbeat:Connect(function()
    if not currentAttack
        or fighter:GetState() ~= "Attack" then

        return
    end

    local attackName = currentAttack
    local data = AnimationData.Combat[attackName]

    if not data or attackDuration <= 0 then
        return
    end

    -- HITSTOP
    if hitstopStartedAt then
        local now = os.clock()

        if now < hitstopEndsAt then
            return
        end

        totalPausedTime += now - hitstopStartedAt

        hitstopStartedAt = nil
        hitstopEndsAt = 0

        local track = attackTracks[attackName]

        if track and track.IsPlaying then
            track:AdjustSpeed(data.Speed or 1)
        end

        print("[Hitstop] FIM:", attackName)
    end

    local elapsed = getAttackElapsed()
    local progress = elapsed / attackDuration

    local hitAt = math.clamp(
        data.HitAt or 0.90,
        0,
        1
    )

    -- PONTO DE IMPACTO
    if not hitRequested and progress >= hitAt then
        hitRequested = true
        hitRequestedAt = os.clock()

        print(
            "[Combat] Ponto de impacto:",
            attackName,
            "| Progresso:",
            progress
        )

        if hitResponse then
            local response = hitResponse
            hitResponse = nil

            applyHitResult(
                attackName,
                response.Duration,
                response.Confirmed
            )
        end
    end

    -- AGUARDA CONFIRMACAO
    if hitRequested and not hitResolved then
        if os.clock() - hitRequestedAt >= HIT_CONFIRM_TIMEOUT then
            hitResolved = true

            print(
                "[Combat] Timeout de confirmacao:",
                attackName
            )
        else
            return
        end
    end

    if not hitRequested
        or not hitResolved
        or hitstopStartedAt then

        return
    end

    -- TRANSICAO DO COMBO
    local transitionPoint =
        data.Transition or COMBO_TRANSITION

    local transitionTime = attackDuration * math.max(
        transitionPoint,
        hitAt
    )

    if queuedAttack and elapsed >= transitionTime then
        if not isRolling() then
            startAttack(queuedAttack)
        else
            queuedAttack = nil
        end

        return
    end

    -- FIM DO ATAQUE
    if elapsed >= attackDuration then
        if queuedAttack and not isRolling() then
            startAttack(queuedAttack)
        else
            finishCombo(attackSequence)
        end
    end
end)

-- ==========================================
-- INPUT DE ATAQUE
-- ==========================================

local function performAttack()
    -- Bloqueia ataques enquanto estiver rolando.
    if isRolling() then
        return
    end

    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local state = fighter:GetState()

    if state == "Idle" then
        startAttack(FIRST_ATTACK)
        return
    end

    if state ~= "Attack" or not currentAttack then
        return
    end

    local data = AnimationData.Combat[currentAttack]

    if not data or not data.Next or queuedAttack then
        return
    end

    local progress = getAttackElapsed() / attackDuration

    if progress >= COMBO_WINDOW_START
        and progress <= 1 then

        queuedAttack = data.Next

        print(
            "[Combat] Proximo golpe preparado:",
            queuedAttack
        )
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        performAttack()
    end
end)

-- ==========================================
-- INICIALIZACAO
-- ==========================================

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

print("[Combat] Sistema carregado")
