
-- HeavyMeleeHUD.client.luau

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local config = require(
    RS:WaitForChild("Shared"):WaitForChild("AnimationData")
).Heavy

local gui = Instance.new("ScreenGui")
gui.Name = "HeavyMeleeHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.fromOffset(74, 240)
container.Position = UDim2.new(1, -100, 0.5, -120)
container.BackgroundTransparency = 1
container.Visible = false
container.Parent = gui

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromOffset(22, 190)
background.Position = UDim2.fromOffset(26, 15)
background.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
background.BackgroundTransparency = 0.15
background.BorderSizePixel = 0
background.Parent = container

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = background

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(180, 180, 180)
stroke.Thickness = 1
stroke.Parent = background

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.fromScale(0, 1)
fill.Size = UDim2.fromScale(1, 0)
fill.BackgroundColor3 = Color3.fromRGB(230, 230, 230)
fill.BorderSizePixel = 0
fill.Parent = background

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = fill

local threshold = Instance.new("Frame")
threshold.Name = "GuardBreakThreshold"
threshold.Size = UDim2.new(1, 10, 0, 2)
threshold.Position = UDim2.new(
    0, -5,
    1 - config.GuardBreakThreshold, 0
)
threshold.BackgroundColor3 = Color3.fromRGB(255, 180, 55)
threshold.BorderSizePixel = 0
threshold.ZIndex = 3
threshold.Parent = background

local multiplierLabel = Instance.new("TextLabel")
multiplierLabel.Size = UDim2.fromOffset(74, 25)
multiplierLabel.Position = UDim2.fromOffset(0, 208)
multiplierLabel.BackgroundTransparency = 1
multiplierLabel.TextColor3 = Color3.new(1, 1, 1)
multiplierLabel.TextScaled = true
multiplierLabel.Font = Enum.Font.GothamBold
multiplierLabel.Text = "x1.20"
multiplierLabel.Parent = container

local breakLabel = Instance.new("TextLabel")
breakLabel.Size = UDim2.fromOffset(100, 24)
breakLabel.Position = UDim2.fromOffset(-13, -12)
breakLabel.BackgroundTransparency = 1
breakLabel.TextColor3 = Color3.fromRGB(255, 190, 70)
breakLabel.TextScaled = true
breakLabel.Font = Enum.Font.GothamBold
breakLabel.Text = "GUARD BREAK"
breakLabel.Visible = false
breakLabel.Parent = container

RunService.RenderStepped:Connect(function()
    local character = player.Character

    if not character then
        container.Visible = false
        return
    end

    local charging = character:GetAttribute("HeavyCharging")
    container.Visible = charging == true

    if not charging then return end

    local charge = math.clamp(
        character:GetAttribute("HeavyCharge") or 0,
        0,
        1
    )

    local multiplier = config.MinMultiplier
        + (config.MaxMultiplier - config.MinMultiplier)
        * charge

    fill.Size = UDim2.fromScale(1, charge)

    local canBreak = charge >= config.GuardBreakThreshold

    fill.BackgroundColor3 = canBreak
        and Color3.fromRGB(255, 165, 45)
        or Color3.fromRGB(235, 235, 235)

    multiplierLabel.Text = string.format("x%.2f", multiplier)
    breakLabel.Visible = canBreak
end)
