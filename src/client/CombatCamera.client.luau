-- CombatCamera
-- Câmera de combate inspirada no Budokai Tenkaichi 3

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local dummy = Workspace:WaitForChild("TrainingDummy")

local DISTANCE = 13
local HEIGHT = 5
local SMOOTHNESS = 10

local character
local root

local function setupCharacter(newCharacter)
	character = newCharacter
	root = character:WaitForChild("HumanoidRootPart")

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.AutoRotate = false
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
	setupCharacter(player.Character)
end

camera.CameraType = Enum.CameraType.Scriptable

RunService:BindToRenderStep(
	"CombatCamera",
	Enum.RenderPriority.Camera.Value + 1,
	function(dt)
		if not root or not root.Parent then
			return
		end

		local targetRoot = dummy:FindFirstChild("HumanoidRootPart")

		if not targetRoot then
			return
		end

		local playerPos = root.Position
		local targetPos = targetRoot.Position

		local direction = targetPos - playerPos
		direction = Vector3.new(direction.X, 0, direction.Z)

		if direction.Magnitude < 0.01 then
			return
		end

		direction = direction.Unit

		-- Posiciona a câmera atrás do personagem
		local cameraPos =
			playerPos
		- direction * DISTANCE
			+ Vector3.new(0, HEIGHT, 0)

		-- Olha para o espaço entre os combatentes
		local focusPos =
			playerPos:Lerp(targetPos, 0.35)
			+ Vector3.new(0, 2.5, 0)

		local desiredCFrame = CFrame.lookAt(
			cameraPos,
			focusPos
		)

		local alpha = 1 - math.exp(-SMOOTHNESS * dt)

		camera.CFrame = camera.CFrame:Lerp(
			desiredCFrame,
			alpha
		)

		-- Mantém o personagem olhando para o adversário
		root.CFrame = CFrame.lookAt(
			playerPos,
			playerPos + direction
		)
	end
)
