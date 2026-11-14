
-- TrainingDummyGuard.server.luau
-- Guard, segmentos e animacao congelada do Dummy

local Workspace = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")

local AnimationData = require(
    RS:WaitForChild("Shared"):WaitForChild("AnimationData")
)

local DUMMY_NAME = "TrainingDummy"
local MAX_GUARD = 4
local FADE_TIME = 0.12

local guardAnimation = AnimationData.Guard.Block

local function setupDummy(dummy)
    if not dummy:IsA("Model") then
        warn("[DummyGuard] TrainingDummy nao e um Model")
        return
    end

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

    local animationToken = 0

    local function freezeAnimation(token)
        task.spawn(function()
            local deadline = os.clock() + 3

            while token == animationToken
                and guardTrack.IsPlaying
                and guardTrack.Length <= 0
                and os.clock() < deadline do

                task.wait()
            end

            if token ~= animationToken
                or not guardTrack.IsPlaying
                or guardTrack.Length <= 0 then

                return
            end

            local freezeAt = math.clamp(
                guardAnimation.FreezeAt or 0.99,
                0,
                0.999
            )

            local targetPosition =
                guardTrack.Length * freezeAt

            while token == animationToken
                and guardTrack.IsPlaying
                and guardTrack.TimePosition < targetPosition do

                task.wait()
            end

            if token ~= animationToken
                or not guardTrack.IsPlaying then

                return
            end

            guardTrack.TimePosition = targetPosition
            guardTrack:AdjustSpeed(0)

            print("[DummyGuard] Pose final congelada")
        end)
    end

    local function updateAnimation()
        local guarding =
            dummy:GetAttribute("Guarding") == true

        local broken =
            dummy:GetAttribute("GuardBroken") == true

        local stunned =
            dummy:GetAttribute("CombatStunned") == true

        local canPlay =
            guarding
            and not broken
            and not stunned
            and humanoid.Health > 0

        if canPlay then
            if not guardTrack.IsPlaying then
                animationToken += 1

                guardTrack:Play(FADE_TIME)
                guardTrack:AdjustSpeed(
                    guardAnimation.Speed or 1
                )

                freezeAnimation(animationToken)
            end
        elseif guardTrack.IsPlaying then
            animationToken += 1
            guardTrack:Stop(FADE_TIME)
        end
    end

    -- ==========================================
    -- SEGMENTOS
    -- ==========================================

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
        animationToken += 1
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
