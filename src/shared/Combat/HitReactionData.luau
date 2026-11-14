
-- HitReactionData.luau

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

HitReactionData.OriginalIds = {
    None = 1,
    NoFlinch = 2,
    Grab = 9,
    GrabB = 14,
}

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

    HeavyPunch = {
        Result = "Hit",
        Reaction = "Stun",
    },
}

return HitReactionData
