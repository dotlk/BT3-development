
-- StaminaController.server.luau
-- Recebe solicitacoes de Dash/Roll
-- e valida o consumo de Stamina no servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StaminaService = require(
    script.Parent:WaitForChild("StaminaService")
)

-- ==========================================
-- REMOTE FUNCTION
-- ==========================================

local staminaRequest = ReplicatedStorage:FindFirstChild(
    "StaminaRequest"
)

if not staminaRequest then
    staminaRequest = Instance.new("RemoteFunction")
    staminaRequest.Name = "StaminaRequest"
    staminaRequest.Parent = ReplicatedStorage
end

-- ==========================================
-- VALIDACAO
-- ==========================================

local function canPerformAction(player)
    local character = player.Character

    if not character then
        return false
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    if not humanoid
        or humanoid.Health <= 0
        or not root then

        return false
    end

    if character:GetAttribute("CombatStunned") == true
        or character:GetAttribute("GuardBroken") == true
        or character:GetAttribute("IsRolling") == true then

        return false
    end

    return true
end

-- ==========================================
-- SOLICITACAO DO CLIENTE
-- ==========================================

staminaRequest.OnServerInvoke = function(player, action)
    if action ~= "Dash" and action ~= "Roll" then
        return false
    end

    if not canPerformAction(player) then
        return false
    end

    local approved = StaminaService.TrySpend(
        player,
        action
    )

    if approved then
        print(
            "[StaminaController] Autorizado:",
            player.Name,
            action
        )
    end

    return approved
end

print("[StaminaController] Validacao de Stamina ativa")
