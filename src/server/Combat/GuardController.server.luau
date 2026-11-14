
-- GuardController.server.luau
-- Recebe solicitacoes de Guard do cliente.
-- O servidor decide se a defesa pode ser ativada.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuardService = require(
    script.Parent:WaitForChild("GuardService")
)

-- ==========================================
-- REMOTE EVENT
-- ==========================================

local guardRequest = ReplicatedStorage:FindFirstChild(
    "GuardRequest"
)

if not guardRequest then
    guardRequest = Instance.new("RemoteEvent")
    guardRequest.Name = "GuardRequest"
    guardRequest.Parent = ReplicatedStorage
end

-- ==========================================
-- VALIDACAO
-- ==========================================

local function canStartGuard(player)
    local character = player.Character

    if not character then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if not character:FindFirstChild("HumanoidRootPart") then
        return false
    end

    if character:GetAttribute("CombatStunned") == true
        or character:GetAttribute("GuardBroken") == true
        or character:GetAttribute("IsRolling") == true
        or character:GetAttribute("IsQuickStepping") == true then
        return false
    end

    if GuardService.GetSegments(character) <= 0 then
        return false
    end

    return true
end

-- ==========================================
-- SOLICITACOES
-- ==========================================

guardRequest.OnServerEvent:Connect(function(player, guarding)
    if typeof(guarding) ~= "boolean" then
        return
    end

    local character = player.Character

    if not character then
        return
    end

    -- Desativar a defesa sempre e permitido.
    if not guarding then
        GuardService.SetGuarding(character, false)
        return
    end

    if not canStartGuard(player) then
        GuardService.SetGuarding(character, false)
        return
    end

    GuardService.SetGuarding(character, true)
end)

-- ==========================================
-- CANCELAMENTO POR STUN
-- ==========================================

local function setupCharacter(character)
    local function updateGuard()
        if character:GetAttribute("CombatStunned") == true
            or character:GetAttribute("GuardBroken") == true then

            GuardService.SetGuarding(character, false)
        end
    end

    character:GetAttributeChangedSignal(
        "CombatStunned"
    ):Connect(updateGuard)

    character:GetAttributeChangedSignal(
        "GuardBroken"
    ):Connect(updateGuard)
end

local function setupPlayer(player)
    player.CharacterAdded:Connect(setupCharacter)

    if player.Character then
        setupCharacter(player.Character)
    end
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

print("[GuardController] Sistema inicializado")
