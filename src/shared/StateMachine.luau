
-- StateMachine.luau
-- Máquina de estados reutilizável para combate

local StateMachine = {}
StateMachine.__index = StateMachine

export type State =
    "Idle"
    | "Attack"
    | "Block"
    | "Dodge"
    | "Stun"
    | "Knockback"
    | "Recovery"

local TRANSITIONS = {
    Idle = {
        Attack = true,
        Block = true,
        Dodge = true,
        Stun = true,
        Knockback = true
    },

    Attack = {
        Idle = true,
        Stun = true,
        Knockback = true,
        Recovery = true
    },

    Block = {
        Idle = true,
        Stun = true,
        Knockback = true
    },

    Dodge = {
        Idle = true,
        Stun = true,
        Recovery = true
    },

    Stun = {
        Idle = true,
        Knockback = true,
        Recovery = true
    },

    Knockback = {
        Recovery = true
    },

    Recovery = {
        Idle = true,
        Stun = true,
        Knockback = true
    }
}

function StateMachine.new(initialState: State?)
    local self = setmetatable({}, StateMachine)

    self.CurrentState = initialState or "Idle"
    self.PreviousState = nil
    self.StateStartTime = os.clock()

    return self
end

function StateMachine:GetState(): State
    return self.CurrentState
end

function StateMachine:GetStateDuration(): number
    return os.clock() - self.StateStartTime
end

function StateMachine:CanTransition(newState: State): boolean
    local allowed = TRANSITIONS[self.CurrentState]

    if not allowed then
        return false
    end

    return allowed[newState] == true
end

function StateMachine:Transition(newState: State): boolean
    if not self:CanTransition(newState) then
        return false
    end

    self.PreviousState = self.CurrentState
    self.CurrentState = newState
    self.StateStartTime = os.clock()

    return true
end

function StateMachine:ForceState(newState: State)
    self.PreviousState = self.CurrentState
    self.CurrentState = newState
    self.StateStartTime = os.clock()
end

function StateMachine:Is(state: State): boolean
    return self.CurrentState == state
end

return StateMachine
