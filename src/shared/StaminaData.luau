
-- StaminaData.luau
-- Configuracoes compartilhadas de Stamina
-- O servidor e responsavel pela validacao real.

local StaminaData = {
    Max = 100,

    Costs = {
        Dash = 20,
        Roll = 40,
    },

    Cooldowns = {
        Dash = 0.25,
        Roll = 0.35,
    },

    Regen = {
        Delay = 3.0,
        Amount = 20,
        Interval = 5.0,
    },
}

return StaminaData
