
-- CombatGuard.luau
-- Resolucao de defesa e Guard Break
-- Executado exclusivamente pelo servidor

local CombatStun = require(
    script.Parent:WaitForChild("CombatStun")
)

local GuardService = require(
    script.Parent:WaitForChild("GuardService")
)

local CombatGuard = {}

-- ==========================================
-- DIRECAO DO ATAQUE
-- ==========================================

local function isFrontal(attacker, defender)
    local attackerCharacter = attacker.Character

    local attackerRoot = attackerCharacter
        and attackerCharacter:FindFirstChild("HumanoidRootPart")

    local defenderRoot =
        defender:FindFirstChild("HumanoidRootPart")

    if not attackerRoot or not defenderRoot then
        return false
    end

    local offset =
        attackerRoot.Position - defenderRoot.Position

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

-- ==========================================
-- RESOLUCAO DO GUARD
-- ==========================================

function CombatGuard.Resolve(
    attacker,
    defender,
    attackName,
    guardBreak
)
    -- Verifica se o alvo esta defendendo.
    if not GuardService.IsGuarding(defender) then
        return false
    end

    local humanoid =
        defender:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    -- Ataques pelas costas ignoram o Guard.
    if not isFrontal(attacker, defender) then
        print(
            "[Guard] Ataque pelas costas:",
            attackName
        )

        return false
    end

    -- ======================================
    -- GUARD BREAK
    -- ======================================

    -- Heavy suficientemente carregado quebra
    -- a defesa sem consumir segmento.
    if attackName == "HeavyPunch"
        and guardBreak == true then

        CombatStun.ApplyGuardBreak(
            defender,
            humanoid
        )

        return true
    end

    -- ======================================
    -- BLOQUEIO NORMAL
    -- ======================================

    -- O GuardService controla os segmentos,
    -- o consumo e o temporizador de regen.
    local blocked = GuardService.Spend(
        defender,
        attackName
    )

    if not blocked then
        return false
    end

    local segments =
        GuardService.GetSegments(defender)

    print(
        "[Guard] Bloqueado:",
        attackName,
        "| Segmentos restantes:",
        segments
    )

    if segments <= 0 then
        print(
            "[Guard] Defesa esgotada:",
            defender.Name
        )
    end

    return true
end

return CombatGuard
