
-- CombatCamera
-- Camera terrestre com lock-on dinamico

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local dummy = Workspace:WaitForChild("TrainingDummy")

local MIN_DISTANCE = 12
local MAX_DISTANCE = 30
local BASE_DISTANCE = 10
local DISTANCE_PER_STUD = 0.55
local HEIGHT = 5
local FOCUS_HEIGHT = 2.5
local SMOOTHNESS = 7
local ROTATION_SMOOTHNESS = 12

local root = nil
local currentDistance = MIN_DISTANCE
local lastDirection = Vector3.new(0, 0, -1)

local function setupCharacter(character)
    root = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.AutoRotate = false
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

RunService:BindToRenderStep(
    "CombatCamera",
    Enum.RenderPriority.Camera.Value + 1,
    function(dt)
        local camera = Workspace.CurrentCamera
        local targetRoot = dummy:FindFirstChild("HumanoidRootPart")

        if not root or not root.Parent or not targetRoot then
            return
        end

        camera.CameraType = Enum.CameraType.Scriptable

        local playerPos = root.Position
        local targetPos = targetRoot.Position

        local offset = targetPos - playerPos
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)
        local separation = flatOffset.Magnitude

        if separation > 0.05 then
            lastDirection = flatOffset.Unit
        end

        local desiredDistance = math.clamp(
            BASE_DISTANCE + separation * DISTANCE_PER_STUD,
            MIN_DISTANCE,
            MAX_DISTANCE
        )

        local alpha = 1 - math.exp(-SMOOTHNESS * dt)
        local rotationAlpha = 1 - math.exp(-ROTATION_SMOOTHNESS * dt)

        currentDistance +=
            (desiredDistance - currentDistance) * alpha

        local cameraPos =
            playerPos
            - lastDirection * currentDistance
            + Vector3.new(0, HEIGHT, 0)

        local focusPos =
            playerPos:Lerp(targetPos, 0.35)
            + Vector3.new(0, FOCUS_HEIGHT, 0)

        local desiredCFrame = CFrame.lookAt(cameraPos, focusPos)

        camera.CFrame = camera.CFrame:Lerp(
            desiredCFrame,
            alpha
        )

        local desiredRootCFrame = CFrame.lookAt(
            playerPos,
            playerPos + lastDirection
        )

        root.CFrame = root.CFrame:Lerp(
            desiredRootCFrame,
            rotationAlpha
        )
    end
)
