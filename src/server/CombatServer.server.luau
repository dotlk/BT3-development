
-- CombatServer.server.luau
-- Validacao de ataques, Heavy Melee e Guard

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CombatHit = require(script.Parent:WaitForChild("CombatHit"))
local CombatCollision = require(script.Parent:WaitForChild("CombatCollision"))

local AnimationData = require(
    RS:WaitForChild("Shared"):WaitForChild("AnimationData")
)

local heavyConfig = AnimationData.Heavy

local MIN_DURATION = 0.15
local MAX_DURATION = 2
local MIN_INTERVAL = 0.10

local activeAttacks = {}
local lastAttack = {}
local lastAttackId = {}
local heavyCharges = {}

local function remote(name)
    local event = RS:FindFirstChild(name)

    if not event then
        event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = RS
    end

    return event
end

local attackEvent = remote("CombatAttack")
local hitstopEvent = remote("CombatHitstop")
local heavyEvent = remote("CombatHeavyCharge")

local function validCharacter(player)
    local character = player.Character
    if not character then return nil end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0
        or not root or not root:IsA("BasePart") then
        return nil
    end

    return character
end

local function reply(player, attack, confirmed)
    local data = AnimationData.Combat[attack.Name]

    hitstopEvent:FireClient(
        player,
        attack.Name,
        confirmed and (data.Hitstop or 0) or 0,
        confirmed,
        attack.Id
    )
end

local function finish(player, attack, confirmed)
    if activeAttacks[player] ~= attack then return end

    activeAttacks[player] = nil

    if attack.Connection then
        attack.Connection:Disconnect()
        attack.Connection = nil
    end

    reply(player, attack, confirmed)
end

-- ==========================================
-- CARREGAMENTO DO HEAVY
-- ==========================================

heavyEvent.OnServerEvent:Connect(function(player, action, chargeId)
    if typeof(action) ~= "string"
        or typeof(chargeId) ~= "number"
        or chargeId % 1 ~= 0
        or chargeId < 1
        or chargeId > 1000000000 then
        return
    end

    if action == "Cancel" then
        local charge = heavyCharges[player]

        if charge and charge.Id == chargeId then
            heavyCharges[player] = nil
        end

        return
    end

    if action ~= "Start" then return end

    local character = validCharacter(player)
    if not character then return end

    if character:GetAttribute("CombatStunned") == true
        or character:GetAttribute("IsRolling") == true then
        return
    end

    if activeAttacks[player] then return end

    local previous = lastAttack[player]

    if previous then
        local elapsed = os.clock() - previous.StartedAt

        if elapsed < previous.Duration + 0.15 then
            return
        end
    end

    local existing = heavyCharges[player]

    if existing and chargeId <= existing.Id then
        return
    end

    heavyCharges[player] = {
        Id = chargeId,
        StartedAt = os.clock(),
        Character = character,
    }
end)

-- ==========================================
-- PROCESSAMENTO DE ATAQUES
-- ==========================================

local function processAttack(
    player,
    attackName,
    attackId,
    duration,
    heavyId
)
    if typeof(attackName) ~= "string"
        or typeof(attackId) ~= "number"
        or attackId % 1 ~= 0
        or attackId < 1
        or attackId > 1000000000
        or typeof(duration) ~= "number"
        or duration ~= duration then
        return
    end

    local data = AnimationData.Combat[attackName]

    if not data or not data.Hitbox then return end

    if duration < MIN_DURATION or duration > MAX_DURATION then
        return
    end

    local character = validCharacter(player)
    if not character then return end

    if character:GetAttribute("CombatStunned") == true
        or character:GetAttribute("IsRolling") == true then
        return
    end

    if attackId <= (lastAttackId[player] or 0) then
        return
    end

    if activeAttacks[player] then return end

    local now = os.clock()
    local previous = lastAttack[player]
    local isHeavy = attackName == "HeavyPunch"

    local damage = data.Damage
    local chargeFraction = 0

    if isHeavy then
        local charge = heavyCharges[player]

        if not charge
            or charge.Character ~= character
            or charge.Id ~= heavyId then
            return
        end

        local elapsed = now - charge.StartedAt

        if elapsed < heavyConfig.HoldThreshold then
            return
        end

        chargeFraction = math.clamp(
            elapsed / heavyConfig.ChargeDuration,
            0,
            1
        )

        local multiplier = heavyConfig.MinMultiplier
            + (
                heavyConfig.MaxMultiplier
                - heavyConfig.MinMultiplier
            ) * chargeFraction

        damage = data.Damage * multiplier
    end

    if previous then
        if now - previous.StartedAt < MIN_INTERVAL then
            return
        end

        if isHeavy then
            if now - previous.StartedAt
                < previous.Duration + 0.15 then
                return
            end
        elseif attackName ~= "Punch1" then
            local previousData =
                AnimationData.Combat[previous.Name]

            if not previousData
                or previousData.Next ~= attackName then
                return
            end

            if now - previous.StartedAt
                < previous.Duration * 0.5 then
                return
            end
        end
    elseif not isHeavy and attackName ~= "Punch1" then
        return
    end

    if isHeavy then
        heavyCharges[player] = nil
    else
        heavyCharges[player] = nil
    end

    local hitbox = data.Hitbox

    local startFraction = math.clamp(
        hitbox.Start or 0, 0, 1
    )

    local finishFraction = math.clamp(
        hitbox.Finish or 1, 0, 1
    )

    if finishFraction <= startFraction then return end

    lastAttackId[player] = attackId

    lastAttack[player] = {
        Name = attackName,
        StartedAt = now,
        Duration = duration,
    }

    local attack = {
        Id = attackId,
        Name = attackName,
        Character = character,
        StartedAt = now,
        StartAt = now + duration * startFraction,
        FinishAt = now + duration * finishFraction,
        Damage = damage,
        Charge = chargeFraction,
        GuardBreak = isHeavy
            and chargeFraction >= heavyConfig.GuardBreakThreshold,
        Connection = nil,
    }

    activeAttacks[player] = attack

    print(
        "[CombatServer]",
        attackName,
        "Dano:", damage,
        "Carga:", math.floor(chargeFraction * 100) .. "%",
        "GuardBreak:", attack.GuardBreak
    )

    -- ==========================================
    -- DETECCAO DE COLISAO
    -- ==========================================

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

        local dummy = Workspace:FindFirstChild("TrainingDummy")
        if not dummy then return end

        local dummyHumanoid =
            dummy:FindFirstChildOfClass("Humanoid")

        if not dummyHumanoid or dummyHumanoid.Health <= 0 then
            return
        end

        for _, target in ipairs(
            CombatCollision.Query(
                character,
                hitbox.Size,
                hitbox.Offset
            )
        ) do
            if target == dummy then
                local applied = CombatHit.Apply(
                    player,
                    target,
                    attackName,
                    attack.Damage,
                    attack.GuardBreak
                )

                if applied then
                    finish(player, attack, true)
                    return
                end
            end
        end
    end

    attack.Connection =
        RunService.Heartbeat:Connect(checkCollision)
end

attackEvent.OnServerEvent:Connect(processAttack)

-- ==========================================
-- LIMPEZA
-- ==========================================

Players.PlayerRemoving:Connect(function(player)
    local attack = activeAttacks[player]

    if attack and attack.Connection then
        attack.Connection:Disconnect()
    end

    activeAttacks[player] = nil
    lastAttack[player] = nil
    lastAttackId[player] = nil
    heavyCharges[player] = nil
end)

print("[CombatServer] Heavy Melee + Guard habilitados")
