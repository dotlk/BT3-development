
-- StaminaHUD.client.luau
-- HUD minimalista: 5 quadrados brancos
-- Cada quadrado representa 20 de stamina
-- Sem animacoes de preenchimento

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==========================================
-- CONFIGURACOES
-- ==========================================

local STAMINA_MAX = 100
local SEGMENT_COUNT = 5
local SEGMENT_VALUE = 20

local SQUARE_SIZE = 15
local SQUARE_GAP = 6

local ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)
local INACTIVE_COLOR = Color3.fromRGB(40, 40, 40)

local BOTTOM_OFFSET = 35

-- ==========================================
-- GUI
-- ==========================================

local oldGui = playerGui:FindFirstChild("StaminaHUD")

if oldGui then
    oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StaminaHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local totalWidth =
    SEGMENT_COUNT * SQUARE_SIZE
    + (SEGMENT_COUNT - 1) * SQUARE_GAP

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -BOTTOM_OFFSET)
container.Size = UDim2.fromOffset(totalWidth, SQUARE_SIZE)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, SQUARE_GAP)
layout.Parent = container

-- ==========================================
-- QUADRADOS
-- ==========================================

local segments = {}

for i = 1, SEGMENT_COUNT do
    local square = Instance.new("Frame")
    square.Name = "Segment" .. i
    square.Size = UDim2.fromOffset(
        SQUARE_SIZE,
        SQUARE_SIZE
    )
    square.BackgroundColor3 = ACTIVE_COLOR
    square.BorderSizePixel = 0
    square.LayoutOrder = i
    square.Parent = container

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 2)
    corner.Parent = square

    segments[i] = square
end

-- ==========================================
-- ATUALIZACAO
-- ==========================================

local function updateHUD()
    local stamina =
        player:GetAttribute("QuickStepStamina")

    if typeof(stamina) ~= "number" then
        stamina = STAMINA_MAX
    end

    stamina = math.clamp(stamina, 0, STAMINA_MAX)

    local activeSegments = math.floor(
        stamina / SEGMENT_VALUE
    )

    for i, square in ipairs(segments) do
        local active = i <= activeSegments

        square.BackgroundColor3 =
            active and ACTIVE_COLOR or INACTIVE_COLOR
    end
end

player:GetAttributeChangedSignal(
    "QuickStepStamina"
):Connect(updateHUD)

updateHUD()

print("[StaminaHUD] HUD carregada")
