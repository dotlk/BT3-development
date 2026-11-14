
-- CombatStun.luau
-- Guard Break Stun com animacao unica
-- Pode ser interrompido por um golpe normal

local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationData = require(
    RS:WaitForChild("Shared"):WaitForChild("AnimationData")
)

local CombatStun = {}

local GUARD_BREAK_DURATION = 3
local FADE_TIME = 0.08

local active = setmetatable({}, {
    __mode = "k",
})

local function loadTrack(animator, data)
    local animation = Instance.new("Animation")
    animation.AnimationId = data.Id

    local track = animator:LoadAnimation(animation)
    track.Priority = data.Priority
    track.Looped = data.Looped

    animation:Destroy()

    return track
end

local function stopTracks(state)
    if state.LoopConnection then
        state.LoopConnection:Disconnect()
        state.LoopConnection = nil
    end

    for _, track in ipairs(state.Tracks) do
        track:Stop(FADE_TIME)
        track:Destroy()
    end

    table.clear(state.Tracks)
end

local function restoreMovement(state)
    local humanoid = state.Humanoid

    if not humanoid
        or not humanoid.Parent
        or humanoid.Health <= 0 then
        return
    end

    humanoid.WalkSpeed = state.WalkSpeed
    humanoid.JumpPower = state.JumpPower
    humanoid.JumpHeight = state.JumpHeight
    humanoid.AutoRotate = state.AutoRotate
end

local function finishStun(defender, state)
    if active[defender] ~= state then
        return
    end

    active[defender] = nil
    stopTracks(state)

    if not defender.Parent then
        return
    end

    defender:SetAttribute("GuardBroken", false)
    defender:SetAttribute("CombatStunned", false)

    restoreMovement(state)

    if defender.Name == "TrainingDummy"
        and state.Humanoid.Health > 0
        and (defender:GetAttribute("GuardSegments") or 0) > 0 then

        defender:SetAttribute("Guarding", true)
    end

    print("[CombatStun] FIM:", defender.Name)
end

local function playStunLoop(
    defender,
    humanoid,
    state,
    loopTrack,
    loopData
)
    local speed = math.max(loopData.Speed or 0.35, 0.01)
    local pauseAt = math.clamp(
        loopData.PauseAt or 0.50,
        0.01,
        0.99
    )
    local pauseDuration = math.max(
        loopData.PauseDuration or 0.45,
        0
    )

    local paused = false
    local resumeAt = 0
    local pauseUsedThisCycle = false
    local lastPosition = 0

    loopTrack:Play(FADE_TIME)
    loopTrack:AdjustSpeed(speed)

    state.LoopConnection =
        RunService.Heartbeat:Connect(function()
            if active[defender] ~= state
                or not loopTrack.IsPlaying
                or humanoid.Health <= 0 then

                if state.LoopConnection then
                    state.LoopConnection:Disconnect()
                    state.LoopConnection = nil
                end
                return
            end

            local length = loopTrack.Length

            if length <= 0 then
                return
            end

            local position = loopTrack.TimePosition
            local pausePosition = length * pauseAt

            if paused then
                if os.clock() >= resumeAt then
                    paused = false
                    loopTrack:AdjustSpeed(speed)
                end

                lastPosition = position
                return
            end

            if position < lastPosition then
                pauseUsedThisCycle = false
            end

            if not pauseUsedThisCycle
                and position >= pausePosition then

                pauseUsedThisCycle = true
                paused = true
                resumeAt = os.clock() + pauseDuration

                loopTrack.TimePosition = pausePosition
                loopTrack:AdjustSpeed(0)

                lastPosition = pausePosition
                return
            end

            lastPosition = position
        end)
end

function CombatStun.ApplyGuardBreak(defender, humanoid)
    if active[defender] then
        return
    end

    if not humanoid or humanoid.Health <= 0 then
        return
    end

    local state = {
        Humanoid = humanoid,
        WalkSpeed = humanoid.WalkSpeed,
        JumpPower = humanoid.JumpPower,
        JumpHeight = humanoid.JumpHeight,
        AutoRotate = humanoid.AutoRotate,
        Tracks = {},
        LoopConnection = nil,
    }

    active[defender] = state

    defender:SetAttribute("Guarding", false)
    defender:SetAttribute("GuardBroken", true)
    defender:SetAttribute("CombatStunned", true)

    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    humanoid.AutoRotate = false

    local animator =
        humanoid:FindFirstChildOfClass("Animator")

    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local loopData =
        AnimationData.HitReactions.GuardBreakStun

    if loopData then
        local loopTrack = loadTrack(animator, loopData)
        table.insert(state.Tracks, loopTrack)

        playStunLoop(
            defender,
            humanoid,
            state,
            loopTrack,
            loopData
        )
    else
        warn("[CombatStun] GuardBreakStun nao configurado")
    end

    print("[CombatStun] GUARD BREAK:", defender.Name)

    task.delay(GUARD_BREAK_DURATION, function()
        finishStun(defender, state)
    end)
end

-- Cancela somente o Guard Break.
-- Nao reativa a defesa porque um golpe vai assumir o controle.
function CombatStun.CancelGuardBreak(defender)
    local state = active[defender]

    if not state then
        return false
    end

    -- Invalida o temporizador anterior.
    active[defender] = nil

    stopTracks(state)

    defender:SetAttribute("GuardBroken", false)
    defender:SetAttribute("CombatStunned", false)
    defender:SetAttribute("Guarding", false)

    restoreMovement(state)

    print(
        "[CombatStun] GUARD BREAK INTERROMPIDO:",
        defender.Name
    )

    return true
end

return CombatStun
