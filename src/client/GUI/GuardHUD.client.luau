
-- GuardHUD.client.luau
-- HUD minimalista de quatro segmentos

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SEGMENT_COUNT = 4
local SQUARE_SIZE = 15
local SQUARE_GAP = 6

local ACTIVE_COLOR = Color3.fromRGB(255, 179, 0)
local INACTIVE_COLOR = Color3.fromRGB(40, 40, 40)
local BROKEN_COLOR = Color3.fromRGB(230, 95, 75)

-- A StaminaHUD fica a 35 pixels da borda inferior.
local BOTTOM_OFFSET = 8

local oldGui = playerGui:FindFirstChild("GuardHUD")
if oldGui then
    oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GuardHUD"
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
container.Position = UDim2.new(
    0.5, 0,
    1, -BOTTOM_OFFSET
)
container.Size = UDim2.fromOffset(
    totalWidth,
    SQUARE_SIZE
)
container.BackgroundTransparency = 1
container.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, SQUARE_GAP)
layout.Parent = container

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

local connections = {}

local function disconnectCharacter()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end

    table.clear(connections)
end

local function updateHUD()
    local character = player.Character
    local count = SEGMENT_COUNT
    local broken = false

    if character then
        local value = character:GetAttribute("GuardSegments")

        if typeof(value) == "number" then
            count = math.clamp(
                math.floor(value),
                0,
                SEGMENT_COUNT
            )
        end

        broken =
            character:GetAttribute("GuardBroken") == true
    end

    for i, square in ipairs(segments) do
        if broken then
            square.BackgroundColor3 = BROKEN_COLOR
        elseif i <= count then
            square.BackgroundColor3 = ACTIVE_COLOR
        else
            square.BackgroundColor3 = INACTIVE_COLOR
        end
    end
end

local function setupCharacter(character)
    disconnectCharacter()

    table.insert(
        connections,
        character:GetAttributeChangedSignal(
            "GuardSegments"
        ):Connect(updateHUD)
    )

    table.insert(
        connections,
        character:GetAttributeChangedSignal(
            "GuardBroken"
        ):Connect(updateHUD)
    )

    updateHUD()
end

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end

print("[GuardHUD] HUD carregada")
