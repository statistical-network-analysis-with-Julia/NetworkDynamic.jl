"""
    NetworkDynamic.jl - Dynamic Network Data Structures

Provides data structures for representing and manipulating dynamic (time-varying)
networks, including vertex/edge activity spells and time-varying attributes.

Port of the R networkDynamic package from the StatNet collection.
"""
module NetworkDynamic

using Dates
using Graphs
using Network

# Core types
export DynamicNetwork, Spell, TimeVaryingAttribute, ActivitySpell
export VertexSpell, EdgeSpell

# Spell operations
export add_spell!, remove_spell!, get_spells, merge_spells!
export is_active, get_activity_range, spell_overlap, spell_duration
export activate!, deactivate!, activate_vertices!, activate_edges!

# Network extraction
export network_extract, network_collapse, network_slice
export get_timing_info, get_network_attribute

# Time-varying attributes
export get_vertex_attribute_active, set_vertex_attribute_active!
export get_edge_attribute_active, set_edge_attribute_active!
export list_vertex_attributes_active, list_edge_attributes_active

# Query functions
export when_vertex, when_edge
export get_vertex_activity, get_edge_activity
export active_vertices, active_edges

# Utility
export as_dynamic_network, reconcile_activity!
export get_observation_period, set_observation_period!

"""
    Spell{T}

Represents an activity spell (time interval).

# Fields
- `onset::T`: Start time (inclusive)
- `terminus::T`: End time (exclusive by default)
- `onset_censored::Bool`: True if spell may have started earlier
- `terminus_censored::Bool`: True if spell may continue beyond terminus
"""
struct Spell{T}
    onset::T
    terminus::T
    onset_censored::Bool
    terminus_censored::Bool

    function Spell(onset::T, terminus::T;
                   onset_censored::Bool=false,
                   terminus_censored::Bool=false) where T
        onset <= terminus || throw(ArgumentError("onset must be <= terminus"))
        new{T}(onset, terminus, onset_censored, terminus_censored)
    end
end

# Convenience constructor for mixed numeric types
Spell(onset::S, terminus::T; kwargs...) where {S, T} =
    (P = promote_type(S, T); Spell(P(onset), P(terminus); kwargs...))

# Spell utilities
Base.:(==)(a::Spell, b::Spell) = a.onset == b.onset && a.terminus == b.terminus
Base.isless(a::Spell, b::Spell) = a.onset < b.onset || (a.onset == b.onset && a.terminus < b.terminus)
Base.hash(s::Spell, h::UInt) = hash((s.onset, s.terminus), h)

function Base.show(io::IO, s::Spell)
    cens_l = s.onset_censored ? "(" : "["
    cens_r = s.terminus_censored ? ")*" : ")"
    print(io, "Spell", cens_l, s.onset, ", ", s.terminus, cens_r)
end

# Is the spell active at the single time point `at`? Point (zero-duration)
# spells [t, t) are treated as instantaneous events active exactly at t,
# matching R networkDynamic semantics.
_spell_active_at(s::Spell, at) =
    (s.onset <= at < s.terminus) || (s.onset == s.terminus == at)

"""
    spell_overlap(s1::Spell, s2::Spell) -> Bool

Check if two spells overlap. Half-open interval semantics: touching spells
`[0,10)` and `[10,20)` do not overlap. Point (zero-duration) spells `[t,t)`
are instantaneous events: they overlap an interval containing `t` and
another point spell only at the identical time.
"""
function spell_overlap(s1::Spell{T}, s2::Spell{T}) where T
    p1 = s1.onset == s1.terminus
    p2 = s2.onset == s2.terminus
    if p1 && p2
        return s1.onset == s2.onset
    elseif p1
        return s2.onset <= s1.onset < s2.terminus
    elseif p2
        return s1.onset <= s2.onset < s1.terminus
    end
    return s1.onset < s2.terminus && s2.onset < s1.terminus
end

"""
    spell_duration(s::Spell) -> Number

Get the duration of a spell.
"""
spell_duration(s::Spell) = s.terminus - s.onset

"""
    TimeVaryingAttribute{T, Time, V}

An attribute that changes over time.
"""
struct TimeVaryingAttribute{Time, V}
    values::Vector{V}
    spells::Vector{Spell{Time}}

    function TimeVaryingAttribute{Time, V}() where {Time, V}
        new{Time, V}(V[], Spell{Time}[])
    end
end

"""
    DynamicNetwork{T,Time}

A network with time-varying structure (edges and vertices can appear/disappear).

# Type Parameters
- `T`: Vertex ID type
- `Time`: Time type (Float64, DateTime, etc.)

# Fields
- `network::Network{T}`: Base network structure (maximum set of vertices/edges)
- `vertex_spells::Dict{T, Vector{Spell{Time}}}`: Activity periods for vertices
- `edge_spells::Dict{Tuple{T,T}, Vector{Spell{Time}}}`: Activity periods for edges
- `vertex_tea::Dict{Tuple{T,Symbol}, TimeVaryingAttribute{Time}}`: Time-varying vertex attributes
- `edge_tea::Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute{Time}}`: Time-varying edge attributes
- `observation_period::Tuple{Time, Time}`: Overall observation window
"""
mutable struct DynamicNetwork{T<:Integer, Time}
    network::Network{T}
    vertex_spells::Dict{T, Vector{Spell{Time}}}
    edge_spells::Dict{Tuple{T,T}, Vector{Spell{Time}}}
    vertex_tea::Dict{Tuple{T,Symbol}, TimeVaryingAttribute{Time}}
    edge_tea::Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute{Time}}
    observation_period::Tuple{Time, Time}
    net_obs_period::Spell{Time}

    function DynamicNetwork{T, Time}(n::Int=0;
                                     observation_start=nothing,
                                     observation_end=nothing,
                                     directed::Bool=true) where {T<:Integer, Time}
        start = isnothing(observation_start) ? _default_obs_start(Time) :
                convert(Time, observation_start)
        stop = isnothing(observation_end) ? _default_obs_end(Time) :
               convert(Time, observation_end)
        net = Network{T}(; n=n, directed=directed)
        new{T, Time}(
            net,
            Dict{T, Vector{Spell{Time}}}(),
            Dict{Tuple{T,T}, Vector{Spell{Time}}}(),
            Dict{Tuple{T,Symbol}, TimeVaryingAttribute{Time}}(),
            Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute{Time}}(),
            (start, stop),
            Spell(start, stop)
        )
    end
end

DynamicNetwork(n::Int=0; kwargs...) = DynamicNetwork{Int, Float64}(n; kwargs...)

# Default observation windows per time type; DateTime/Date have no
# zero/one, so give them sensible calendar defaults
_default_obs_start(::Type{Time}) where Time<:Number = zero(Time)
_default_obs_end(::Type{Time}) where Time<:Number = one(Time)
_default_obs_start(::Type{DateTime}) = DateTime(0)
_default_obs_end(::Type{DateTime}) = DateTime(1)
_default_obs_start(::Type{Date}) = Date(0)
_default_obs_end(::Type{Date}) = Date(1)

function Base.show(io::IO, dnet::DynamicNetwork{T, Time}) where {T, Time}
    dir_str = is_directed(dnet) ? "directed" : "undirected"
    println(io, "DynamicNetwork{$T, $Time}: $dir_str dynamic network")
    println(io, "  Vertices: $(nv(dnet))")
    println(io, "  Edges (base): $(ne(dnet))")
    println(io, "  Observation period: $(dnet.observation_period)")
    n_vs = sum(length(v) for v in values(dnet.vertex_spells); init=0)
    n_es = sum(length(v) for v in values(dnet.edge_spells); init=0)
    print(io, "  Spells: $n_vs vertex, $n_es edge")
end

# Forward Graphs.jl interface to underlying network
Graphs.nv(dnet::DynamicNetwork) = nv(dnet.network)
Graphs.ne(dnet::DynamicNetwork) = ne(dnet.network)
Graphs.vertices(dnet::DynamicNetwork) = vertices(dnet.network)
Graphs.is_directed(dnet::DynamicNetwork) = is_directed(dnet.network)

"""
    get_observation_period(dnet::DynamicNetwork) -> Tuple

Get the observation period for the network.
"""
get_observation_period(dnet::DynamicNetwork) = dnet.observation_period

"""
    set_observation_period!(dnet::DynamicNetwork, start, stop)

Set the observation period for the network.
"""
function set_observation_period!(dnet::DynamicNetwork{T, Time}, start, stop) where {T, Time}
    start, stop = convert(Time, start), convert(Time, stop)
    dnet.observation_period = (start, stop)
    dnet.net_obs_period = Spell(start, stop)
    return dnet
end

# =============================================================================
# Spell Operations
# =============================================================================

"""
    add_spell!(dnet::DynamicNetwork, spell::Spell; vertex=nothing, edge=nothing)

Add an activity spell to a vertex or edge.
"""
function add_spell!(dnet::DynamicNetwork{T, Time}, spell::Spell{Time};
                    vertex::Union{Nothing, T}=nothing,
                    edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    if !isnothing(vertex)
        spells = get!(dnet.vertex_spells, vertex, Spell{Time}[])
        push!(spells, spell)
        sort!(spells)
    elseif !isnothing(edge)
        # Ensure edge exists in base network
        if !has_edge(dnet.network, edge[1], edge[2])
            add_edge!(dnet.network, edge[1], edge[2])
        end
        # Normalize edge direction for undirected networks
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        spells = get!(dnet.edge_spells, e, Spell{Time}[])
        push!(spells, spell)
        sort!(spells)
    else
        throw(ArgumentError("Must specify either vertex or edge"))
    end
    return dnet
end

"""
    activate!(dnet::DynamicNetwork, onset, terminus; vertex=nothing, edge=nothing)

Convenience function to add a spell from onset to terminus.
"""
function activate!(dnet::DynamicNetwork{T, Time}, onset, terminus;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    add_spell!(dnet, Spell(convert(Time, onset), convert(Time, terminus));
               vertex=vertex, edge=edge)
end

"""
    activate_vertices!(dnet::DynamicNetwork, vertices, onset, terminus)

Activate multiple vertices for a spell.
"""
function activate_vertices!(dnet::DynamicNetwork{T, Time}, verts::AbstractVector{T},
                            onset, terminus) where {T, Time}
    spell = Spell(convert(Time, onset), convert(Time, terminus))
    for v in verts
        add_spell!(dnet, spell; vertex=v)
    end
    return dnet
end

"""
    activate_edges!(dnet::DynamicNetwork, edges, onset, terminus)

Activate multiple edges for a spell.
"""
function activate_edges!(dnet::DynamicNetwork{T, Time}, edges::AbstractVector{Tuple{T,T}},
                         onset, terminus) where {T, Time}
    spell = Spell(convert(Time, onset), convert(Time, terminus))
    for e in edges
        add_spell!(dnet, spell; edge=e)
    end
    return dnet
end

"""
    remove_spell!(dnet::DynamicNetwork, spell::Spell; vertex=nothing, edge=nothing)

Remove a specific spell from a vertex or edge.
"""
function remove_spell!(dnet::DynamicNetwork{T, Time}, spell::Spell{Time};
                       vertex::Union{Nothing, T}=nothing,
                       edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    if !isnothing(vertex)
        if haskey(dnet.vertex_spells, vertex)
            filter!(s -> s != spell, dnet.vertex_spells[vertex])
        end
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        if haskey(dnet.edge_spells, e)
            filter!(s -> s != spell, dnet.edge_spells[e])
        end
    else
        throw(ArgumentError("Must specify either vertex or edge"))
    end
    return dnet
end

"""
    get_spells(dnet::DynamicNetwork; vertex=nothing, edge=nothing) -> Vector{Spell}

Get all activity spells for a vertex or edge.
"""
function get_spells(dnet::DynamicNetwork{T, Time};
                    vertex::Union{Nothing, T}=nothing,
                    edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    if !isnothing(vertex)
        return get(dnet.vertex_spells, vertex, Spell{Time}[])
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        return get(dnet.edge_spells, e, Spell{Time}[])
    else
        throw(ArgumentError("Must specify either vertex or edge"))
    end
end

"""
    merge_spells!(dnet::DynamicNetwork; vertex=nothing, edge=nothing)

Merge overlapping or adjacent spells for a vertex or edge. Censoring flags
are preserved: the merged spell keeps the onset censoring of the spell
supplying its onset and the terminus censoring of the spell supplying its
terminus.
"""
function merge_spells!(dnet::DynamicNetwork{T, Time};
                       vertex::Union{Nothing, T}=nothing,
                       edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    spells = get_spells(dnet; vertex=vertex, edge=edge)
    isempty(spells) && return dnet

    merged = _merge_spell_vector(spells)

    # Update storage
    if !isnothing(vertex)
        dnet.vertex_spells[vertex] = merged
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        dnet.edge_spells[e] = merged
    end

    return dnet
end

# Merge a (possibly unsorted) spell vector: sort, then coalesce
# overlapping/adjacent spells, propagating censoring flags.
function _merge_spell_vector(spells::Vector{Spell{Time}}) where Time
    sorted = sort(spells)
    merged = Spell{Time}[]
    current = sorted[1]

    for i in 2:length(sorted)
        s = sorted[i]
        if s.onset <= current.terminus
            # Overlap or adjacent — extend current, keeping the censoring
            # flag of whichever spell supplies the merged terminus
            if s.terminus > current.terminus
                term, term_cens = s.terminus, s.terminus_censored
            elseif s.terminus == current.terminus
                term = current.terminus
                term_cens = current.terminus_censored || s.terminus_censored
            else
                term, term_cens = current.terminus, current.terminus_censored
            end
            current = Spell(current.onset, term;
                            onset_censored=current.onset_censored,
                            terminus_censored=term_cens)
        else
            push!(merged, current)
            current = s
        end
    end
    push!(merged, current)

    return merged
end

# =============================================================================
# Activity Queries
# =============================================================================

"""
    is_active(dnet::DynamicNetwork, at::Time; vertex=nothing, edge=nothing) -> Bool

Check if a vertex or edge is active at a given time.
"""
const _NO_SPELLS = Dict{DataType, Vector}()
# Shared empty spell vector per time type; avoids allocating a fresh empty
# vector on every dictionary miss in hot query loops
_empty_spells(::Type{Time}) where Time =
    get!(_NO_SPELLS, Time, Spell{Time}[])::Vector{Spell{Time}}

function is_active(dnet::DynamicNetwork{T, Time}, at;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    at = convert(Time, at)
    if !isnothing(vertex)
        spells = get(dnet.vertex_spells, vertex, _empty_spells(Time))
        return any(_spell_active_at(s, at) for s in spells)
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        spells = get(dnet.edge_spells, e, _empty_spells(Time))
        return any(_spell_active_at(s, at) for s in spells)
    else
        throw(ArgumentError("Must specify either vertex or edge"))
    end
end

"""
    is_active(dnet::DynamicNetwork, onset, terminus; vertex=nothing, edge=nothing, rule=:any) -> Bool

Check if a vertex or edge is active during an interval.
Rule can be :any (active at any point) or :all (active throughout).
"""
function is_active(dnet::DynamicNetwork{T, Time}, onset, terminus;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing,
                   rule::Symbol=:any) where {T, Time}
    onset, terminus = convert(Time, onset), convert(Time, terminus)
    spells = get_spells(dnet; vertex=vertex, edge=edge)

    if rule == :any
        query = Spell(onset, terminus)
        return any(spell_overlap(s, query) for s in spells)
    elseif rule == :all
        # Must be continuously active throughout
        # Check if any spell contains the entire interval
        return any(s.onset <= onset && s.terminus >= terminus for s in spells)
    else
        throw(ArgumentError("rule must be :any or :all"))
    end
end

"""
    active_vertices(dnet::DynamicNetwork, at::Time) -> Vector

Get all vertices active at time `at`.
"""
function active_vertices(dnet::DynamicNetwork{T, Time}, at) where {T, Time}
    at = convert(Time, at)
    return [v for v in 1:nv(dnet) if is_active(dnet, at; vertex=T(v))]
end

"""
    active_edges(dnet::DynamicNetwork, at::Time) -> Vector{Tuple}

Get all edges active at time `at`.
"""
function active_edges(dnet::DynamicNetwork{T, Time}, at) where {T, Time}
    at = convert(Time, at)
    result = Tuple{T,T}[]
    for (edge, spells) in dnet.edge_spells
        if any(_spell_active_at(s, at) for s in spells)
            push!(result, edge)
        end
    end
    return result
end

"""
    get_activity_range(dnet::DynamicNetwork; vertex=nothing, edge=nothing) -> Tuple

Get the earliest onset and latest terminus for all spells.

Note: censored spells report their *observed* bounds, so with
`onset_censored`/`terminus_censored` spells this is the observed, not the
true, activity range.
"""
function get_activity_range(dnet::DynamicNetwork{T, Time};
                            vertex::Union{Nothing, T}=nothing,
                            edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    spells = get_spells(dnet; vertex=vertex, edge=edge)
    isempty(spells) && return nothing

    earliest = minimum(s.onset for s in spells)
    latest = maximum(s.terminus for s in spells)
    return (earliest, latest)
end

"""
    when_vertex(dnet::DynamicNetwork, v) -> Vector{Spell}

Get all activity spells for vertex v.
"""
when_vertex(dnet::DynamicNetwork{T, Time}, v::T) where {T, Time} = get_spells(dnet; vertex=v)

"""
    when_edge(dnet::DynamicNetwork, i, j) -> Vector{Spell}

Get all activity spells for edge (i, j).
"""
when_edge(dnet::DynamicNetwork{T, Time}, i::T, j::T) where {T, Time} = get_spells(dnet; edge=(i, j))

# =============================================================================
# Network Extraction
# =============================================================================

"""
    network_extract(dnet::DynamicNetwork, at::Time;
                    retain_all_vertices=false) -> Network

Extract a static network representing the state at time `at`.

With `retain_all_vertices=true`, all base vertices are kept (inactive ones
as isolates), so vertex IDs are stable across time slices. With the default
`retain_all_vertices=false`, inactive vertices are dropped and survivors
are renumbered densely to `1:k`; each extracted vertex's original ID is
recorded in the `:vertex_pid` vertex attribute (persistent ID, after R
networkDynamic's `vertex.pid`) so slices can still be aligned over time.

Static vertex and edge attributes are copied either way.
"""
function network_extract(dnet::DynamicNetwork{T, Time}, at;
                         retain_all_vertices::Bool=false) where {T, Time}
    at = convert(Time, at)
    edge_active = spells -> any(_spell_active_at(s, at) for s in spells)
    vert_active = v -> is_active(dnet, at; vertex=T(v))
    return _extract(dnet, vert_active, edge_active, retain_all_vertices)
end

"""
    network_extract(dnet::DynamicNetwork, onset::Time, terminus::Time;
                    rule=:any, retain_all_vertices=false) -> Network

Extract a static network representing activity during an interval
(`rule=:any`: active at any point; `rule=:all`: active throughout).
See the point-query method for `retain_all_vertices` and the `:vertex_pid`
attribute.
"""
function network_extract(dnet::DynamicNetwork{T, Time}, onset, terminus;
                         rule::Symbol=:any,
                         retain_all_vertices::Bool=false) where {T, Time}
    onset, terminus = convert(Time, onset), convert(Time, terminus)
    rule in (:any, :all) || throw(ArgumentError("rule must be :any or :all"))
    query = Spell(onset, terminus)
    edge_active = spells -> rule == :any ?
        any(spell_overlap(s, query) for s in spells) :
        any(s.onset <= onset && s.terminus >= terminus for s in spells)
    vert_active = v -> is_active(dnet, onset, terminus; vertex=T(v), rule=rule)
    return _extract(dnet, vert_active, edge_active, retain_all_vertices)
end

# Shared extraction machinery: `vert_active(v)` and `edge_active(spells)`
# decide inclusion; vertex/edge attributes are copied; original vertex IDs
# are preserved (retain_all_vertices) or recorded as :vertex_pid.
function _extract(dnet::DynamicNetwork{T, Time}, vert_active, edge_active,
                  retain_all_vertices::Bool) where {T, Time}
    n = nv(dnet.network)
    active_verts = [T(v) for v in 1:n if vert_active(v)]

    if retain_all_vertices
        old_to_new = Dict{T,T}(T(v) => T(v) for v in 1:n)
        extracted = Network{T}(; n=n, directed=is_directed(dnet.network))
    else
        old_to_new = Dict{T,T}(v => T(i) for (i, v) in enumerate(active_verts))
        extracted = Network{T}(; n=length(active_verts),
                               directed=is_directed(dnet.network))
        # Persistent IDs: map extracted vertices back to base-network IDs
        for (old_v, new_v) in old_to_new
            set_vertex_attribute!(extracted, :vertex_pid, new_v, old_v)
        end
    end

    active_set = Set(active_verts)

    # Add active edges (only between active endpoints) with attributes
    for ((i, j), spells) in dnet.edge_spells
        edge_active(spells) || continue
        (i in active_set && j in active_set) || continue
        ni, nj = old_to_new[i], old_to_new[j]
        add_edge!(extracted, ni, nj)
        for (attr_name, attr_dict) in dnet.network.edge_attrs
            key = is_directed(dnet.network) ? (i, j) : minmax(i, j)
            if haskey(attr_dict, key)
                set_edge_attribute!(extracted, attr_name, ni, nj, attr_dict[key])
            end
        end
    end

    # Copy static vertex attributes of surviving vertices (all vertices
    # survive when retain_all_vertices is set)
    for v in (retain_all_vertices ? [T(v) for v in 1:n] : active_verts)
        new_v = old_to_new[v]
        for (attr_name, attr_dict) in dnet.network.vertex_attrs
            if haskey(attr_dict, v)
                set_vertex_attribute!(extracted, attr_name, new_v, attr_dict[v])
            end
        end
    end

    return extracted
end

"""
    network_slice(dnet::DynamicNetwork, times::AbstractVector) -> Vector{Network}

Extract a sequence of static networks at specified time points.
"""
function network_slice(dnet::DynamicNetwork{T, Time}, times::AbstractVector;
                       kwargs...) where {T, Time}
    return [network_extract(dnet, t; kwargs...) for t in times]
end

"""
    network_collapse(dnet::DynamicNetwork; onset=nothing, terminus=nothing,
                     rule=:any) -> Network

Collapse the dynamic network to a static one. All base vertices are kept
(vertex IDs are stable); an edge is included if it was ever active — or,
when `onset`/`terminus` are given, if it was active in that interval under
`rule` (`:any` or `:all`). Static vertex and edge attributes are copied.
"""
function network_collapse(dnet::DynamicNetwork{T, Time};
                          onset=nothing, terminus=nothing,
                          rule::Symbol=:any) where {T, Time}
    edge_active = if isnothing(onset) || isnothing(terminus)
        spells -> !isempty(spells)
    else
        query = Spell(convert(Time, onset), convert(Time, terminus))
        rule == :any ?
            (spells -> any(spell_overlap(s, query) for s in spells)) :
            (spells -> any(s.onset <= query.onset && s.terminus >= query.terminus
                           for s in spells))
    end

    return _extract(dnet, _ -> true, edge_active, true)
end

"""
    get_timing_info(dnet::DynamicNetwork) -> NamedTuple

Get summary timing information about the dynamic network.
"""
function get_timing_info(dnet::DynamicNetwork{T, Time}) where {T, Time}
    all_onsets = Time[]
    all_termini = Time[]

    for spells in values(dnet.vertex_spells)
        for s in spells
            push!(all_onsets, s.onset)
            push!(all_termini, s.terminus)
        end
    end
    for spells in values(dnet.edge_spells)
        for s in spells
            push!(all_onsets, s.onset)
            push!(all_termini, s.terminus)
        end
    end

    if isempty(all_onsets)
        return (
            observation_period=dnet.observation_period,
            data_start=nothing,
            data_end=nothing,
            n_vertex_spells=0,
            n_edge_spells=0
        )
    end

    return (
        observation_period=dnet.observation_period,
        data_start=minimum(all_onsets),
        data_end=maximum(all_termini),
        n_vertex_spells=sum(length(v) for v in values(dnet.vertex_spells)),
        n_edge_spells=sum(length(v) for v in values(dnet.edge_spells))
    )
end

# =============================================================================
# Time-Varying Attributes
# =============================================================================

"""
    set_vertex_attribute_active!(dnet, v, attr, value, onset, terminus)

Set a time-varying vertex attribute.
"""
function set_vertex_attribute_active!(dnet::DynamicNetwork{T, Time}, v::T,
                                      attr::Symbol, value, onset, terminus) where {T, Time}
    key = (v, attr)
    if !haskey(dnet.vertex_tea, key)
        dnet.vertex_tea[key] = TimeVaryingAttribute{Time, typeof(value)}()
    end
    tea = dnet.vertex_tea[key]
    push!(tea.values, value)
    push!(tea.spells, Spell(convert(Time, onset), convert(Time, terminus)))
    return dnet
end

"""
    get_vertex_attribute_active(dnet, v, attr, at) -> value

Get the value of a time-varying vertex attribute at a specific time.
When several attribute spells cover `at`, the most recently set value wins.
"""
function get_vertex_attribute_active(dnet::DynamicNetwork{T, Time}, v::T,
                                     attr::Symbol, at) where {T, Time}
    at = convert(Time, at)
    key = (v, attr)
    !haskey(dnet.vertex_tea, key) && return nothing

    tea = dnet.vertex_tea[key]
    for i in reverse(eachindex(tea.spells))
        if _spell_active_at(tea.spells[i], at)
            return tea.values[i]
        end
    end
    return nothing
end

"""
    set_edge_attribute_active!(dnet, i, j, attr, value, onset, terminus)

Set a time-varying edge attribute.
"""
function set_edge_attribute_active!(dnet::DynamicNetwork{T, Time}, i::T, j::T,
                                    attr::Symbol, value, onset, terminus) where {T, Time}
    e = is_directed(dnet.network) ? (i, j) : (min(i, j), max(i, j))
    key = (e, attr)
    if !haskey(dnet.edge_tea, key)
        dnet.edge_tea[key] = TimeVaryingAttribute{Time, typeof(value)}()
    end
    tea = dnet.edge_tea[key]
    push!(tea.values, value)
    push!(tea.spells, Spell(convert(Time, onset), convert(Time, terminus)))
    return dnet
end

"""
    get_edge_attribute_active(dnet, i, j, attr, at) -> value

Get the value of a time-varying edge attribute at a specific time.
When several attribute spells cover `at`, the most recently set value wins.
"""
function get_edge_attribute_active(dnet::DynamicNetwork{T, Time}, i::T, j::T,
                                   attr::Symbol, at) where {T, Time}
    at = convert(Time, at)
    e = is_directed(dnet.network) ? (i, j) : (min(i, j), max(i, j))
    key = (e, attr)
    !haskey(dnet.edge_tea, key) && return nothing

    tea = dnet.edge_tea[key]
    for idx in reverse(eachindex(tea.spells))
        if _spell_active_at(tea.spells[idx], at)
            return tea.values[idx]
        end
    end
    return nothing
end

"""
    list_vertex_attributes_active(dnet::DynamicNetwork) -> Vector{Symbol}

List all time-varying vertex attribute names.
"""
function list_vertex_attributes_active(dnet::DynamicNetwork)
    return unique([key[2] for key in keys(dnet.vertex_tea)])
end

"""
    list_edge_attributes_active(dnet::DynamicNetwork) -> Vector{Symbol}

List all time-varying edge attribute names.
"""
function list_edge_attributes_active(dnet::DynamicNetwork)
    return unique([key[2] for key in keys(dnet.edge_tea)])
end

# =============================================================================
# Conversion and Reconciliation
# =============================================================================

"""
    as_dynamic_network(net::Network; onset=0.0, terminus=1.0) -> DynamicNetwork

Convert a static network to a dynamic network with all elements active
during the specified period. Mixed numeric `onset`/`terminus` types are
promoted (e.g. `onset=0, terminus=10.0` gives a `Float64` time axis);
`DateTime`/`Date` values give a calendar time axis.
"""
function as_dynamic_network(net::Network{T}; onset=0.0, terminus=1.0) where T
    Time = promote_type(typeof(onset), typeof(terminus))
    onset, terminus = convert(Time, onset), convert(Time, terminus)
    dnet = DynamicNetwork{T, Time}(Int(nv(net));
                                   observation_start=onset,
                                   observation_end=terminus,
                                   directed=is_directed(net))

    spell = Spell(onset, terminus)

    # Activate all vertices
    for v in 1:nv(net)
        add_spell!(dnet, spell; vertex=T(v))
    end

    # Activate all edges
    for e in edges(net)
        add_spell!(dnet, spell; edge=(T(src(e)), T(dst(e))))
    end

    return dnet
end

"""
    reconcile_activity!(dnet::DynamicNetwork)

Ensure edge activity is consistent with vertex activity.
Edges are only active when both endpoints are active.
"""
function reconcile_activity!(dnet::DynamicNetwork{T, Time}) where {T, Time}
    for (edge, edge_spells) in dnet.edge_spells
        i, j = edge
        v_spells_i = get(dnet.vertex_spells, i, Spell{Time}[])
        v_spells_j = get(dnet.vertex_spells, j, Spell{Time}[])

        # If no vertex spells defined, assume always active
        isempty(v_spells_i) && isempty(v_spells_j) && continue

        # Filter edge spells to times when both vertices are active
        new_spells = Spell{Time}[]
        for es in edge_spells
            for vs_i in (isempty(v_spells_i) ? [Spell(dnet.observation_period...)] : v_spells_i)
                for vs_j in (isempty(v_spells_j) ? [Spell(dnet.observation_period...)] : v_spells_j)
                    # Find intersection of all three spells
                    start = max(es.onset, vs_i.onset, vs_j.onset)
                    stop = min(es.terminus, vs_i.terminus, vs_j.terminus)
                    if start < stop
                        push!(new_spells, Spell(start, stop))
                    end
                end
            end
        end

        # The cartesian product can emit overlapping fragments; store a
        # sorted, merged spell set
        dnet.edge_spells[edge] = isempty(new_spells) ? new_spells :
                                 _merge_spell_vector(new_spells)
    end

    return dnet
end

end # module
