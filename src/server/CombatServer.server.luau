
-- CombatServer.server.luau
-- Deteccao e validacao de ataques no servidor
-- Resolucao de acertos delegada ao CombatHit

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatHit = require(script.Parent:WaitForChild("CombatHit"))

local ATTACK_RANGE = 5
local ATTACK_COOLDOWN = 0.10
local MIN_FACING_DOT = 0.35

local ATTACK_DAMAGE = {
    Punch1 = 5,
    Punch2 = 5,
    Punch3 = 8,
    Finisher4 = 12,
}

-- RemoteEvent dos ataques

local attackEvent = ReplicatedStorage:FindFirstChild("CombatAttack")

if not attackEvent then
    attackEvent = Instance.new("RemoteEvent")
    attackEvent.Name = "CombatAttack"
    attackEvent.Parent = ReplicatedStorage
end

-- RemoteEvent do Hitstop
-- NOVO: sera utilizado nas proximas etapas

local hitstopEvent = ReplicatedStorage:FindFirstChild("CombatHitstop")

if not hitstopEvent then
    hitstopEvent = Instance.new("RemoteEvent")
    hitstopEvent.Name = "CombatHitstop"
    hitstopEvent.Parent = ReplicatedStorage
end

-- Controle de cooldown por jogador

local lastAttack = {}

local function processAttack(player, attackName)

    -- Validacao do ataque recebido

    if typeof(attackName) ~= "string" then
        return
    end

    local damage = ATTACK_DAMAGE[attackName]

    if not damage then
        return
    end

    -- Cooldown

    local now = os.clock()

    if lastAttack[player]
        and now - lastAttack[player] < ATTACK_COOLDOWN then
        return
    end

    -- Validacao do personagem atacante

    local character = player.Character

    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 or not root then
        return
    end

    lastAttack[player] = now

    -- Localizacao do alvo de treinamento

    local dummy = Workspace:FindFirstChild("TrainingDummy")

    if not dummy then
        return
    end

    local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
    local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")

    if not dummyHumanoid or not dummyRoot then
        return
    end

    if dummyHumanoid.Health <= 0 then
        return
    end

    -- Calculo da distancia horizontal

    local offset = dummyRoot.Position - root.Position

    local horizontalOffset = Vector3.new(
        offset.X,
        0,
        offset.Z
    )

    local distance = horizontalOffset.Magnitude

    if distance > ATTACK_RANGE then
        return
    end

    -- Verificacao da direcao do atacante

    if distance > 0.001 then

        local forward = Vector3.new(
            root.CFrame.LookVector.X,
            0,
            root.CFrame.LookVector.Z
        )

        if forward.Magnitude < 0.001 then
            return
        end

        local facingDot = forward.Unit:Dot(
            horizontalOffset.Unit
        )

        if facingDot < MIN_FACING_DOT then
            return
        end
    end

    -- Resolucao do acerto

    local hitApplied = CombatHit.Apply(
        player,
        dummy,
        attackName,
        damage
    )

    if not hitApplied then
        return
    end

    print(
        "[CombatServer]",
        player.Name,
        "acertou",
        attackName,
        "em",
        dummy.Name,
        "| Dano:",
        damage,
        "| Vida restante:",
        dummyHumanoid.Health
    )
end

-- Recebimento dos ataques

attackEvent.OnServerEvent:Connect(processAttack)

-- Limpeza dos dados ao desconectar

Players.PlayerRemoving:Connect(function(player)
    lastAttack[player] = nil
end)

print("[CombatServer] Sistema de combate iniciado")
