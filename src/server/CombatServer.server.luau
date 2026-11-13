
-- CombatServer.server.luau
-- Deteccao continua de hitboxes durante ataques
-- Estrutura inspirada na arquitetura de combate do BT3

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatHit = require(
    script.Parent:WaitForChild("CombatHit")
)

local CombatCollision = require(
    script.Parent:WaitForChild("CombatCollision")
)

local AnimationData = require(
    ReplicatedStorage
        :WaitForChild("Shared")
        :WaitForChild("AnimationData")
)

local ATTACK_COOLDOWN = 0.10

-- Duracao provisoria para ataques sem Duration.
-- Posteriormente usaremos o tempo real da animacao.
local DEFAULT_ATTACK_DURATION = 0.8

local attackEvent =
    ReplicatedStorage:FindFirstChild("CombatAttack")

if not attackEvent then
    attackEvent = Instance.new("RemoteEvent")
    attackEvent.Name = "CombatAttack"
    attackEvent.Parent = ReplicatedStorage
end

local hitstopEvent =
    ReplicatedStorage:FindFirstChild("CombatHitstop")

if not hitstopEvent then
    hitstopEvent = Instance.new("RemoteEvent")
    hitstopEvent.Name = "CombatHitstop"
    hitstopEvent.Parent = ReplicatedStorage
end

local lastAttack = {}
local activeAttacks = {}

local function sendHitResult(
    player,
    attackName,
    hitConfirmed
)
    local duration = 0

    if hitConfirmed then
        local attackData = AnimationData.Combat[attackName]

        if attackData then
            duration = attackData.Hitstop or 0
        end
    end

    hitstopEvent:FireClient(
        player,
        attackName,
        duration,
        hitConfirmed
    )
end

local function getValidCharacter(player)
    local character = player.Character

    if not character then
        return nil
    end

    local humanoid =
        character:FindFirstChildOfClass("Humanoid")

    local root =
        character:FindFirstChild("HumanoidRootPart")

    if not humanoid
        or humanoid.Health <= 0
        or not root
        or not root:IsA("BasePart") then

        return nil
    end

    return character
end

local function finishAttack(
    player,
    attack,
    hitConfirmed
)
    if activeAttacks[player] ~= attack then
        return
    end

    activeAttacks[player] = nil

    if attack.Connection then
        attack.Connection:Disconnect()
        attack.Connection = nil
    end

    sendHitResult(
        player,
        attack.Name,
        hitConfirmed
    )
end

local function processAttack(player, attackName)
    if typeof(attackName) ~= "string" then
        return
    end

    local attackData = AnimationData.Combat[attackName]

    if not attackData or not attackData.Hitbox then
        return
    end

    -- Impede iniciar outro ataque enquanto
    -- a janela anterior ainda esta ativa.
    if activeAttacks[player] then
        sendHitResult(player, attackName, false)
        return
    end

    local now = os.clock()

    if lastAttack[player]
        and now - lastAttack[player] < ATTACK_COOLDOWN then

        sendHitResult(player, attackName, false)
        return
    end

    local character = getValidCharacter(player)

    if not character then
        sendHitResult(player, attackName, false)
        return
    end

    local hitbox = attackData.Hitbox

    local attackDuration =
        attackData.Duration or DEFAULT_ATTACK_DURATION

    local startFraction = math.clamp(
        hitbox.Start or 0,
        0,
        1
    )

    local finishFraction = math.clamp(
        hitbox.Finish or 1,
        0,
        1
    )

    if finishFraction <= startFraction then
        sendHitResult(player, attackName, false)
        return
    end

    local windowDuration =
        (finishFraction - startFraction) * attackDuration

    lastAttack[player] = now

    local attack = {
        Name = attackName,
        Character = character,
        StartedAt = now,
        Duration = windowDuration,
        Connection = nil,
        HitTargets = {},
    }

    activeAttacks[player] = attack

    print(
        "[CombatCollision] JANELA INICIADA:",
        player.Name,
        "| Golpe:",
        attackName,
        "| Duracao:",
        windowDuration
    )

    -- Executa a primeira consulta imediatamente,
    -- sem esperar o proximo Heartbeat.
    local function checkCollision()
        if activeAttacks[player] ~= attack then
            return
        end

        if getValidCharacter(player) ~= character then
            finishAttack(player, attack, false)
            return
        end

        local dummy = Workspace:FindFirstChild("TrainingDummy")

        if not dummy then
            finishAttack(player, attack, false)
            return
        end

        local dummyHumanoid =
            dummy:FindFirstChildOfClass("Humanoid")

        if not dummyHumanoid or dummyHumanoid.Health <= 0 then
            finishAttack(player, attack, false)
            return
        end

        local targets = CombatCollision.Query(
            character,
            hitbox.Size,
            hitbox.Offset
        )

        for _, target in ipairs(targets) do
            if target == dummy
                and not attack.HitTargets[target] then

                attack.HitTargets[target] = true

                local hitApplied = CombatHit.Apply(
                    player,
                    target,
                    attackName,
                    attackData.Damage
                )

                if hitApplied then
                    print(
                        "[CombatCollision] HIT:",
                        player.Name,
                        "| Golpe:",
                        attackName,
                        "| Alvo:",
                        target.Name
                    )

                    finishAttack(player, attack, true)
                    return
                end
            end
        end

        local elapsed = os.clock() - attack.StartedAt

        if elapsed >= attack.Duration then
            print(
                "[CombatCollision] MISS:",
                player.Name,
                "| Golpe:",
                attackName
            )

            finishAttack(player, attack, false)
        end
    end

    attack.Connection = RunService.Heartbeat:Connect(
        checkCollision
    )

    checkCollision()
end

attackEvent.OnServerEvent:Connect(processAttack)

Players.PlayerRemoving:Connect(function(player)
    local attack = activeAttacks[player]

    if attack and attack.Connection then
        attack.Connection:Disconnect()
    end

    activeAttacks[player] = nil
    lastAttack[player] = nil
end)

print(
    "[CombatServer] Sistema de colisao continua iniciado"
)
