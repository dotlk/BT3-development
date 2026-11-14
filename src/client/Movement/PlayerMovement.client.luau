
-- PlayerMovement.client.luau
-- Gerencia velocidade, corrida e penalidade de Guard.
-- Duplo toque em qualquer WASD ativa corrida fora do Lock-On.
-- Trocar de direcao nao interrompe a corrida.
-- Durante Guard, a corrida e bloqueada e a velocidade reduzida.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local WALK_SPEED = 12
local RUN_SPEED = 20
local GUARD_SPEED = 8

local DOUBLE_TAP_WINDOW = 0.30

local MOVEMENT_KEYS = {
    [Enum.KeyCode.W] = true,
    [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true,
    [Enum.KeyCode.D] = true,
}

-- ==========================================
-- ESTADO
-- ==========================================

local lastTap = {}
local sprinting = false

local humanoid
local activeCharacter
local targetValue

-- ==========================================
-- FUNCOES
-- ==========================================

local function anyMovementHeld()
    for key in pairs(MOVEMENT_KEYS) do
        if UserInputService:IsKeyDown(key) then
            return true
        end
    end

    return false
end

local function hasLockOn()
    return targetValue ~= nil
        and targetValue.Parent ~= nil
        and targetValue.Value ~= nil
end

local function isGuarding()
    return activeCharacter ~= nil
        and activeCharacter:GetAttribute("Guarding") == true
end

local function setSprint(value)
    sprinting = value

    if activeCharacter then
        activeCharacter:SetAttribute("IsSprinting", value)
    end
end

local function stopSprint()
    setSprint(false)
end

-- ==========================================
-- INPUT DE CORRIDA
-- ==========================================

UserInputService.InputBegan:Connect(function(input, processed)
    local key = input.KeyCode

    if not MOVEMENT_KEYS[key]
        or processed
        or UserInputService:GetFocusedTextBox() then
        return
    end

    -- Nao permite iniciar corrida durante Guard.
    if isGuarding() then
        stopSprint()
        table.clear(lastTap)
        return
    end

    local now = os.clock()
    local previous = lastTap[key]

    lastTap[key] = now

    if previous
        and now - previous <= DOUBLE_TAP_WINDOW then

        if not hasLockOn() then
            setSprint(true)
        end

        lastTap[key] = nil
    end
end)

-- ==========================================
-- SETUP DO PERSONAGEM
-- ==========================================

local function setupCharacter(character)
    activeCharacter = character
    humanoid = character:WaitForChild("Humanoid")

    targetValue = character:FindFirstChild("LockOnTarget")

    if not targetValue then
        targetValue = Instance.new("ObjectValue")
        targetValue.Name = "LockOnTarget"
        targetValue.Parent = character
    end

    humanoid.WalkSpeed = WALK_SPEED

    stopSprint()
    table.clear(lastTap)
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

-- ==========================================
-- CONTROLE DE VELOCIDADE
-- ==========================================

RunService:BindToRenderStep(
    "PlayerMovementSpeed",
    Enum.RenderPriority.Character.Value + 2,
    function()
        if not humanoid
            or not humanoid.Parent
            or humanoid.Health <= 0 then
            return
        end

        -- QuickStepController controla a velocidade
        -- durante Roll.
        if activeCharacter
            and activeCharacter:GetAttribute("IsRolling") then
            return
        end

        -- ==================================
        -- GUARD
        -- ==================================

        if isGuarding() then
            -- Interrompe imediatamente a corrida.
            if sprinting then
                stopSprint()
            end

            -- Impede que toques anteriores ativem
            -- corrida apos soltar Guard.
            table.clear(lastTap)

            humanoid.WalkSpeed = GUARD_SPEED
            return
        end

        -- ==================================
        -- LOCK-ON
        -- ==================================

        if hasLockOn() then
            stopSprint()
            humanoid.WalkSpeed = WALK_SPEED
            return
        end

        -- ==================================
        -- MOVIMENTACAO NORMAL
        -- ==================================

        if sprinting and not anyMovementHeld() then
            stopSprint()
        end

        humanoid.WalkSpeed =
            sprinting and RUN_SPEED or WALK_SPEED
    end
)
