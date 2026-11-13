
-- HitReactionData.luau
-- Estrutura inicial de reacoes inspirada no BT3
-- Os tempos serao definidos apos estudarmos
-- os handlers e registros de ataques originais

local HitReactionData = {}

HitReactionData.Result = {
    None = "None",
    NoFlinch = "NoFlinch",
    Hit = "Hit",
    Guard = "Guard",
    Dodge = "Dodge",
    Armor = "Armor",
    Clash = "Clash",
}

HitReactionData.Reaction = {
    Stun = "Stun",
    Knockback = "Knockback",
    Launch = "Launch",
    Knockdown = "Knockdown",
    Recovery = "Recovery",
}

-- IDs confirmados no codigo descompilado
HitReactionData.OriginalIds = {
    None = 1,
    NoFlinch = 2,
    Grab = 9,
    GrabB = 14,
}

-- Classificacao inicial para nosso prototipo.
-- Ainda nao representa a tabela exata de ataques do BT3.
HitReactionData.Attacks = {
    Punch1 = {
        Result = "Hit",
        Reaction = "Stun",
    },

    Punch2 = {
        Result = "Hit",
        Reaction = "Stun",
    },

    Punch3 = {
        Result = "Hit",
        Reaction = "Stun",
    },

    Finisher4 = {
        Result = "Hit",
        Reaction = "Knockback",
    },
}

return HitReactionData
