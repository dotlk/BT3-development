
-- CombatCollision.luau
-- Deteccao de volumes de impacto por ataque
-- Inspirado na separacao de colisao e resolucao do BT3

local Workspace = game:GetService("Workspace")

local CombatCollision = {}

local DEFAULT_SIZE = Vector3.new(4, 4, 4)
local DEFAULT_OFFSET = CFrame.new(0, 0, -2.5)

-- Retorna os personagens atingidos por um volume.
-- Nao aplica dano nem altera estados de combate.
function CombatCollision.Query(
    attackerCharacter: Model,
    size: Vector3?,
    offset: CFrame?
): {Model}

    local root = attackerCharacter:FindFirstChild(
        "HumanoidRootPart"
    )

    if not root or not root:IsA("BasePart") then
        return {}
    end

    local volumeSize = size or DEFAULT_SIZE
    local volumeOffset = offset or DEFAULT_OFFSET

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        attackerCharacter
    }

    local volumeCFrame = root.CFrame * volumeOffset

    local parts = Workspace:GetPartBoundsInBox(
        volumeCFrame,
        volumeSize,
        params
    )

    local targets = {}
    local seen = {}

    for _, part in ipairs(parts) do
        local model = part:FindFirstAncestorOfClass("Model")

        if model and not seen[model] then
            local humanoid =
                model:FindFirstChildOfClass("Humanoid")

            if humanoid and humanoid.Health > 0 then
                seen[model] = true
                table.insert(targets, model)
            end
        end
    end

    return targets
end

return CombatCollision
