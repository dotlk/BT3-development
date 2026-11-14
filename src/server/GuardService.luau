
-- GuardService.luau
-- Controle autoritativo dos segmentos e regeneracao do Guard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuardData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GuardData")
)

local GuardService = {}

local states = {}

-- ==========================================
-- CONFIGURACAO
-- ==========================================

local MAX_SEGMENTS = GuardData.MaxSegments
local REGEN = GuardData.Regen

-- ==========================================
-- SINCRONIZACAO
-- ==========================================

local function publish(character, state)
    character:SetAttribute("GuardSegments", state.Segments)
    character:SetAttribute("GuardMaxSegments", MAX_SEGMENTS)
    character:SetAttribute("Guarding", state.Guarding)
end

local function isPaused(character, state)
    if state.Guarding and not REGEN.WhileGuarding then
        return true
    end

    if character:GetAttribute("GuardBroken") == true
        and not REGEN.WhileBroken then
        return true
    end

    return false
end

local function scheduleRegen(state)
    if not REGEN.Enabled
        or state.Segments >= MAX_SEGMENTS then
        state.NextRegen = nil
        return
    end

    state.NextRegen = os.clock() + REGEN.Delay
end

-- ==========================================
-- ESTADO
-- ==========================================

local function createState(character, preserveExisting)
    local segments = MAX_SEGMENTS
    local guarding = false

    -- O TrainingDummy ja possui atributos iniciais
    -- configurados pelo TrainingDummyGuard.
    if preserveExisting then
        local existing =
            character:GetAttribute("GuardSegments")

        if typeof(existing) == "number" then
            segments = math.clamp(
                math.floor(existing),
                0,
                MAX_SEGMENTS
            )
        end

        guarding =
            character:GetAttribute("Guarding") == true
    end

    if segments <= 0 then
        guarding = false
    end

    local state = {
        Segments = segments,
        Guarding = guarding,
        NextRegen = nil,
        WasPaused = false,
    }

    states[character] = state

    state.WasPaused = isPaused(character, state)

    if segments < MAX_SEGMENTS
        and not state.WasPaused then
        scheduleRegen(state)
    end

    publish(character, state)

    return state
end

local function getState(character)
    return states[character]
        or createState(character, true)
end

-- ==========================================
-- INICIALIZACAO
-- ==========================================

function GuardService.Initialize(character)
    local state = createState(character, false)

    character:SetAttribute("GuardBroken", false)

    return state
end

-- ==========================================
-- ATIVAR / DESATIVAR DEFESA
-- ==========================================

function GuardService.SetGuarding(character, guarding)
    if typeof(guarding) ~= "boolean" then
        return false
    end

    local state = getState(character)

    if guarding then
        local humanoid =
            character:FindFirstChildOfClass("Humanoid")

        if not humanoid or humanoid.Health <= 0 then
            return false
        end

        if state.Segments <= 0
            or character:GetAttribute("GuardBroken") == true
            or character:GetAttribute("CombatStunned") == true then
            return false
        end
    end

    local wasPaused = isPaused(character, state)

    state.Guarding = guarding

    local paused = isPaused(character, state)

    if paused then
        -- Regeneracao suspensa enquanto defende.
        state.NextRegen = nil
    elseif wasPaused then
        -- Ao sair da defesa, reinicia o Delay.
        scheduleRegen(state)
    end

    state.WasPaused = paused

    publish(character, state)

    return true
end

-- ==========================================
-- CONSULTA DA DEFESA
-- ==========================================

function GuardService.IsGuarding(character)
    local state = getState(character)

    -- O CombatStun e o TrainingDummyGuard tambem
    -- modificam o atributo Guarding no servidor.
    local guarding =
        character:GetAttribute("Guarding") == true

    return guarding
        and state.Segments > 0
        and character:GetAttribute("GuardBroken") ~= true
        and character:GetAttribute("CombatStunned") ~= true
end

function GuardService.GetSegments(character)
    return getState(character).Segments
end

-- ==========================================
-- CONSUMO DE SEGMENTOS
-- ==========================================

function GuardService.Spend(character, attackName)
    local cost = GuardData.SegmentCosts[attackName]

    if typeof(cost) ~= "number" or cost < 0 then
        return false
    end

    local state = getState(character)

    if not GuardService.IsGuarding(character) then
        return false
    end

    -- Socos leves bloqueados nao consomem Guard.
    if cost == 0 then
        return true
    end

    state.Segments = math.max(
        0,
        state.Segments - cost
    )

    if state.Segments <= 0 then
        state.Guarding = false
    else
        state.Guarding =
            character:GetAttribute("Guarding") == true
    end

    local paused = isPaused(character, state)

    if paused then
        -- Enquanto estiver defendendo, nao regenera.
        state.NextRegen = nil
    else
        -- Ao esgotar a defesa, inicia o Delay.
        scheduleRegen(state)
    end

    state.WasPaused = paused

    publish(character, state)

    return true
end

-- ==========================================
-- REGENERACAO
-- ==========================================

local function updateRegen(character, state)
    if not REGEN.Enabled then
        return
    end

    -- Sincroniza mudancas realizadas pelo
    -- CombatStun e pelo TrainingDummyGuard.
    local externalGuarding =
        character:GetAttribute("Guarding") == true

    state.Guarding = externalGuarding

    local paused = isPaused(character, state)

    if state.Segments >= MAX_SEGMENTS then
        state.NextRegen = nil
        state.WasPaused = paused
        return
    end

    if paused then
        state.NextRegen = nil
        state.WasPaused = true
        return
    end

    if state.WasPaused or not state.NextRegen then
        -- Primeira recuperacao apos o Delay.
        scheduleRegen(state)
        state.WasPaused = false
    end

    local now = os.clock()

    if now < state.NextRegen then
        return
    end

    local interval = math.max(
        REGEN.Interval,
        0.01
    )

    local ticks = 1 + math.floor(
        (now - state.NextRegen) / interval
    )

    state.Segments = math.min(
        MAX_SEGMENTS,
        state.Segments + ticks * REGEN.Amount
    )

    state.NextRegen =
        state.NextRegen + ticks * interval

    if state.Segments >= MAX_SEGMENTS then
        state.NextRegen = nil
    end

    publish(character, state)
end

-- ==========================================
-- LOOP DE REGENERACAO
-- ==========================================

task.spawn(function()
    while true do
        task.wait(0.25)

        for character, state in pairs(states) do
            if not character.Parent then
                states[character] = nil
            else
                updateRegen(character, state)
            end
        end
    end
end)

-- ==========================================
-- RESET / REMOCAO
-- ==========================================

function GuardService.Reset(character)
    GuardService.Initialize(character)
end

function GuardService.Remove(character)
    states[character] = nil
end

-- ==========================================
-- JOGADORES
-- ==========================================

local function setupPlayer(player)
    player.CharacterAdded:Connect(function(character)
        GuardService.Initialize(character)
    end)

    if player.Character then
        GuardService.Initialize(player.Character)
    end
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
    if player.Character then
        GuardService.Remove(player.Character)
    end
end)

return GuardService
