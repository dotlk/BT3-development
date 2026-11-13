
-- CombatController.client.luau
-- Sistema de combo com quatro ataques encadeados
-- Impacto por progresso da animacao
-- Hitstop com confirmacao do servidor

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

local FIRST_ATTACK = "Punch1"

local DEFAULT_ATTACK_DURATION = 0.4
local MIN_ATTACK_DURATION = 0.15
local RECOVERY_DURATION = 0.2

local COMBO_WINDOW_START = 0.25
local COMBO_TRANSITION = 0.75

-- Evita que uma resposta perdida bloqueie o combo
local HIT_CONFIRM_TIMEOUT = 0.35

local fighter = StateMachine.new()

local humanoid = nil
local attackTracks = {}

local currentAttack = nil
local attackStartedAt = 0
local attackDuration = 0

local queuedAttack = nil
local attackSequence = 0

-- Controle do impacto
local hitRequested = false
local hitResolved = false
local hitRequestedAt = 0

-- Controle do Hitstop
local hitstopStartedAt = nil
local hitstopEndsAt = 0
local totalPausedTime = 0

-- Tempo do ataque sem contar as pausas
local function getAttackElapsed()
    local now = os.clock()
    local paused = totalPausedTime

    if hitstopStartedAt then
        paused += now - hitstopStartedAt
    end

    return math.max(
        0,
        now - attackStartedAt - paused
    )
end

local function clearHitstop()
    hitstopStartedAt = nil
    hitstopEndsAt = 0
    totalPausedTime = 0
end

-- Prepara o personagem e suas animacoes
local function setupCharacter(character)
    attackSequence += 1

    fighter:ForceState("Idle")

    currentAttack = nil
    queuedAttack = nil
    attackStartedAt = 0
    attackDuration = 0

    hitRequested = false
    hitResolved = false
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

    print("[Combat] Animacoes carregadas")
end

-- Encerra o combo
local function finishCombo(sequence)
    if sequence ~= attackSequence then
        return
    end

    queuedAttack = nil
    currentAttack = nil

    hitRequested = false
    hitResolved = false

    clearHitstop()

    if fighter:GetState() == "Attack" then
        fighter:Transition("Recovery")
    end

    print("[Combat] Recovery iniciado")

    task.delay(RECOVERY_DURATION, function()
        if sequence ~= attackSequence then
            return
        end

        if fighter:GetState() == "Recovery" then
            fighter:Transition("Idle")
        end

        print("[Combat] Idle")
    end)
end

-- Inicia um golpe
local function startAttack(attackName)
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

    -- Interrompe o golpe anterior
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

    print("[Combat] Ataque:", attackName)
end

-- Recebe a resposta do servidor
hitstopEvent.OnClientEvent:Connect(function(
    attackName,
    duration,
    hitConfirmed
)
    if typeof(attackName) ~= "string"
        or typeof(duration) ~= "number"
        or typeof(hitConfirmed) ~= "boolean" then
        return
    end

    if fighter:GetState() ~= "Attack" then
        return
    end

    if currentAttack ~= attackName then
        return
    end

    if not hitRequested or hitResolved then
        return
    end

    local track = attackTracks[attackName]
    local data = AnimationData.Combat[attackName]

    if not track or not data then
        return
    end

    -- O servidor respondeu: nao precisamos mais
    -- aguardar confirmacao deste golpe
    hitResolved = true

    if not hitConfirmed then
        print("[Combat] Golpe nao confirmado:", attackName)
        return
    end

    -- Sem Hitstop, apenas confirma o impacto
    if duration <= 0 then
        return
    end

    -- Limite de seguranca
    if duration > 2 then
        return
    end

    if not track.IsPlaying then
        return
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
end)

-- Atualiza impacto, Hitstop e transicoes
RunService.Heartbeat:Connect(function()
    if not currentAttack then
        return
    end

    if fighter:GetState() ~= "Attack" then
        return
    end

    local attackName = currentAttack
    local data = AnimationData.Combat[attackName]

    if not data or attackDuration <= 0 then
        return
    end

    -- Durante o Hitstop, nao avanca o combo
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

    -- Solicita o impacto uma unica vez
    local hitAt = math.clamp(data.HitAt or 0.90, 0, 1)

    if not hitRequested and progress >= hitAt then
        hitRequested = true
        hitRequestedAt = os.clock()

        if humanoid and humanoid.Health > 0 then
            attackEvent:FireServer(attackName)

            print(
                "[Combat] Impacto solicitado:",
                attackName,
                "| Progresso:",
                progress
            )
        else
            hitResolved = true
        end
    end

    -- Aguarda resposta positiva ou negativa
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

    -- Nenhum golpe pode ser cancelado
    -- antes de solicitar seu impacto
    if not hitRequested or not hitResolved then
        return
    end

    -- Transicao apos impacto e Hitstop
    local transitionPoint = data.Transition or COMBO_TRANSITION
    local transitionTime = attackDuration * transitionPoint

    if queuedAttack and elapsed >= transitionTime then
        local nextAttack = queuedAttack
        startAttack(nextAttack)
        return
    end

    -- Finaliza ao atingir a duracao do ataque
    if elapsed >= attackDuration then
        if queuedAttack then
            local nextAttack = queuedAttack
            startAttack(nextAttack)
        else
            finishCombo(attackSequence)
        end
    end
end)

-- Processa o clique do jogador
local function performAttack()
    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local state = fighter:GetState()

    if state == "Idle" then
        startAttack(FIRST_ATTACK)
        return
    end

    if state ~= "Attack" then
        return
    end

    if not currentAttack then
        return
    end

    local data = AnimationData.Combat[currentAttack]

    if not data or not data.Next then
        return
    end

    if queuedAttack then
        return
    end

    local elapsed = getAttackElapsed()
    local progress = elapsed / attackDuration

    if progress >= COMBO_WINDOW_START and progress <= 1 then
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

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end
