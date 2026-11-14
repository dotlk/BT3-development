
-- GuardData.luau
-- Configuracoes compartilhadas do sistema de defesa
-- O servidor controla os segmentos e a regeneracao.

local GuardData = {
    MaxSegments = 4,

    GuardBreak = {
        Duration = 3.0,
        ChargeThreshold = 0.70,
    },

    Regen = {
        Enabled = true,
        Delay = 5.0,
        Interval = 2.0,
        Amount = 1,

        -- Nao regenera enquanto estiver defendendo.
        WhileGuarding = false,

        -- Nao regenera durante Guard Break.
        WhileBroken = false,
    },

    SegmentCosts = {
        Punch1 = 0,
        Punch2 = 0,
        Punch3 = 0,
        Finisher4 = 1,
        HeavyPunch = 1,
    },
}

return GuardData
