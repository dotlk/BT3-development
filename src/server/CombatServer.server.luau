-- CombatServer.server.luau
-- Protocolo: CombatAttack(attackName, attackId, durationSeconds)
-- Resposta: CombatHitstop(attackName, hitstopSeconds, hitConfirmed, attackId)
-- O servidor controla as janelas de colisao e valida os alvos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatHit = require(script.Parent:WaitForChild("CombatHit"))
local CombatCollision = require(script.Parent:WaitForChild("CombatCollision"))
local AnimationData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AnimationData"))

local MIN_ATTACK_DURATION = 0.15
local MAX_ATTACK_DURATION = 2.0
local MIN_ATTACK_INTERVAL = 0.10
local activeAttacks = {}
local lastAttack = {}
local lastAttackId = {}

local function remote(name)
    local event = ReplicatedStorage:FindFirstChild(name)
    if not event then
        event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = ReplicatedStorage
    end
    return event
end

local attackEvent = remote("CombatAttack")
local hitstopEvent = remote("CombatHitstop")

local function validCharacter(player)
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
        return nil
    end
    return character
end

local function reply(player, attack, confirmed)
    local data = AnimationData.Combat[attack.Name]
    hitstopEvent:FireClient(player, attack.Name, confirmed and (data.Hitstop or 0) or 0, confirmed, attack.Id)
end

local function finish(player, attack, confirmed)
    if activeAttacks[player] ~= attack then return end
    activeAttacks[player] = nil
    if attack.Connection then
        attack.Connection:Disconnect()
        attack.Connection = nil
    end
    reply(player, attack, confirmed)
    print("[CombatCollision]", confirmed and "HIT" or "MISS", attack.Name, "#", attack.Id)
end

local function processAttack(player, attackName, attackId, duration)
    if typeof(attackName) ~= "string" or typeof(attackId) ~= "number"
        or attackId % 1 ~= 0 or attackId < 1 or attackId > 1000000000
        or typeof(duration) ~= "number" or duration ~= duration then
        return
    end

    local data = AnimationData.Combat[attackName]
    if not data or not data.Hitbox then return end
    if duration < MIN_ATTACK_DURATION or duration > MAX_ATTACK_DURATION then return end

    local character = validCharacter(player)
    if not character then return end
    if attackId <= (lastAttackId[player] or 0) then return end

    local now = os.clock()
    local previous = lastAttack[player]
    if previous then
        if now - previous.StartedAt < MIN_ATTACK_INTERVAL then return end
        -- Um novo golpe so pode seguir o anterior na sequencia do combo.
        if data ~= AnimationData.Combat.Punch1 then
            local previousData = AnimationData.Combat[previous.Name]
            if not previousData or previousData.Next ~= attackName then return end
            -- Impede avancar para o proximo golpe imediatamente.
            if now - previous.StartedAt < previous.Duration * 0.5 then return end
        end
    elseif attackName ~= "Punch1" then
        return
    end

    local previousActive = activeAttacks[player]
    if previousActive then
        -- Nao permite interromper uma janela de colisao ainda ativa.
        return
    end

    local hitbox = data.Hitbox
    local startFraction = math.clamp(hitbox.Start or 0, 0, 1)
    local finishFraction = math.clamp(hitbox.Finish or 1, 0, 1)
    if finishFraction <= startFraction then return end

    lastAttackId[player] = attackId
    lastAttack[player] = {Name = attackName, StartedAt = now, Duration = duration}

    local attack = {
        Id = attackId,
        Name = attackName,
        Character = character,
        StartedAt = now,
        StartAt = now + duration * startFraction,
        FinishAt = now + duration * finishFraction,
        Connection = nil,
    }
    activeAttacks[player] = attack
    print("[CombatCollision] ATAQUE REGISTRADO:", attackName, "#", attackId,
        "| Janela:", startFraction, "->", finishFraction)

    local function checkCollision()
        if activeAttacks[player] ~= attack then return end
        if validCharacter(player) ~= character then
            finish(player, attack, false)
            return
        end
        local currentTime = os.clock()
        if currentTime >= attack.FinishAt then
            finish(player, attack, false)
            return
        end
        if currentTime < attack.StartAt then return end

        -- Por enquanto, somente o TrainingDummy e um alvo valido.
        local dummy = Workspace:FindFirstChild("TrainingDummy")
        if not dummy then return end
        local dummyHumanoid = dummy:FindFirstChildOfClass("Humanoid")
        if not dummyHumanoid or dummyHumanoid.Health <= 0 then return end

        for _, target in ipairs(CombatCollision.Query(character, hitbox.Size, hitbox.Offset)) do
            if target == dummy then
                local applied = CombatHit.Apply(player, target, attackName, data.Damage)
                if applied then
                    finish(player, attack, true)
                    return
                end
            end
        end
    end

    attack.Connection = RunService.Heartbeat:Connect(checkCollision)
end

attackEvent.OnServerEvent:Connect(processAttack)

Players.PlayerRemoving:Connect(function(player)
    local attack = activeAttacks[player]
    if attack and attack.Connection then attack.Connection:Disconnect() end
    activeAttacks[player] = nil
    lastAttack[player] = nil
    lastAttackId[player] = nil
end)

print("[CombatServer] Hitboxes sincronizadas com o inicio dos ataques")