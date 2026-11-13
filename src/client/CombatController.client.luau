
-- CombatController.client.luau
-- Sistema de combo com quatro ataques encadeados

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")

local attackEvent = ReplicatedStorage:WaitForChild("CombatAttack")

local StateMachine = require(shared:WaitForChild("StateMachine"))
local AnimationData = require(shared:WaitForChild("AnimationData"))

local FIRST_ATTACK = "Punch1"

local DEFAULT_ATTACK_DURATION = 0.4
local MIN_ATTACK_DURATION = 0.15
local RECOVERY_DURATION = 0.2

local COMBO_WINDOW_START = 0.25
local COMBO_TRANSITION = 0.75

local fighter = StateMachine.new()

local humanoid = nil
local attackTracks = {}

local currentAttack = nil
local attackStartedAt = 0
local attackDuration = 0

local queuedAttack = nil
local attackSequence = 0

-- Prepara o personagem e carrega as animacoes
local function setupCharacter(character)
    attackSequence += 1

    fighter:ForceState("Idle")

    currentAttack = nil
    queuedAttack = nil
    attackStartedAt = 0
    attackDuration = 0

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
    local sequence = attackSequence

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

    track:Stop(0)
    track:Play(0.08)
    track:AdjustSpeed(data.Speed)

    local duration = data.Duration or track.Length

    if duration <= 0 then
        duration = DEFAULT_ATTACK_DURATION
    end

    attackDuration = math.max(
        duration / data.Speed,
        MIN_ATTACK_DURATION
    )

    print("[Combat] Ataque:", attackName)

    -- Solicita a verificacao de impacto ao servidor
    local hitDelay = data.HitDelay or 0.15

    task.delay(hitDelay, function()
        if sequence ~= attackSequence then
            return
        end

        if not humanoid or humanoid.Health <= 0 then
            return
        end

        if fighter:GetState() ~= "Attack" then
            return
        end

        attackEvent:FireServer(attackName)
    end)

    -- Calcula o momento de transicao para o proximo golpe
    local transitionPoint = data.Transition or COMBO_TRANSITION

    task.delay(attackDuration * transitionPoint, function()
        if sequence ~= attackSequence then
            return
        end

        if queuedAttack then
            local nextAttack = queuedAttack
            startAttack(nextAttack)
            return
        end

        -- Aguarda ate o fim da janela do combo
        local remaining = attackDuration * (1 - transitionPoint)

        task.delay(remaining, function()
            if sequence ~= attackSequence then
                return
            end

            if queuedAttack then
                local nextAttack = queuedAttack
                startAttack(nextAttack)
            else
                finishCombo(sequence)
            end
        end)
    end)
end

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

    local elapsed = os.clock() - attackStartedAt
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
