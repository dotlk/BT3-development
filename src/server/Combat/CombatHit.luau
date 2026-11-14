
-- CombatHit.luau
-- Resolucao de acertos, Guard, Hitstun, Knockback e Hitstop
-- Guard Break interrompido ao receber um golpe

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")

local HitReactionData = require(
    shared:WaitForChild("Combat"):WaitForChild("HitReactionData")
)

local AnimationData = require(
    shared:WaitForChild("AnimationData")
)

local CombatGuard = require(
    script.Parent:WaitForChild("CombatGuard")
)

local CombatStun = require(
    script.Parent:WaitForChild("CombatStun")
)

local CombatHit = {}

-- Configuracoes provisorias
local HITSTUN_DURATION = 0.25
local KNOCKBACK_DURATION = 0.55
local KNOCKBACK_SPEED = 35

local HIT_REACTION_FREEZE_TIME = 0.08

local HIT_ANIMATIONS = {
    Punch1 = "Hit2",
    Punch2 = "Hit1",
    Punch3 = "Hit2",
    Finisher4 = "Knockback1",
    HeavyPunch = "Hit2",
}

local reactionStates = setmetatable({}, {
    __mode = "k"
})

local reactionTracks = setmetatable({}, {
    __mode = "k"
})

local reactionAnimations = {}

for name, data in pairs(AnimationData.HitReactions) do
    local animation = Instance.new("Animation")
    animation.Name = name
    animation.AnimationId = data.Id

    reactionAnimations[name] = animation
end

-- Pre-carregamento das animacoes
task.spawn(function()
    local animations = {}

    for _, animation in pairs(reactionAnimations) do
        table.insert(animations, animation)
    end

    local success, err = pcall(function()
        ContentProvider:PreloadAsync(animations)
    end)

    if success then
        print("[HitReaction] Recursos pre-carregados")
    else
        warn("[HitReaction] Falha no preload:", err)
    end
end)

local function prepareReactions(humanoid)
    if reactionTracks[humanoid] then
        return reactionTracks[humanoid]
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")

    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local tracks = {}

    for name, animation in pairs(reactionAnimations) do
        local data = AnimationData.HitReactions[name]
        local track = animator:LoadAnimation(animation)

        track.Priority = data.Priority
        track.Looped = data.Looped

        tracks[name] = track
    end

    reactionTracks[humanoid] = tracks

    print(
        "[HitReaction] Tracks preparados:",
        humanoid.Parent.Name
    )

    return tracks
end

-- Prepara o dummy antecipadamente
task.spawn(function()
    local dummy = Workspace:WaitForChild("TrainingDummy")
    local humanoid = dummy:WaitForChild("Humanoid")

    prepareReactions(humanoid)
end)

local function stopHitAnimation(humanoid)
    local tracks = reactionTracks[humanoid]

    if not tracks then
        return
    end

    for _, track in pairs(tracks) do
        if track.IsPlaying then
            track:Stop(0.08)
        end
    end
end

local function playHitAnimation(
    humanoid,
    attackName,
    frozen
)
    local reactionName = HIT_ANIMATIONS[attackName]

    if not reactionName then
        return nil, 1
    end

    local tracks = prepareReactions(humanoid)
    local track = tracks[reactionName]

    if not track then
        warn(
            "[HitReaction] Track nao encontrado:",
            reactionName
        )
        return nil, 1
    end

    stopHitAnimation(humanoid)

    local speed =
        AnimationData.HitReactions[reactionName].Speed or 1

    track:Play(0)

    if frozen then
        track:AdjustSpeed(0)

        local length = track.Length

        if length > 0 then
            track.TimePosition = math.min(
                HIT_REACTION_FREEZE_TIME,
                math.max(length - 0.001, 0)
            )
        end
    else
        track:AdjustSpeed(speed)
    end

    print(
        "[HitReaction] Executando:",
        reactionName,
        "| Congelada:",
        frozen
    )

    return track, speed
end

local function getReactionState(humanoid)
    local state = reactionStates[humanoid]

    if not state then
        state = {
            Sequence = 0,
            Active = false,

            WalkSpeed = humanoid.WalkSpeed,
            JumpPower = humanoid.JumpPower,
            JumpHeight = humanoid.JumpHeight,

            KnockbackConnection = nil,
            HitstopEndsAt = 0,
        }

        reactionStates[humanoid] = state
    end

    return state
end

local function stopKnockback(state)
    if state.KnockbackConnection then
        state.KnockbackConnection:Disconnect()
        state.KnockbackConnection = nil
    end
end

local function beginReaction(defender, humanoid, state)
    if not state.Active then
        state.WalkSpeed = humanoid.WalkSpeed
        state.JumpPower = humanoid.JumpPower
        state.JumpHeight = humanoid.JumpHeight
    end

    state.Active = true
    state.Sequence += 1
    state.HitstopEndsAt = 0

    defender:SetAttribute("CombatStunned", true)

    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    return state.Sequence
end

local function finishReaction(
    defender,
    humanoid,
    state,
    sequence
)
    if state.Sequence ~= sequence then
        return
    end

    stopKnockback(state)

    if not humanoid.Parent then
        return
    end

    state.Active = false
    state.HitstopEndsAt = 0

    defender:SetAttribute("CombatStunned", false)

    humanoid.WalkSpeed = state.WalkSpeed
    humanoid.JumpPower = state.JumpPower
    humanoid.JumpHeight = state.JumpHeight

    stopHitAnimation(humanoid)

    print("[HitReaction] FIM:", defender.Name)
end

local function getHitstopDuration(attackName)
    local attackData = AnimationData.Combat[attackName]

    if not attackData then
        return 0
    end

    return math.clamp(
        attackData.Hitstop or 0,
        0,
        2
    )
end

local function applyDefenderHitstop(
    defender,
    humanoid,
    state,
    sequence,
    attackName,
    onComplete
)
    local duration = getHitstopDuration(attackName)
    local frozen = duration > 0

    local track, speed = playHitAnimation(
        humanoid,
        attackName,
        frozen
    )

    if not frozen then
        onComplete()
        return
    end

    state.HitstopEndsAt = os.clock() + duration

    print(
        "[DefenderHitstop] INICIO:",
        defender.Name,
        "| Golpe:",
        attackName,
        "| Duracao:",
        duration
    )

    task.delay(duration, function()
        if state.Sequence ~= sequence then
            return
        end

        if not humanoid.Parent then
            return
        end

        state.HitstopEndsAt = 0

        if track and track.IsPlaying then
            track:AdjustSpeed(speed)
        end

        print(
            "[DefenderHitstop] FIM:",
            defender.Name,
            "| Golpe:",
            attackName
        )

        onComplete()
    end)
end

local function applyHitstun(defender, attackName)
    local humanoid =
        defender:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local state = getReactionState(humanoid)

    stopKnockback(state)

    local sequence = beginReaction(
        defender,
        humanoid,
        state
    )

    print("[Hitstun] INICIO:", defender.Name)

    applyDefenderHitstop(
        defender,
        humanoid,
        state,
        sequence,
        attackName,
        function()
            task.delay(HITSTUN_DURATION, function()
                finishReaction(
                    defender,
                    humanoid,
                    state,
                    sequence
                )
            end)
        end
    )
end

local function applyKnockback(
    attacker,
    defender,
    attackName
)
    local humanoid =
        defender:FindFirstChildOfClass("Humanoid")

    local root =
        defender:FindFirstChild("HumanoidRootPart")

    if not humanoid
        or humanoid.Health <= 0
        or not root then
        return
    end

    local attackerCharacter = attacker.Character

    local attackerRoot = attackerCharacter
        and attackerCharacter:FindFirstChild("HumanoidRootPart")

    if not attackerRoot then
        return
    end

    local offset = root.Position - attackerRoot.Position

    local horizontal = Vector3.new(
        offset.X,
        0,
        offset.Z
    )

    if horizontal.Magnitude < 0.001 then
        local look = attackerRoot.CFrame.LookVector

        horizontal = Vector3.new(
            look.X,
            0,
            look.Z
        )
    end

    if horizontal.Magnitude < 0.001 then
        return
    end

    local direction = horizontal.Unit
    local state = getReactionState(humanoid)

    stopKnockback(state)

    local sequence = beginReaction(
        defender,
        humanoid,
        state
    )

    local currentVelocity = root.AssemblyLinearVelocity

    root.AssemblyLinearVelocity = Vector3.new(
        0,
        currentVelocity.Y,
        0
    )

    applyDefenderHitstop(
        defender,
        humanoid,
        state,
        sequence,
        attackName,
        function()
            if state.Sequence ~= sequence then
                return
            end

            if not root.Parent then
                return
            end

            local elapsed = 0

            state.KnockbackConnection =
                RunService.Heartbeat:Connect(function(dt)

                if state.Sequence ~= sequence
                    or not root.Parent then

                    stopKnockback(state)
                    return
                end

                elapsed += dt

                local progress = math.min(
                    elapsed / KNOCKBACK_DURATION,
                    1
                )

                local speed =
                    KNOCKBACK_SPEED * (1 - progress)

                local velocity =
                    root.AssemblyLinearVelocity

                root.AssemblyLinearVelocity = Vector3.new(
                    direction.X * speed,
                    velocity.Y,
                    direction.Z * speed
                )

                if progress >= 1 then
                    stopKnockback(state)
                end
            end)

            print(
                "[Knockback] INICIO:",
                defender.Name
            )

            task.delay(KNOCKBACK_DURATION, function()
                finishReaction(
                    defender,
                    humanoid,
                    state,
                    sequence
                )
            end)
        end
    )
end

-- ==========================================
-- RESOLUCAO FINAL DO GOLPE
-- ==========================================

function CombatHit.Apply(
    attacker,
    defender,
    attackName,
    damage,
    guardBreak
)
    local attackData =
        HitReactionData.Attacks[attackName]

    if not attackData then
        return false
    end

    local humanoid =
        defender:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    if attackData.Result ~= HitReactionData.Result.Hit then
        return false
    end

    -- Verifica o Guard antes de causar dano.
    local blocked = CombatGuard.Resolve(
        attacker,
        defender,
        attackName,
        guardBreak
    )

    if blocked then
        print(
            "[CombatHit] Golpe defendido:",
            attackName,
            "| Defensor:",
            defender.Name
        )

        return true
    end

    -- ==========================================
    -- INTERRUPCAO DO GUARD BREAK
    -- ==========================================

    -- Se o defensor estiver no Guard Break Stun,
    -- encerra esse estado antes de aplicar o golpe.
    -- O temporizador e a animacao sao cancelados.
    CombatStun.CancelGuardBreak(defender)

    -- ==========================================
    -- GOLPE NAO DEFENDIDO
    -- ==========================================

    humanoid:TakeDamage(damage)

    if humanoid.Health > 0 then
        if attackData.Reaction ==
            HitReactionData.Reaction.Stun then

            applyHitstun(defender, attackName)

        elseif attackData.Reaction ==
            HitReactionData.Reaction.Knockback then

            applyKnockback(
                attacker,
                defender,
                attackName
            )
        end
    end

    print(
        "[CombatHit]",
        attacker.Name,
        "->",
        defender.Name,
        "| Golpe:",
        attackName,
        "| Reacao:",
        attackData.Reaction,
        "| Dano:",
        damage
    )

    return true
end

return CombatHit
