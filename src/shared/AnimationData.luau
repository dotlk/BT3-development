
-- AnimationData.luau
-- Configuracoes de animacoes, ataques e hitboxes

local AnimationData = {

    Combat = {

        Punch1 = {
            Id = "rbxassetid://76413761527862",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,

            Damage = 5,
            HitAt = 0.80,
            Hitstop = 0.05,
            Next = "Punch2",

            Hitbox = {
                Size = Vector3.new(2.5, 2.5, 3),
                Offset = CFrame.new(0, 0, -2),
                Start = 0.70,
                Finish = 0.90,
            },
        },

        Punch2 = {
            Id = "rbxassetid://133436694606914",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,

            Damage = 5,
            HitAt = 0.80,
            Hitstop = 0.05,
            Next = "Punch3",

            Hitbox = {
                Size = Vector3.new(2.5, 2.5, 3),
                Offset = CFrame.new(0, 0, -2),
                Start = 0.70,
                Finish = 0.90,
            },
        },

        Punch3 = {
            Id = "rbxassetid://74685345422777",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,

            Duration = 0.8,
            Transition = 0.55,

            Damage = 8,
            HitAt = 0.60,
            Hitstop = 0.65,
            Next = "Finisher4",

            Hitbox = {
                Size = Vector3.new(3, 3, 3.5),
                Offset = CFrame.new(0, 0, -2.3),
                Start = 0.50,
                Finish = 0.75,
            },
        },

        Finisher4 = {
            Id = "rbxassetid://99628362868936",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,

            Damage = 12,
            HitAt = 0.90,
            Hitstop = 0.60,
            Next = nil,

            Hitbox = {
                Size = Vector3.new(3.5, 3, 4),
                Offset = CFrame.new(0, 0, -2.5),
                Start = 0.80,
                Finish = 0.98,
            },
        },
    },

    HitReactions = {

        Hit1 = {
            Id = "rbxassetid://136878400855885",
            Priority = Enum.AnimationPriority.Action2,
            Looped = false,
            Speed = 1,
        },

        Hit2 = {
            Id = "rbxassetid://85466048474937",
            Priority = Enum.AnimationPriority.Action2,
            Looped = false,
            Speed = 1,
        },

        Knockback1 = {
            Id = "rbxassetid://128003370985305",
            Priority = Enum.AnimationPriority.Action2,
            Looped = false,
            Speed = 1,
        },
    },
}

return AnimationData
