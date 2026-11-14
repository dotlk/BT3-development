
-- StaminaService.luau
-- Controle autoritativo da Stamina no servidor

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaminaData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StaminaData")
)

local StaminaService = {}

local states = {}

local function publish(player, state)
    player:SetAttribute("QuickStepStamina", state.Value)
end

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

local function updateRegen(player, state)
    local now = os.clock()
    local regen = StaminaData.Regen

    if state.Value >= StaminaData.Max then
        return
    end

    if now - state.LastUse < regen.Delay then
        return
    end

    local firstRegenAt = state.LastUse + regen.Delay

    local elapsed = math.max(
        0,
        now - math.max(state.LastRegen, firstRegenAt)
    )

    local intervals = math.floor(elapsed / regen.Interval)

    if intervals <= 0 then
        return
    end

    state.Value = math.min(
        StaminaData.Max,
        state.Value + intervals * regen.Amount
    )

    state.LastRegen =
        math.max(state.LastRegen, firstRegenAt)
        + intervals * regen.Interval

    publish(player, state)
end

function StaminaService.TrySpend(player, action)
    local cost = StaminaData.Costs[action]
    local cooldown = StaminaData.Cooldowns[action]

    if not cost or not cooldown then
        return false
    end

    local state = getState(player)
    updateRegen(player, state)

    local now = os.clock()
    local lastAction = state.LastActions[action] or -math.huge

    if now - lastAction < cooldown then
        return false
    end

    if state.Value < cost then
        return false
    end

    state.Value -= cost
    state.LastUse = now
    state.LastRegen = now
    state.LastActions[action] = now

    publish(player, state)

    return true
end

function StaminaService.Get(player)
    local state = getState(player)
    updateRegen(player, state)

    return state.Value
end

function StaminaService.Reset(player)
    createState(player)
end

function StaminaService.Remove(player)
    states[player] = nil
end

-- Inicializacao
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

-- Regeneracao periodica
task.spawn(function()
    while true do
        task.wait(0.25)

        for player, state in pairs(states) do
            updateRegen(player, state)
        end
    end
end)

return StaminaService
