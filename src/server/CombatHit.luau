
-- CombatHit.luau
-- Resolucao de acertos, Hitstun e Knockback

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local shared = ReplicatedStorage:WaitForChild("Shared")

local HitReactionData = require(
    shared:WaitForChild("HitReactionData")
)

local AnimationData = require(
    shared:WaitForChild("AnimationData")
)

local CombatHit = {}

-- Configuracoes provisórias
local HITSTUN_DURATION = 0.25
local KNOCKBACK_DURATION = 0.55
local KNOCKBACK_SPEED = 35

local HIT_ANIMATIONS = {
    Punch1 = "Hit2",
    Punch2 = "Hit1",
    Punch3 = "Hit2",
    Finisher4 = "Knockback1",
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

    print("[HitReaction] Tracks preparados:", humanoid.Parent.Name)

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
    if not tracks then return end

    for _, track in pairs(tracks) do
        if track.IsPlaying then
            track:Stop(0.08)
        end
    end
end

local function playHitAnimation(humanoid, attackName)
    local reactionName = HIT_ANIMATIONS[attackName]
    if not reactionName then return end

    local tracks = prepareReactions(humanoid)
    local track = tracks[reactionName]

    if not track then
        warn("[HitReaction] Track nao encontrado:", reactionName)
        return
    end

    stopHitAnimation(humanoid)

    track:Play(0.05)
    track:AdjustSpeed(
        AnimationData.HitReactions[reactionName].Speed or 1
    )

    print("[HitReaction] Executando:", reactionName)
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

    defender:SetAttribute("CombatStunned", true)

    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    return state.Sequence
end

local function finishReaction(defender, humanoid, state, sequence)
    if state.Sequence ~= sequence then return end

    stopKnockback(state)

    if not humanoid.Parent then return end

    state.Active = false

    defender:SetAttribute("CombatStunned", false)

    humanoid.WalkSpeed = state.WalkSpeed
    humanoid.JumpPower = state.JumpPower
    humanoid.JumpHeight = state.JumpHeight

    stopHitAnimation(humanoid)

    print("[HitReaction] FIM:", defender.Name)
end

local function applyHitstun(defender, attackName)
    local humanoid = defender:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    local state = getReactionState(humanoid)
    stopKnockback(state)

    local sequence = beginReaction(defender, humanoid, state)

    print("[Hitstun] INICIO:", defender.Name)

    playHitAnimation(humanoid, attackName)

    task.delay(HITSTUN_DURATION, function()
        finishReaction(defender, humanoid, state, sequence)
    end)
end

local function applyKnockback(attacker, defender, attackName)
    local humanoid = defender:FindFirstChildOfClass("Humanoid")
    local root = defender:FindFirstChild("HumanoidRootPart")

    if not humanoid or humanoid.Health <= 0 or not root then
        return
    end

    local attackerCharacter = attacker.Character
    local attackerRoot = attackerCharacter
        and attackerCharacter:FindFirstChild("HumanoidRootPart")

    if not attackerRoot then return end

    local offset = root.Position - attackerRoot.Position
    local horizontal = Vector3.new(offset.X, 0, offset.Z)

    if horizontal.Magnitude < 0.001 then
        local look = attackerRoot.CFrame.LookVector
        horizontal = Vector3.new(look.X, 0, look.Z)
    end

    if horizontal.Magnitude < 0.001 then return end

    local direction = horizontal.Unit
    local state = getReactionState(humanoid)

    stopKnockback(state)

    local sequence = beginReaction(defender, humanoid, state)

    playHitAnimation(humanoid, attackName)

    local elapsed = 0

    -- Impulso horizontal com desaceleracao linear
    state.KnockbackConnection = RunService.Heartbeat:Connect(function(dt)
        if state.Sequence ~= sequence or not root.Parent then
            stopKnockback(state)
            return
        end

        elapsed += dt

        local progress = math.min(
            elapsed / KNOCKBACK_DURATION,
            1
        )

        local speed = KNOCKBACK_SPEED * (1 - progress)

        local currentVelocity = root.AssemblyLinearVelocity

        root.AssemblyLinearVelocity = Vector3.new(
            direction.X * speed,
            currentVelocity.Y,
            direction.Z * speed
        )

        if progress >= 1 then
            stopKnockback(state)
        end
    end)

    print("[Knockback] INICIO:", defender.Name)

    task.delay(KNOCKBACK_DURATION, function()
        finishReaction(defender, humanoid, state, sequence)
    end)
end

function CombatHit.Apply(attacker, defender, attackName, damage)
    local attackData = HitReactionData.Attacks[attackName]
    if not attackData then return false end

    local humanoid = defender:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    if attackData.Result ~= HitReactionData.Result.Hit then
        return false
    end

    humanoid:TakeDamage(damage)

    if humanoid.Health > 0 then
        if attackData.Reaction == HitReactionData.Reaction.Stun then
            applyHitstun(defender, attackName)

        elseif attackData.Reaction == HitReactionData.Reaction.Knockback then
            applyKnockback(attacker, defender, attackName)
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
