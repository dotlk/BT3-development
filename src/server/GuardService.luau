
-- GuardService.luau
-- Gerenciamento autoritativo dos segmentos de Guard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuardData = require(
    ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GuardData")
)

local GuardService = {}

local states = {}

local function publish(character, state)
    character:SetAttribute("GuardSegments", state.Segments)
    character:SetAttribute("GuardMaxSegments", GuardData.MaxSegments)
    character:SetAttribute("Guarding", state.Guarding)
end

local function getState(character)
    local state = states[character]

    if not state then
        state = {
            Segments = GuardData.MaxSegments,
            Guarding = false,
            LastDamage = os.clock(),
            NextRegen = nil,
        }

        states[character] = state
        publish(character, state)
    end

    return state
end

function GuardService.Initialize(character)
    states[character] = {
        Segments = GuardData.MaxSegments,
        Guarding = false,
        LastDamage = os.clock(),
        NextRegen = nil,
    }

    character:SetAttribute("GuardBroken", false)

    publish(character, states[character])
end

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

    state.Guarding = guarding
    publish(character, state)

    return true
end

function GuardService.IsGuarding(character)
    local state = getState(character)

    return state.Guarding
        and state.Segments > 0
        and character:GetAttribute("GuardBroken") ~= true
end

function GuardService.Spend(character, attackName)
    local cost = GuardData.SegmentCosts[attackName]

    if typeof(cost) ~= "number" then
        return false
    end

    local state = getState(character)

    if not state.Guarding or state.Segments <= 0 then
        return false
    end

    state.Segments = math.max(
        0,
        state.Segments - cost
    )

    state.LastDamage = os.clock()
    state.NextRegen =
        state.LastDamage + GuardData.Regen.Delay

    if state.Segments <= 0 then
        state.Guarding = false
    end

    publish(character, state)

    return true
end

function GuardService.GetSegments(character)
    return getState(character).Segments
end

function GuardService.Reset(character)
    GuardService.Initialize(character)
end

function GuardService.Remove(character)
    states[character] = nil
end

-- ==========================================
-- REGENERACAO
-- ==========================================

task.spawn(function()
    while true do
        task.wait(0.25)

        if not GuardData.Regen.Enabled then
            continue
        end

        local now = os.clock()

        for character, state in pairs(states) do
            if not character.Parent then
                states[character] = nil
                continue
            end

            if state.Segments >= GuardData.MaxSegments then
                state.NextRegen = nil
                continue
            end

            if state.Guarding
                and not GuardData.Regen.WhileGuarding then
                continue
            end

            if character:GetAttribute("GuardBroken") == true
                and not GuardData.Regen.WhileBroken then
                continue
            end

            if not state.NextRegen then
                state.NextRegen =
                    now + GuardData.Regen.Delay
            end

            if now >= state.NextRegen then
                state.Segments = math.min(
                    GuardData.MaxSegments,
                    state.Segments + GuardData.Regen.Amount
                )

                state.NextRegen =
                    now + GuardData.Regen.Interval

                publish(character, state)
            end
        end
    end
end)

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
