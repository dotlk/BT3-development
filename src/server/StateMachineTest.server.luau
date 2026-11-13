
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateMachine = require(
    ReplicatedStorage.Shared.StateMachine
)

local fighter = StateMachine.new()

print("Estado inicial:", fighter:GetState())

print("Idle -> Attack:", fighter:Transition("Attack"))
print("Estado atual:", fighter:GetState())

print("Attack -> Dodge:", fighter:Transition("Dodge"))
print("Estado atual:", fighter:GetState())

print("Attack -> Recovery:", fighter:Transition("Recovery"))
print("Estado atual:", fighter:GetState())

print("Recovery -> Idle:", fighter:Transition("Idle"))
print("Estado final:", fighter:GetState())
