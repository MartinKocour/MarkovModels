# Implementation of a Finite State Machine (FSM)

#######################################################################
# Link

# This abstract type is not necessary conceptually but it is needed
# to cope with the circular dependency between Link / State
abstract type AbstractState end

"""
    struct Link{T} where T <: AbstractFloat
        dest
        weight
        label
    end

Weighted link pointing to a state `dest` with label `label`. `T` is
the type of the weight. The weight represents the log-probability of
going through this link.
"""
mutable struct Link{T<:AbstractFloat}
    src::AbstractState
    dest::AbstractState
    weight::T
end

#######################################################################
# State

"""
    InitStateID

A type with no fields whose singleton instance [`initstateid`](@ref)
is used to represent the identifier of an initial state in a graph.
"""
struct InitStateID end

"""
    initstateid

Singleton instance of type [`InitStateID`](@ref) representing the
identifier of an initial state in a graph.
"""
const initstateid = InitStateID()
Base.show(io::IO, id::InitStateID) = print(io, "initstateid")

"""
    FinalStateID

A type with no fields whose singleton instance [`finalstateid`](@ref)
is used to represent the identifier of a final state in a graph.
"""
struct FinalStateID end

"""
    finalstateid

Singleton instance of type [`FinalStateID`](@ref) representing the
identifier of a final state in a graph.
"""
const finalstateid = FinalStateID()
Base.show(io::IO, id::FinalStateID) = print(io, "finalstateid")

"""
    const StateID = Union{Int64, InitStateID, FinalStateID}

Type of the state identifier.
"""
const StateID = Union{Int64, InitStateID, FinalStateID}

"""
    const Label = Union{AbstractString, Nothing}

Type of the state label.
"""
const Label = Union{AbstractString, Nothing}

"""
    const Pdfindex = Union{Int64, Nothing}

Type of the state pdf index.
"""
const Pdfindex = Union{Int64, Nothing}

"""
    stuct State
        id
        pdfindex
        outgoing
        incoming
    end

State of a FSM.
  * `id` is the unique identifier of the state within a FSM.
  * `pdfindex` is the index of a probability density associated to the
     state. If the state is non-emitting, `pdfindex` is equal to
     `nothing`.
  * `outgoing` is a `Vector` of links leaving the state.
  * `incoming` is a `Vector` of links arriving to the state.

# Examples
```julia-repl
julia> State(1)
State(1)
julia> State(1, pdfindex = 2)
State(1, pdfindex = 2)
```

"""
struct State <: AbstractState
    id::StateID
    pdfindex::Union{Int64, Nothing}
    label::Union{AbstractString, Nothing}
end

function Base.show(
    io::IO,
    s::State
)
    str = "State($(s.id)"
    if ! isnothing(s.pdfindex) str = "$str, pdfindex = $(s.pdfindex)" end
    if ! isnothing(s.label) str = "$str, label = $(s.label)" end
    print(io, "$str)")
end

State(id; pdfindex = nothing, label = nothing) = State(id, pdfindex, label)

"""
    isemitting(state)

Returns `true` if the `state` is associated with a probability density.
"""
isemitting(s::State) = ! isnothing(s.pdfindex)

"""
    islabeled(state)

Returns `true` if the `state` has a label.
"""
islabeled(s::State) = ! isnothing(s.label)

#######################################################################
# FSM

mutable struct StateIDCounter
    count::Int64
end

struct FSM
    idcounter::StateIDCounter
    states::Dict{StateID, State}
    links::Dict{StateID, Vector{Link}}
    backwardlinks::Dict{StateID, Vector{Link}}

    FSM() = new(
        StateIDCounter(0),
        Dict{StateID, State}(
            initstateid => State(initstateid),
            finalstateid => State(finalstateid)
        ),
        Dict{StateID, Vector{Link}}(),
        Dict{StateID, Vector{Link}}(),
    )
end

#######################################################################
# Methods to construct the FSM

"""
    addstate!(fsm[, pdfindex = ..., label = "..."])

Add `state` to `fsm` and return it.
"""
function addstate!(
    fsm::FSM;
    id = nothing,
    pdfindex = nothing,
    label = nothing
)
    fsm.idcounter.count += 1
    s = State(fsm.idcounter.count, pdfindex, label)
    fsm.states[s.id] = s
end

"""
    removestate!(fsm, state)

Remove `state` from `fsm`.
"""
function removestate!(
    fsm::FSM,
    s::State
)
    # Remove all the connections of `s` before to remove it
    toremove = State[]
    for link in children(fsm, s) push!(toremove, link.dest) end
    for link in parents(fsm, s) push!(toremove, link.dest) end
    for s2 in toremove unlink!(fsm, s, s2) end

    delete!(fsm.states, s.id)
    delete!(fsm.links, s.id)
    delete!(fsm.backwardlinks, s.id)

    s
end

"""
    link!(state1, state2[, weight])

Add a weighted connection between `state1` and `state2`. By default,
`weight = 0`.
"""
function link!(
    fsm::FSM,
    s1::State,
    s2::State,
    weight::Real = 0.
)
    array = get(fsm.links, s1.id, Vector{Link}())
    push!(array, Link(s1, s2, weight))
    fsm.links[s1.id] = array

    array = get(fsm.backwardlinks, s2.id, Vector{Link}())
    push!(array, Link(s2, s1, weight))
    fsm.backwardlinks[s2.id] = array
end

"""
    unlink!(fsm, src, dest)

Remove all the connections between `src` and `dest` in `fsm`.
"""
function unlink!(
    fsm::FSM,
    s1::State,
    s2::State
)
    if s1.id ∈ keys(fsm.links) filter!(l -> l.dest.id ≠ s2.id, fsm.links[s1.id]) end
    if s2.id ∈ keys(fsm.links) filter!(l -> l.dest.id ≠ s1.id, fsm.links[s2.id]) end
    if s1.id ∈ keys(fsm.backwardlinks) filter!(l -> l.dest.id ≠ s2.id, fsm.backwardlinks[s1.id]) end
    if s2.id ∈ keys(fsm.backwardlinks) filter!(l -> l.dest.id ≠ s1.id, fsm.backwardlinks[s2.id]) end

    nothing
end

"""
    LinearFSM(seq, emissions_names)

Create a linear FSM from a sequence of label `seq`. `emissions_names`
should be a one-to-one mapping pdfindex -> label.
"""
function LinearFSM(
    sequence::AbstractArray{String},
    emissionsmap::Dict
)
    fsm = FSM()
    prevstate = initstate(fsm)
    for token in sequence
        s = addstate!(fsm, pdfindex = emissionsmap[token], label = token)
        link!(fsm, prevstate, s)
        prevstate = s
    end
    link!(fsm, prevstate, finalstate(fsm))
    fsm
end

#######################################################################
# Convenience function to access particular property/attribute of the
# FSM

"""
    initstate(fsm)

Returns the initial state of `fsm`.
"""
initstate(fsm::FSM) = fsm.states[initstateid]

"""
    finalstate(fsm)

Returns the final state of `fsm`.
"""
finalstate(fsm::FSM) = fsm.states[finalstateid]

#######################################################################
# Iterators

"""
    states(fsm)

Iterator over the state of `fsm`.
"""
states(fsm::FSM) = values(fsm.states)

struct LinkIterator
    fsm::FSM
    siter
end

function Base.iterate(
    iter::LinkIterator,
    iterstate = nothing
)
    # Initialize the state of the iterator.
    if iterstate == nothing
        state, siterstate = iterate(iter.siter)
        liter = get(iter.fsm.links, state.id, Vector{Link}())
        next = iterate(liter)
    else
        state, siterstate, liter, literstate = iterstate
        next = iterate(liter, literstate)
    end

    while next == nothing
        nextstate = iterate(iter.siter, siterstate)

        # Finished iterating over the states.
        # End the iterations.
        if nextstate == nothing return nothing end

        state, siterstate = nextstate
        liter = get(iter.fsm.links, state.id, Vector{Link}())
        next = iterate(liter)
    end

    link, literstate = next
    newliterstate = (state, siterstate, liter, literstate)

    return link, newliterstate
end

"""
    links(fsm)

Iterator over the links of the FSM.
"""
links(fsm::FSM) = LinkIterator(fsm, states(fsm))

"""
    children(fsm, state)

Iterator over the link to the children (i.e. next states) of `state`.
"""
children(fsm::FSM, state::State) = get(fsm.links, state.id, Vector{Link}())

"""
    parents(fsm, state)

Iterator over the link to the parents (i.e. previous states) of `state`.
"""
parents(fsm::FSM, state::State) = get(fsm.backwardlinks, state.id, Vector{Link}())

struct Forward end
const forward = Forward()

struct Backward end
const backward = Backward()

struct EmittingStatesIterator
    state::State
    getlinks::Function
end

function Base.iterate(
    iter::EmittingStatesIterator,
    queue = nothing
)
    if queue == nothing
        queue = Vector([(link, oftype(link.weight, 0.0))
                        for link in iter.getlinks(iter.state)])
    end

    hasfoundstate = false
    nextstate = weight = nothing
    while hasfoundstate ≠ true
        if isempty(queue) return nothing end
        s_w = nextemittingstates!(queue, iter.getlinks)
        if s_w ≠ nothing
            hasfoundstate = true
            nextstate, weight = s_w
        end
    end
    (nextstate, weight), queue
end

function nextemittingstates!(
    queue::Vector{Tuple{Link{T}, T}},
    getlinks::Function
) where T <: AbstractFloat

    link, pathweight = pop!(queue)
    if isemitting(link.dest)
        return link.dest, pathweight + link.weight
    end
    append!(queue, [(newlink, pathweight + link.weight)
                    for newlink in getlinks(link.dest)])
    return nothing
end

"""
    emittingstates(fsm, state, forward | backward)

Iterator over the next (forward) or previous (backward) emitting
states. For each value, the iterator return a tuple
`(nextstate, weightpath)`. The weight path is the sum of the weights
for all the link to reach `nextstate`.
"""
function emittingstates(
    fsm::FSM,
    s::State,
    ::Forward
)
    EmittingStatesIterator(s, st -> children(fsm, st))
end

function emittingstates(
    fsm::FSM,
    s::State,
    ::Backward
)
    EmittingStatesIterator(s, st -> parents(fsm, st))
end
