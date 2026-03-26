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

"""
    spell_overlap(s1::Spell, s2::Spell) -> Bool

Check if two spells overlap.
"""
function spell_overlap(s1::Spell{T}, s2::Spell{T}) where T
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
- `vertex_tea::Dict{Tuple{T,Symbol}, TimeVaryingAttribute}`: Time-varying vertex attributes
- `edge_tea::Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute}`: Time-varying edge attributes
- `observation_period::Tuple{Time, Time}`: Overall observation window
"""
mutable struct DynamicNetwork{T<:Integer, Time}
    network::Network{T}
    vertex_spells::Dict{T, Vector{Spell{Time}}}
    edge_spells::Dict{Tuple{T,T}, Vector{Spell{Time}}}
    vertex_tea::Dict{Tuple{T,Symbol}, TimeVaryingAttribute}
    edge_tea::Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute}
    observation_period::Tuple{Time, Time}
    net_obs_period::Spell{Time}

    function DynamicNetwork{T, Time}(n::Int=0;
                                     observation_start::Time=zero(Time),
                                     observation_end::Time=one(Time),
                                     directed::Bool=true) where {T<:Integer, Time}
        net = Network{T}(; n=n, directed=directed)
        new{T, Time}(
            net,
            Dict{T, Vector{Spell{Time}}}(),
            Dict{Tuple{T,T}, Vector{Spell{Time}}}(),
            Dict{Tuple{T,Symbol}, TimeVaryingAttribute}(),
            Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute}(),
            (observation_start, observation_end),
            Spell(observation_start, observation_end)
        )
    end
end

DynamicNetwork(n::Int=0; kwargs...) = DynamicNetwork{Int, Float64}(n; kwargs...)

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
function set_observation_period!(dnet::DynamicNetwork{T, Time}, start::Time, stop::Time) where {T, Time}
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
function activate!(dnet::DynamicNetwork{T, Time}, onset::Time, terminus::Time;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    add_spell!(dnet, Spell(onset, terminus); vertex=vertex, edge=edge)
end

"""
    activate_vertices!(dnet::DynamicNetwork, vertices, onset, terminus)

Activate multiple vertices for a spell.
"""
function activate_vertices!(dnet::DynamicNetwork{T, Time}, verts::AbstractVector{T},
                            onset::Time, terminus::Time) where {T, Time}
    spell = Spell(onset, terminus)
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
                         onset::Time, terminus::Time) where {T, Time}
    spell = Spell(onset, terminus)
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

Merge overlapping or adjacent spells for a vertex or edge.
"""
function merge_spells!(dnet::DynamicNetwork{T, Time};
                       vertex::Union{Nothing, T}=nothing,
                       edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    spells = get_spells(dnet; vertex=vertex, edge=edge)
    isempty(spells) && return dnet

    sort!(spells)
    merged = Spell{Time}[]
    current = spells[1]

    for i in 2:length(spells)
        if spells[i].onset <= current.terminus
            # Overlap or adjacent - extend current
            current = Spell(current.onset, max(current.terminus, spells[i].terminus))
        else
            push!(merged, current)
            current = spells[i]
        end
    end
    push!(merged, current)

    # Update storage
    if !isnothing(vertex)
        dnet.vertex_spells[vertex] = merged
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        dnet.edge_spells[e] = merged
    end

    return dnet
end

# =============================================================================
# Activity Queries
# =============================================================================

"""
    is_active(dnet::DynamicNetwork, at::Time; vertex=nothing, edge=nothing) -> Bool

Check if a vertex or edge is active at a given time.
"""
function is_active(dnet::DynamicNetwork{T, Time}, at::Time;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing) where {T, Time}
    if !isnothing(vertex)
        spells = get(dnet.vertex_spells, vertex, Spell{Time}[])
        return any(s.onset <= at < s.terminus for s in spells)
    elseif !isnothing(edge)
        e = is_directed(dnet.network) ? edge : (min(edge...), max(edge...))
        spells = get(dnet.edge_spells, e, Spell{Time}[])
        return any(s.onset <= at < s.terminus for s in spells)
    else
        throw(ArgumentError("Must specify either vertex or edge"))
    end
end

"""
    is_active(dnet::DynamicNetwork, onset, terminus; vertex=nothing, edge=nothing, rule=:any) -> Bool

Check if a vertex or edge is active during an interval.
Rule can be :any (active at any point) or :all (active throughout).
"""
function is_active(dnet::DynamicNetwork{T, Time}, onset::Time, terminus::Time;
                   vertex::Union{Nothing, T}=nothing,
                   edge::Union{Nothing, Tuple{T,T}}=nothing,
                   rule::Symbol=:any) where {T, Time}
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
function active_vertices(dnet::DynamicNetwork{T, Time}, at::Time) where {T, Time}
    return [v for v in 1:nv(dnet) if is_active(dnet, at; vertex=T(v))]
end

"""
    active_edges(dnet::DynamicNetwork, at::Time) -> Vector{Tuple}

Get all edges active at time `at`.
"""
function active_edges(dnet::DynamicNetwork{T, Time}, at::Time) where {T, Time}
    result = Tuple{T,T}[]
    for (edge, spells) in dnet.edge_spells
        if any(s.onset <= at < s.terminus for s in spells)
            push!(result, edge)
        end
    end
    return result
end

"""
    get_activity_range(dnet::DynamicNetwork; vertex=nothing, edge=nothing) -> Tuple

Get the earliest onset and latest terminus for all spells.
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
    network_extract(dnet::DynamicNetwork, at::Time) -> Network

Extract a static network representing the state at time `at`.
"""
function network_extract(dnet::DynamicNetwork{T, Time}, at::Time) where {T, Time}
    # Get active vertices
    n = nv(dnet.network)
    active_verts = [v for v in 1:n if is_active(dnet, at; vertex=T(v))]

    # Create mapping from old to new vertex IDs
    old_to_new = Dict(v => i for (i, v) in enumerate(active_verts))

    extracted = Network{T}(; n=length(active_verts), directed=is_directed(dnet.network))

    # Add active edges
    for ((i, j), spells) in dnet.edge_spells
        if any(s.onset <= at < s.terminus for s in spells)
            if haskey(old_to_new, i) && haskey(old_to_new, j)
                add_edge!(extracted, old_to_new[i], old_to_new[j])
            end
        end
    end

    # Copy static vertex attributes
    for v in active_verts
        new_v = old_to_new[v]
        for (attr_name, attr_dict) in dnet.network.vertex_attrs
            if haskey(attr_dict, v)
                set_vertex_attribute!(extracted, new_v, attr_name, attr_dict[v])
            end
        end
    end

    return extracted
end

"""
    network_extract(dnet::DynamicNetwork, onset::Time, terminus::Time; rule=:any) -> Network

Extract a static network representing activity during an interval.
"""
function network_extract(dnet::DynamicNetwork{T, Time}, onset::Time, terminus::Time;
                         rule::Symbol=:any) where {T, Time}
    n = nv(dnet.network)
    active_verts = [v for v in 1:n if is_active(dnet, onset, terminus; vertex=T(v), rule=rule)]

    old_to_new = Dict(v => i for (i, v) in enumerate(active_verts))

    extracted = Network{T}(; n=length(active_verts), directed=is_directed(dnet.network))

    for ((i, j), spells) in dnet.edge_spells
        query = Spell(onset, terminus)
        active = if rule == :any
            any(spell_overlap(s, query) for s in spells)
        else
            any(s.onset <= onset && s.terminus >= terminus for s in spells)
        end

        if active && haskey(old_to_new, i) && haskey(old_to_new, j)
            add_edge!(extracted, old_to_new[i], old_to_new[j])
        end
    end

    return extracted
end

"""
    network_slice(dnet::DynamicNetwork, times::AbstractVector) -> Vector{Network}

Extract a sequence of static networks at specified time points.
"""
function network_slice(dnet::DynamicNetwork{T, Time}, times::AbstractVector{Time}) where {T, Time}
    return [network_extract(dnet, t) for t in times]
end

"""
    network_collapse(dnet::DynamicNetwork; rule=:any) -> Network

Collapse dynamic network to static by including all vertices/edges that
were ever active.
"""
function network_collapse(dnet::DynamicNetwork{T, Time}; rule::Symbol=:any) where {T, Time}
    collapsed = Network{T}(; n=nv(dnet.network), directed=is_directed(dnet.network))

    for (edge, spells) in dnet.edge_spells
        if !isempty(spells)
            add_edge!(collapsed, edge[1], edge[2])
        end
    end

    return collapsed
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
                                      attr::Symbol, value, onset::Time, terminus::Time) where {T, Time}
    key = (v, attr)
    if !haskey(dnet.vertex_tea, key)
        dnet.vertex_tea[key] = TimeVaryingAttribute{Time, typeof(value)}()
    end
    tea = dnet.vertex_tea[key]
    push!(tea.values, value)
    push!(tea.spells, Spell(onset, terminus))
    return dnet
end

"""
    get_vertex_attribute_active(dnet, v, attr, at) -> value

Get the value of a time-varying vertex attribute at a specific time.
"""
function get_vertex_attribute_active(dnet::DynamicNetwork{T, Time}, v::T,
                                     attr::Symbol, at::Time) where {T, Time}
    key = (v, attr)
    !haskey(dnet.vertex_tea, key) && return nothing

    tea = dnet.vertex_tea[key]
    for (i, spell) in enumerate(tea.spells)
        if spell.onset <= at < spell.terminus
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
                                    attr::Symbol, value, onset::Time, terminus::Time) where {T, Time}
    e = is_directed(dnet.network) ? (i, j) : (min(i, j), max(i, j))
    key = (e, attr)
    if !haskey(dnet.edge_tea, key)
        dnet.edge_tea[key] = TimeVaryingAttribute{Time, typeof(value)}()
    end
    tea = dnet.edge_tea[key]
    push!(tea.values, value)
    push!(tea.spells, Spell(onset, terminus))
    return dnet
end

"""
    get_edge_attribute_active(dnet, i, j, attr, at) -> value

Get the value of a time-varying edge attribute at a specific time.
"""
function get_edge_attribute_active(dnet::DynamicNetwork{T, Time}, i::T, j::T,
                                   attr::Symbol, at::Time) where {T, Time}
    e = is_directed(dnet.network) ? (i, j) : (min(i, j), max(i, j))
    key = (e, attr)
    !haskey(dnet.edge_tea, key) && return nothing

    tea = dnet.edge_tea[key]
    for (idx, spell) in enumerate(tea.spells)
        if spell.onset <= at < spell.terminus
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
    as_dynamic_network(net::Network; onset, terminus) -> DynamicNetwork

Convert a static network to a dynamic network with all elements active
during the specified period.
"""
function as_dynamic_network(net::Network{T}; onset::Time=0.0, terminus::Time=1.0) where {T, Time}
    dnet = DynamicNetwork{T, typeof(onset)}(nv(net);
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

        dnet.edge_spells[edge] = new_spells
    end

    return dnet
end

end # module
