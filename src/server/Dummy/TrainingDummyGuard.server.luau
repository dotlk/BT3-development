
-- TrainingDummyGuard.server.luau
-- Configuracao, segmentos e animacao do Dummy

local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationData = require(
    RS:WaitForChild("Shared"):WaitForChild("AnimationData")
)

local DUMMY_NAME = "TrainingDummy"
local MAX_GUARD = 4
local FADE_TIME = 0.12

local guardAnimation = AnimationData.Guard.Block

local initialized = setmetatable({}, {
    __mode = "k",
})

local function setupDummy(dummy)
    if not dummy:IsA("Model") then
        return
    end

    if initialized[dummy] then
        return
    end

    initialized[dummy] = true

    local humanoid = dummy:WaitForChild("Humanoid")

    local animator =
        humanoid:FindFirstChildOfClass("Animator")

    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- ==========================================
    -- ATRIBUTOS
    -- ==========================================

    dummy:SetAttribute("Guarding", true)
    dummy:SetAttribute("GuardSegments", MAX_GUARD)
    dummy:SetAttribute("GuardMaxSegments", MAX_GUARD)
    dummy:SetAttribute("GuardBroken", false)

    humanoid.WalkSpeed = 0

    -- ==========================================
    -- ANIMACAO
    -- ==========================================

    local animation = Instance.new("Animation")
    animation.AnimationId = guardAnimation.Id

    local guardTrack = animator:LoadAnimation(animation)

    guardTrack.Priority = guardAnimation.Priority
    guardTrack.Looped = false

    animation:Destroy()

    local guardFrozen = false
    local guardStartedAt = 0
    local guardDuration = 0

    local function canGuard()
        return dummy:GetAttribute("Guarding") == true
            and dummy:GetAttribute("GuardBroken") ~= true
            and dummy:GetAttribute("CombatStunned") ~= true
            and humanoid.Health > 0
    end

    local function updateAnimation()
        if canGuard() then
            if not guardTrack.IsPlaying then
                guardFrozen = false
                guardDuration = 0
                guardStartedAt = os.clock()

                guardTrack:Play(FADE_TIME)
                guardTrack:AdjustSpeed(
                    guardAnimation.Speed or 1
                )

                print("[DummyGuard] Animacao iniciada")
            end
        else
            guardFrozen = false
            guardDuration = 0

            if guardTrack.IsPlaying then
                guardTrack:Stop(FADE_TIME)
            end
        end
    end

    local function updateSegments()
        local segments =
            dummy:GetAttribute("GuardSegments")

        if typeof(segments) ~= "number" then
            return
        end

        segments = math.clamp(
            math.floor(segments),
            0,
            MAX_GUARD
        )

        if dummy:GetAttribute("GuardSegments") ~= segments then
            dummy:SetAttribute("GuardSegments", segments)
            return
        end

        if segments <= 0 then
            dummy:SetAttribute("Guarding", false)
            print("[DummyGuard] Defesa esgotada")
        end

        updateAnimation()
    end

    -- ==========================================
    -- CONGELAMENTO DA ANIMACAO
    -- ==========================================

    local heartbeatConnection

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not dummy.Parent or humanoid.Health <= 0 then
            if heartbeatConnection then
                heartbeatConnection:Disconnect()
                heartbeatConnection = nil
            end
            return
        end

        if not canGuard() or guardFrozen then
            return
        end

        if guardTrack.Length <= 0 then
            return
        end

        local freezeAt = math.clamp(
            guardAnimation.FreezeAt or 0.95,
            0.05,
            0.98
        )

        local speed = math.max(
            guardAnimation.Speed or 1,
            0.01
        )

        local targetPosition =
            guardTrack.Length * freezeAt

        if guardDuration <= 0 then
            guardDuration = targetPosition / speed
        end

        local elapsed = os.clock() - guardStartedAt

        if elapsed >= guardDuration then
            if not guardTrack.IsPlaying then
                guardTrack:Play(0, 1, 0)
            end

            guardTrack.TimePosition = targetPosition
            guardTrack:AdjustSpeed(0)

            guardFrozen = true

            print("[DummyGuard] Pose congelada")
        end
    end)

    -- ==========================================
    -- EVENTOS
    -- ==========================================

    dummy:GetAttributeChangedSignal(
        "Guarding"
    ):Connect(updateAnimation)

    dummy:GetAttributeChangedSignal(
        "GuardBroken"
    ):Connect(updateAnimation)

    dummy:GetAttributeChangedSignal(
        "CombatStunned"
    ):Connect(updateAnimation)

    dummy:GetAttributeChangedSignal(
        "GuardSegments"
    ):Connect(updateSegments)

    humanoid.Died:Connect(function()
        guardFrozen = false
        guardTrack:Stop(0)
    end)

    updateSegments()
    updateAnimation()

    print(
        "[DummyGuard] Preparado:",
        MAX_GUARD,
        "segmentos | Animacao:",
        guardAnimation.Id
    )
end

local dummy = Workspace:FindFirstChild(DUMMY_NAME)

if dummy then
    setupDummy(dummy)
end

Workspace.ChildAdded:Connect(function(child)
    if child.Name == DUMMY_NAME then
        setupDummy(child)
    end
end)
