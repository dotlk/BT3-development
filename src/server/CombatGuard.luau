
-- CombatGuard.luau
-- Resolucao de defesa e Guard Break
-- Executado exclusivamente pelo servidor

local CombatGuard = {}

local MAX_SEGMENTS = 4
local GUARD_BREAK_STUN = 1.0

local guardBreakTokens = setmetatable({}, {
    __mode = "k",
})

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

local function applyGuardBreak(defender, humanoid)
    local token = (guardBreakTokens[defender] or 0) + 1
    guardBreakTokens[defender] = token

    local walkSpeed = humanoid.WalkSpeed
    local jumpPower = humanoid.JumpPower
    local jumpHeight = humanoid.JumpHeight

    defender:SetAttribute("Guarding", false)
    defender:SetAttribute("GuardBroken", true)
    defender:SetAttribute("CombatStunned", true)

    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    print("[Guard] GUARD BREAK:", defender.Name)

    task.delay(GUARD_BREAK_STUN, function()
        if guardBreakTokens[defender] ~= token then
            return
        end

        if not defender.Parent or humanoid.Health <= 0 then
            return
        end

        defender:SetAttribute("GuardBroken", false)
        defender:SetAttribute("CombatStunned", false)

        humanoid.WalkSpeed = walkSpeed
        humanoid.JumpPower = jumpPower
        humanoid.JumpHeight = jumpHeight

        -- O Dummy volta a defender apos o Stun.
        -- Jogadores precisarao manter M2 pressionado
        -- quando integrarmos o Guard ao servidor.
        if defender.Name == "TrainingDummy"
            and (defender:GetAttribute("GuardSegments") or 0) > 0 then

            defender:SetAttribute("Guarding", true)
        end

        print("[Guard] FIM DO GUARD BREAK:", defender.Name)
    end)
end

-- Retorna true se o Guard resolveu o golpe.
-- Um Guard Break tambem conta como golpe resolvido.
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

    -- Heavy suficientemente carregado quebra o Guard
    if attackName == "HeavyPunch" and guardBreak == true then
        applyGuardBreak(defender, humanoid)
        return true
    end

    -- Golpes que consomem um segmento
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

    -- Socos leves nao consomem segmentos
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
