
-- CombatGuard.luau
-- Resolucao de defesa e Guard Break
-- Executado exclusivamente pelo servidor

local CombatStun = require(
    script.Parent:WaitForChild("CombatStun")
)

local CombatGuard = {}

local MAX_SEGMENTS = 4

local function isFrontal(attacker, defender)
    local attackerCharacter = attacker.Character

    local attackerRoot = attackerCharacter
        and attackerCharacter:FindFirstChild("HumanoidRootPart")

    local defenderRoot =
        defender:FindFirstChild("HumanoidRootPart")

    if not attackerRoot or not defenderRoot then
        return false
    end

    local offset = attackerRoot.Position - defenderRoot.Position

    local horizontal = Vector3.new(
        offset.X,
        0,
        offset.Z
    )

    if horizontal.Magnitude < 0.001 then
        return true
    end

    local look = defenderRoot.CFrame.LookVector

    local forward = Vector3.new(
        look.X,
        0,
        look.Z
    )

    if forward.Magnitude < 0.001 then
        return false
    end

    return forward.Unit:Dot(horizontal.Unit) >= 0
end

-- Retorna true quando o golpe foi resolvido pelo Guard.
function CombatGuard.Resolve(
    attacker,
    defender,
    attackName,
    guardBreak
)
    if defender:GetAttribute("Guarding") ~= true then
        return false
    end

    if defender:GetAttribute("GuardBroken") == true then
        return false
    end

    if defender:GetAttribute("CombatStunned") == true then
        return false
    end

    local humanoid =
        defender:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local segments = defender:GetAttribute("GuardSegments")

    if typeof(segments) ~= "number" then
        return false
    end

    segments = math.clamp(
        math.floor(segments),
        0,
        MAX_SEGMENTS
    )

    if segments <= 0 then
        return false
    end

    if not isFrontal(attacker, defender) then
        print("[Guard] Ataque pelas costas:", attackName)
        return false
    end

    -- Heavy suficientemente carregado quebra o Guard.
    if attackName == "HeavyPunch" and guardBreak == true then
        CombatStun.ApplyGuardBreak(defender, humanoid)
        return true
    end

    -- Golpes que consomem um segmento.
    if attackName == "Finisher4"
        or attackName == "HeavyPunch" then

        segments -= 1
        defender:SetAttribute("GuardSegments", segments)

        print(
            "[Guard] Bloqueado:",
            attackName,
            "| Segmentos restantes:",
            segments
        )

        if segments <= 0 then
            defender:SetAttribute("Guarding", false)
            print("[Guard] Defesa esgotada:", defender.Name)
        end

        return true
    end

    -- Socos leves nao consomem segmentos.
    if attackName == "Punch1"
        or attackName == "Punch2"
        or attackName == "Punch3" then

        print(
            "[Guard] Bloqueado sem custo:",
            attackName
        )

        return true
    end

    return false
end

return CombatGuard
