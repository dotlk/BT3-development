
-- CombatController.client.luau
-- Combo normal + Heavy Melee + Guard
-- QuickStep cancela Guard

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local shared = RS:WaitForChild("Shared")

local StateMachine = require(shared:WaitForChild("Combat"):WaitForChild("StateMachine"))
local AnimationData = require(shared:WaitForChild("AnimationData"))

local attackEvent = RS:WaitForChild("CombatAttack")
local hitstopEvent = RS:WaitForChild("CombatHitstop")
local heavyEvent = RS:WaitForChild("CombatHeavyCharge")
local guardRequest = RS:WaitForChild("GuardRequest")

local FIRST_ATTACK = "Punch1"
local DEFAULT_DURATION = 0.4

local RECOVERY_NORMAL = 0.15
local RECOVERY_FINISHER = 0.60
local COMBO_WINDOW_START = 0.25
local COMBO_TRANSITION = 0.75
local HIT_TIMEOUT = 0.60

local HEAVY_END_FREEZE_AT = 0.90
local HEAVY_END_FREEZE_DURATION = 0.18

local heavyConfig = AnimationData.Heavy
local fighter = StateMachine.new()

-- ==========================================
-- ESTADO
-- ==========================================

local humanoid
local tracks = {}

local currentAttack
local queuedAttack
local attackStartedAt = 0
local attackDuration = 0
local attackSequence = 0

local hitRequested = false
local hitResolved = false
local hitResponse
local hitRequestedAt = 0

local hitstopStartedAt
local hitstopEndsAt = 0
local totalPausedTime = 0

local mouseHeld = false
local mousePressedAt = 0
local mouseToken = 0

local guardHeld = false
local guardFrozen = false
local guardStartedAt = 0
local guardDuration = 0

local heavyPhase
local heavyStartedAt = 0
local heavyCharge = 0
local heavyChargeId = 0

local heavyEndFreezeStartedAt
local heavyEndFreezeEndsAt = 0
local heavyEndFreezeDone = false
local totalHeavyEndPausedTime = 0

-- ==========================================
-- PERSONAGEM
-- ==========================================

local function character()
    return player.Character
end

local function isRolling()
    local c = character()
    return c and c:GetAttribute("IsRolling") == true
end

local function isQuickStepping()
    local c = character()
    return c and c:GetAttribute("IsQuickStepping") == true
end

local function isStunned()
    local c = character()
    return c and c:GetAttribute("CombatStunned") == true
end

local function canAct()
    return humanoid ~= nil
        and humanoid.Health > 0
        and not isRolling()
        and not isStunned()
end

local function setHeavyAttributes(active, charge)
    local c = character()
    if not c then return end

    c:SetAttribute("HeavyCharging", active)
    c:SetAttribute("HeavyCharge", charge)
end

local function setGuardAttribute(active)
    local c = character()
    if not c then
        return
    end

    -- O servidor controla o estado real da defesa.
    guardRequest:FireServer(active)
end

-- ==========================================
-- ANIMACOES
-- ==========================================

local function stopTrack(name, fade)
    local track = tracks[name]

    if track and track.IsPlaying then
        track:Stop(fade or 0.05)
    end
end

local function playTrack(name, fade)
    local track = tracks[name]
    if not track then return nil end

    local data = AnimationData.Combat[name]
        or AnimationData.HeavyAnimations[name]
        or AnimationData.Guard[name]

    if not data then return nil end

    track:Stop(0)
    track:Play(fade or 0.05)
    track:AdjustSpeed(data.Speed or 1)

    return track
end

-- ==========================================
-- GUARD
-- ==========================================

local function startGuard()
    if not guardHeld
        or not canAct()
        or isQuickStepping() then
        return
    end

    if fighter:GetState() ~= "Idle" then
        return
    end

    if not fighter:Transition("Block") then
        return
    end

    guardFrozen = false
    guardStartedAt = os.clock()
    guardDuration = 0

    setGuardAttribute(true)

    local track = playTrack("Block", 0.12)

    if track then
        track.Looped = false
    end

    print("[Guard] Ativado")
end

local function stopGuard()
    guardFrozen = false
    guardDuration = 0

    stopTrack("Block", 0.12)

    if fighter:GetState() == "Block" then
        fighter:Transition("Idle")
    end

    setGuardAttribute(false)
end

local function updateGuardAnimation()
    if fighter:GetState() ~= "Block" then
        return
    end

    local track = tracks.Block

    if not track or guardFrozen or track.Length <= 0 then
        return
    end

    local config = AnimationData.Guard.Block
    local speed = math.max(config.Speed or 1, 0.01)

    local freezeAt = math.clamp(
        config.FreezeAt or 0.95,
        0.05,
        0.98
    )

    local targetPosition = track.Length * freezeAt

    if guardDuration <= 0 then
        guardDuration = targetPosition / speed
    end

    if os.clock() - guardStartedAt >= guardDuration then
        if not track.IsPlaying then
            track:Play(0, 1, 0)
        end

        track.TimePosition = targetPosition
        track:AdjustSpeed(0)

        guardFrozen = true
        print("[Guard] Pose congelada")
    end
end

-- ==========================================
-- CONTROLE DE TEMPO
-- ==========================================

local function clearHitstop()
    hitstopStartedAt = nil
    hitstopEndsAt = 0
    totalPausedTime = 0
end

local function clearHeavyEndFreeze()
    heavyEndFreezeStartedAt = nil
    heavyEndFreezeEndsAt = 0
    heavyEndFreezeDone = false
    totalHeavyEndPausedTime = 0
end

local function getAttackElapsed()
    local now = os.clock()

    local paused =
        totalPausedTime + totalHeavyEndPausedTime

    if hitstopStartedAt then
        paused += now - hitstopStartedAt
    end

    if heavyEndFreezeStartedAt then
        paused += now - heavyEndFreezeStartedAt
    end

    return math.max(
        0,
        now - attackStartedAt - paused
    )
end

-- ==========================================
-- HEAVY MELEE
-- ==========================================

local function cancelHeavy(notifyServer)
    if heavyPhase then
        stopTrack("HeavyCharge")
        stopTrack("HeavyHold")

        if notifyServer then
            heavyEvent:FireServer(
                "Cancel",
                heavyChargeId
            )
        end
    end

    heavyPhase = nil
    heavyCharge = 0
    setHeavyAttributes(false, 0)

    if fighter:GetState() == "HeavyCharge" then
        fighter:ForceState("Idle")
    end
end

-- ==========================================
-- SETUP
-- ==========================================

local function setupCharacter(c)
    attackSequence += 1
    mouseToken += 1

    mouseHeld = false
    guardHeld = false
    guardFrozen = false
    guardDuration = 0

    cancelHeavy(false)
    fighter:ForceState("Idle")

    currentAttack = nil
    queuedAttack = nil

    hitRequested = false
    hitResolved = false
    hitResponse = nil

    clearHitstop()
    clearHeavyEndFreeze()

    for _, track in pairs(tracks) do
        track:Stop(0)
        track:Destroy()
    end

    tracks = {}

    humanoid = c:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    local function loadSet(set)
        for name, data in pairs(set) do
            local animation = Instance.new("Animation")
            animation.AnimationId = data.Id

            local track = animator:LoadAnimation(animation)

            track.Priority = data.Priority
            track.Looped = data.Looped

            tracks[name] = track
            animation:Destroy()
        end
    end

    loadSet(AnimationData.Combat)
    loadSet(AnimationData.HeavyAnimations)
    loadSet(AnimationData.Guard)

    setHeavyAttributes(false, 0)
    setGuardAttribute(false)

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

    currentAttack = nil
    queuedAttack = nil

    hitRequested = false
    hitResolved = false
    hitResponse = nil

    clearHitstop()
    clearHeavyEndFreeze()

    local recovery = lastAttack == "Finisher4"
        and RECOVERY_FINISHER
        or RECOVERY_NORMAL

    if fighter:GetState() == "Attack" then
        fighter:Transition("Recovery")
    end

    task.delay(recovery, function()
        if sequence ~= attackSequence then
            return
        end

        if fighter:GetState() == "Recovery" then
            fighter:Transition("Idle")
        end
    end)
end

-- ==========================================
-- HITSTOP
-- ==========================================

local function applyHitResult(name, duration, confirmed)
    if hitResolved or currentAttack ~= name then
        return
    end

    hitResolved = true

    if not confirmed or duration <= 0 or duration > 2 then
        return
    end

    local track = tracks[name]
    if not track then return end

    if not track.IsPlaying then
        track:Play(0, 1, 0)

        if track.Length > 0 then
            track.TimePosition = math.max(
                0,
                track.Length - 0.02
            )
        end
    end

    hitstopStartedAt = os.clock()
    hitstopEndsAt = hitstopStartedAt + duration

    track:AdjustSpeed(0)
    print("[Hitstop] INICIO:", name)
end

-- ==========================================
-- ATAQUE
-- ==========================================

local function startAttack(name, heavyId)
    if not canAct() then
        return false
    end

    local data = AnimationData.Combat[name]
    local track = tracks[name]

    if not data or not track then
        return false
    end

    local state = fighter:GetState()

    if state == "Idle" then
        if not fighter:Transition("Attack") then
            return false
        end
    elseif state ~= "Attack" then
        return false
    end

    attackSequence += 1

    if currentAttack then
        stopTrack(currentAttack, 0.08)
    end

    currentAttack = name
    queuedAttack = nil
    attackStartedAt = os.clock()

    hitRequested = false
    hitResolved = false
    hitResponse = nil
    hitRequestedAt = 0

    clearHitstop()
    clearHeavyEndFreeze()

    playTrack(name, 0.08)

    local duration = data.Duration or track.Length

    if duration <= 0 then
        duration = DEFAULT_DURATION
    end

    attackDuration = math.max(
        duration / math.max(data.Speed or 1, 0.01),
        0.15
    )

    attackEvent:FireServer(
        name,
        attackSequence,
        attackDuration,
        heavyId
    )

    print("[Combat] Ataque:", name)
    return true
end

-- ==========================================
-- PREPARACAO DO HEAVY
-- ==========================================

local function startHeavy()
    if not canAct() then return end

    if fighter:GetState() ~= "Idle" then
        return
    end

    fighter:ForceState("HeavyCharge")

    heavyChargeId += 1
    heavyStartedAt = os.clock()
    heavyCharge = 0
    heavyPhase = "Preparation"

    heavyEvent:FireServer("Start", heavyChargeId)
    setHeavyAttributes(true, 0)

    local chargeTrack = playTrack("HeavyCharge", 0.08)
    local thisId = heavyChargeId

    task.spawn(function()
        local deadline = os.clock() + 0.5

        while chargeTrack
            and chargeTrack.Length <= 0
            and os.clock() < deadline do
            task.wait(0.02)
        end

        if heavyChargeId ~= thisId
            or heavyPhase ~= "Preparation" then
            return
        end

        local duration = 0.25

        if chargeTrack and chargeTrack.Length > 0 then
            local speed =
                AnimationData.HeavyAnimations.HeavyCharge.Speed or 1

            duration =
                chargeTrack.Length / math.max(speed, 0.01)
        end

        task.wait(duration)

        if heavyChargeId ~= thisId
            or heavyPhase ~= "Preparation" then
            return
        end

        heavyPhase = "Holding"

        stopTrack("HeavyCharge", 0.04)
        playTrack("HeavyHold", 0.04)
    end)
end

-- ==========================================
-- LIBERACAO DO HEAVY
-- ==========================================

local function releaseHeavy()
    if not heavyPhase then
        return
    end

    local id = heavyChargeId

    stopTrack("HeavyCharge", 0.04)
    stopTrack("HeavyHold", 0.04)

    heavyPhase = nil
    setHeavyAttributes(false, 0)

    if not canAct() then
        heavyEvent:FireServer("Cancel", id)
        fighter:ForceState("Idle")
        return
    end

    fighter:ForceState("Idle")

    if not startAttack("HeavyPunch", id) then
        heavyEvent:FireServer("Cancel", id)
    end
end

-- ==========================================
-- COMBO NORMAL
-- ==========================================

local function performAttack()
    if not canAct() then
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

    local progress =
        getAttackElapsed() / math.max(attackDuration, 0.01)

    if progress >= COMBO_WINDOW_START
        and progress <= 1 then
        queuedAttack = data.Next
    end
end

-- ==========================================
-- CONFIRMACAO DO SERVIDOR
-- ==========================================

hitstopEvent.OnClientEvent:Connect(function(
    name,
    duration,
    confirmed,
    id
)
    if typeof(name) ~= "string"
        or typeof(duration) ~= "number"
        or typeof(confirmed) ~= "boolean"
        or typeof(id) ~= "number" then
        return
    end

    if fighter:GetState() ~= "Attack"
        or currentAttack ~= name
        or id ~= attackSequence
        or hitResolved then
        return
    end

    if not hitRequested then
        hitResponse = {
            Duration = duration,
            Confirmed = confirmed,
        }
        return
    end

    applyHitResult(name, duration, confirmed)
end)

-- ==========================================
-- ATUALIZACAO
-- ==========================================

RunService.Heartbeat:Connect(function()
    -- ======================================
    -- GUARD E QUICKSTEP
    -- ======================================

    if isQuickStepping() then
        if fighter:GetState() == "Block" then
            -- Cancela e exige novo pressionamento de M2.
            guardHeld = false
            stopGuard()

            print("[Guard] Cancelado por QuickStep")
        end
    elseif fighter:GetState() == "Block" then
        if not guardHeld or not canAct() then
            stopGuard()
        else
            updateGuardAnimation()
        end
    elseif guardHeld
        and canAct()
        and fighter:GetState() == "Idle" then
        startGuard()
    end

    -- ======================================
    -- HEAVY
    -- ======================================

    if heavyPhase then
        if not canAct() then
            cancelHeavy(true)
            mouseHeld = false
            mouseToken += 1
            return
        end

        heavyCharge = math.clamp(
            (os.clock() - heavyStartedAt)
                / heavyConfig.ChargeDuration,
            0,
            1
        )

        setHeavyAttributes(true, heavyCharge)
    end

    if not currentAttack
        or fighter:GetState() ~= "Attack" then
        return
    end

    local name = currentAttack
    local data = AnimationData.Combat[name]

    if not data or attackDuration <= 0 then
        return
    end

    local track = tracks[name]

    -- ======================================
    -- HITSTOP
    -- ======================================

    if hitstopStartedAt then
        local now = os.clock()

        if now < hitstopEndsAt then
            return
        end

        totalPausedTime += now - hitstopStartedAt
        hitstopStartedAt = nil
        hitstopEndsAt = 0

        if track and track.IsPlaying then
            track:AdjustSpeed(data.Speed or 1)
        end

        print("[Hitstop] FIM:", name)
    end

    -- ======================================
    -- PAUSA FINAL DO HEAVYPUNCH
    -- ======================================

    if name == "HeavyPunch"
        and track
        and track.IsPlaying then

        if not heavyEndFreezeDone
            and not heavyEndFreezeStartedAt
            and not hitstopStartedAt
            and track.Length > 0
            and track.TimePosition
                >= track.Length * HEAVY_END_FREEZE_AT then

            heavyEndFreezeStartedAt = os.clock()
            heavyEndFreezeEndsAt =
                heavyEndFreezeStartedAt
                + HEAVY_END_FREEZE_DURATION

            track:AdjustSpeed(0)

            print("[HeavyPunch] Pose final congelada")
        end

        if heavyEndFreezeStartedAt then
            local now = os.clock()

            if now < heavyEndFreezeEndsAt then
                return
            end

            totalHeavyEndPausedTime +=
                now - heavyEndFreezeStartedAt

            heavyEndFreezeStartedAt = nil
            heavyEndFreezeEndsAt = 0
            heavyEndFreezeDone = true

            track:AdjustSpeed(data.Speed or 1)

            print("[HeavyPunch] Pose final liberada")
        end
    end

    local elapsed = getAttackElapsed()
    local progress = elapsed / attackDuration

    local hitAt = math.clamp(
        data.HitAt or 0.90,
        0,
        1
    )

    -- ======================================
    -- IMPACTO
    -- ======================================

    if not hitRequested and progress >= hitAt then
        hitRequested = true
        hitRequestedAt = os.clock()

        if hitResponse then
            local response = hitResponse
            hitResponse = nil

            applyHitResult(
                name,
                response.Duration,
                response.Confirmed
            )
        end
    end

    if hitRequested and not hitResolved then
        if os.clock() - hitRequestedAt >= HIT_TIMEOUT then
            hitResolved = true
            print("[Combat] Timeout:", name)
        else
            return
        end
    end

    if not hitRequested
        or not hitResolved
        or hitstopStartedAt then
        return
    end

    -- ======================================
    -- TRANSICAO DO COMBO
    -- ======================================

    local transition = data.Transition
        or COMBO_TRANSITION

    local transitionTime =
        attackDuration * math.max(transition, hitAt)

    if queuedAttack and elapsed >= transitionTime then
        if not isRolling() then
            startAttack(queuedAttack)
        else
            queuedAttack = nil
        end
        return
    end

    if elapsed >= attackDuration then
        if queuedAttack and not isRolling() then
            startAttack(queuedAttack)
        else
            finishCombo(attackSequence)
        end
    end
end)

-- ==========================================
-- INPUT
-- ==========================================

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end

    -- M2: Guard
    if input.UserInputType
        == Enum.UserInputType.MouseButton2 then

        -- Nao inicia Guard durante QuickStep.
        if isQuickStepping() then
            return
        end

        guardHeld = true

        if mouseHeld and not heavyPhase then
            mouseHeld = false
            mouseToken += 1
        end

        startGuard()
        return
    end

    if input.UserInputType
        ~= Enum.UserInputType.MouseButton1 then
        return
    end

    if guardHeld or fighter:GetState() == "Block" then
        return
    end

    if mouseHeld then
        return
    end

    mouseHeld = true
    mousePressedAt = os.clock()
    mouseToken += 1

    local token = mouseToken

    task.delay(heavyConfig.HoldThreshold, function()
        if token ~= mouseToken
            or not mouseHeld
            or guardHeld then
            return
        end

        if not canAct() then
            return
        end

        if fighter:GetState() ~= "Idle" then
            return
        end

        startHeavy()
    end)
end)

UIS.InputEnded:Connect(function(input)
    -- Soltar M2
    if input.UserInputType
        == Enum.UserInputType.MouseButton2 then

        guardHeld = false
        stopGuard()

        print("[Guard] Desativado")
        return
    end

    if input.UserInputType
        ~= Enum.UserInputType.MouseButton1 then
        return
    end

    if not mouseHeld then
        return
    end

    mouseHeld = false
    mouseToken += 1

    if heavyPhase then
        releaseHeavy()
    else
        local held = os.clock() - mousePressedAt

        if held < heavyConfig.HoldThreshold
            and not guardHeld then
            performAttack()
        end
    end
end)

-- ==========================================
-- INICIALIZACAO
-- ==========================================

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

print("[Combat] Combo + Heavy Melee + Guard carregados")
