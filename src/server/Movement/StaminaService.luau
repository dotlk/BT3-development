
-- StaminaService.luau
-- Controle autoritativo da Stamina no servidor

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaminaData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StaminaData")
)

local StaminaService = {}

local states = {}

-- ==========================================
-- SINCRONIZACAO
-- ==========================================

local function publish(player, state)
    player:SetAttribute("QuickStepStamina", state.Value)
end

-- ==========================================
-- ESTADO
-- ==========================================

local function createState(player)
    local state = {
        Value = StaminaData.Max,
        LastUse = os.clock(),
        LastRegen = os.clock(),
        LastActions = {},
    }

    states[player] = state
    publish(player, state)

    return state
end

local function getState(player)
    return states[player] or createState(player)
end

-- ==========================================
-- REGENERACAO
-- ==========================================

local function updateRegen(player, state)
    local now = os.clock()
    local regen = StaminaData.Regen

    if state.Value >= StaminaData.Max then
        return
    end

    -- Momento da primeira recuperacao.
    local firstRegenAt = state.LastUse + regen.Delay

    if now < firstRegenAt then
        return
    end

    local interval = math.max(regen.Interval, 0.01)

    -- Permite a primeira recuperacao ao fim do Delay,
    -- sem esperar um Interval adicional.
    local lastRegen = math.max(
        state.LastRegen,
        firstRegenAt - interval
    )

    local intervals = math.floor(
        (now - lastRegen) / interval
    )

    if intervals <= 0 then
        return
    end

    state.Value = math.min(
        StaminaData.Max,
        state.Value + intervals * regen.Amount
    )

    state.LastRegen = lastRegen + intervals * interval

    publish(player, state)
end

-- ==========================================
-- CONSUMO DE STAMINA
-- ==========================================

function StaminaService.TrySpend(player, action)
    local cost = StaminaData.Costs[action]
    local cooldown = StaminaData.Cooldowns[action]

    if not cost or not cooldown then
        return false
    end

    local state = getState(player)

    updateRegen(player, state)

    local now = os.clock()
    local lastAction =
        state.LastActions[action] or -math.huge

    -- Verifica cooldown.
    if now - lastAction < cooldown then
        return false
    end

    -- Verifica Stamina disponivel.
    if state.Value < cost then
        return false
    end

    -- Consome Stamina.
    state.Value -= cost

    -- Reinicia o tempo de espera da regeneracao.
    state.LastUse = now
    state.LastRegen = now

    state.LastActions[action] = now

    publish(player, state)

    return true
end

-- ==========================================
-- CONSULTA
-- ==========================================

function StaminaService.Get(player)
    local state = getState(player)

    updateRegen(player, state)

    return state.Value
end

-- ==========================================
-- RESET
-- ==========================================

function StaminaService.Reset(player)
    createState(player)
end

function StaminaService.Remove(player)
    states[player] = nil
end

-- ==========================================
-- INICIALIZACAO DOS JOGADORES
-- ==========================================

Players.PlayerAdded:Connect(function(player)
    createState(player)

    player.CharacterAdded:Connect(function()
        StaminaService.Reset(player)
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    createState(player)

    player.CharacterAdded:Connect(function()
        StaminaService.Reset(player)
    end)
end

Players.PlayerRemoving:Connect(StaminaService.Remove)

-- ==========================================
-- REGENERACAO PERIODICA
-- ==========================================

task.spawn(function()
    while true do
        task.wait(0.25)

        for player, state in pairs(states) do
            updateRegen(player, state)
        end
    end
end)

return StaminaService
