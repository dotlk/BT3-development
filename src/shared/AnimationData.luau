
-- AnimationData.luau
-- Configuracoes de animacoes, ataques e hitboxes

local AnimationData = {
    Heavy = {
        HoldThreshold = 0.20,
        ChargeDuration = 1.50,
        GuardBreakThreshold = 0.70,
        MinMultiplier = 1.20,
        MaxMultiplier = 3.00,
    },

    Guard = {
        Block = {
            Id = "rbxassetid://91707314777281",
            Priority = Enum.AnimationPriority.Action2,
            Looped = true,
            Speed = 1,
        },
    },

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
            Hitstop = 0.10,
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
            Hitstop = 0.20,
            Next = nil,
            Hitbox = {
                Size = Vector3.new(3.5, 3, 4),
                Offset = CFrame.new(0, 0, -2.5),
                Start = 0.80,
                Finish = 0.98,
            },
        },

        HeavyPunch = {
            Id = "rbxassetid://94704781008843",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 0.75,
            Duration = 0.50,
            Damage = 5,
            HitAt = 0.50,
            Hitstop = 0.60,
            Next = nil,
            Hitbox = {
                Size = Vector3.new(3, 3, 4),
                Offset = CFrame.new(0, 0, -2.5),
                Start = 0.40,
                Finish = 0.60,
            },
        },
    },

    HeavyAnimations = {
        HeavyCharge = {
            Id = "rbxassetid://99442157497018",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 0.65,
        },

        HeavyHold = {
            Id = "rbxassetid://102366748161716",
            Priority = Enum.AnimationPriority.Action,
            Looped = true,
            Speed = 0.20,
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

    Movement = {
        QuickDashForward = {
            Id = "rbxassetid://98744320846968",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },

        QuickDashBackward = {
            Id = "rbxassetid://109919687392363",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },

        QuickDashLeft = {
            Id = "rbxassetid://89319983315906",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },

        QuickDashRight = {
            Id = "rbxassetid://112780630414911",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },

        QuickRollLeft = {
            Id = "rbxassetid://80588873649646",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },

        QuickRollRight = {
            Id = "rbxassetid://116175498198155",
            Priority = Enum.AnimationPriority.Action,
            Looped = false,
            Speed = 1,
        },
    },
}

return AnimationData
