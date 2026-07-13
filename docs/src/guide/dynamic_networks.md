# Dynamic Networks

This guide covers the `DynamicNetwork` type in detail, including its structure, construction, and relationship to static networks.

## The DynamicNetwork Type

A `DynamicNetwork{T, Time}` wraps a static `Network{T}` with temporal information. It has two type parameters:

- `T`: The vertex ID type (typically `Int`)
- `Time`: The timestamp type (`Float64`, `DateTime`, `Date`, or any ordered type)

### Internal Structure

<!-- skip-check -->
```julia
mutable struct DynamicNetwork{T<:Integer, Time}
    network::Network{T}                                  # Base static network
    vertex_spells::Dict{T, Vector{Spell{Time}}}           # Vertex activity
    edge_spells::Dict{Tuple{T,T}, Vector{Spell{Time}}}    # Edge activity
    vertex_tea::Dict{Tuple{T,Symbol}, TimeVaryingAttribute}  # Vertex TEAs
    edge_tea::Dict{Tuple{Tuple{T,T},Symbol}, TimeVaryingAttribute}  # Edge TEAs
    observation_period::Tuple{Time, Time}                 # Observation window
    net_obs_period::Spell{Time}                           # Same as Spell
end
```

The underlying `network` field stores the **maximum** set of vertices and edges -- those that are ever active. Activity spells then restrict which elements exist at any given time.

## Creating Dynamic Networks

### Basic Construction

```julia
using NetworkDynamic

# Specify type parameters explicitly
dnet = DynamicNetwork{Int, Float64}(10;
    observation_start=0.0,
    observation_end=100.0
)

# Use defaults (Int vertices, Float64 time)
dnet = DynamicNetwork(10;
    observation_start=0.0,
    observation_end=100.0
)

# Empty network (0 vertices)
dnet = DynamicNetwork(;
    observation_start=0.0,
    observation_end=50.0
)
```

### Directed vs. Undirected

```julia
# Directed network (default)
dnet_dir = DynamicNetwork(5;
    observation_start=0.0,
    observation_end=10.0,
    directed=true
)

# Undirected network
dnet_undir = DynamicNetwork(5;
    observation_start=0.0,
    observation_end=10.0,
    directed=false
)
```

For undirected networks, edge keys are normalized so that `(min(i,j), max(i,j))` is always used. This means `activate!(dnet, 0.0, 5.0; edge=(3, 1))` and `activate!(dnet, 0.0, 5.0; edge=(1, 3))` refer to the same edge.

### With DateTime Timestamps

```julia
using Dates

dnet_dt = DynamicNetwork{Int, DateTime}(20;
    observation_start=DateTime(2024, 1, 1),
    observation_end=DateTime(2024, 12, 31)
)

# Add activity spells with DateTime
activate!(dnet_dt, DateTime(2024, 1, 1), DateTime(2024, 6, 30); vertex=1)
activate!(dnet_dt, DateTime(2024, 3, 1), DateTime(2024, 9, 30); edge=(1, 2))
```

### With Date Timestamps

```julia
using Dates

dnet_date = DynamicNetwork{Int, Date}(10;
    observation_start=Date(2024, 1, 1),
    observation_end=Date(2024, 12, 31)
)

activate!(dnet_date, Date(2024, 1, 1), Date(2024, 6, 30); vertex=1)
```

## The Observation Period

The observation period defines the overall time window for the network. It does not constrain spell activity (spells can extend beyond the observation period), but it provides context for analysis.

### Getting and Setting

```julia
# Get current observation period
period = get_observation_period(dnet)
println("Start: $(period[1]), End: $(period[2])")

# Update observation period
set_observation_period!(dnet, 0.0, 200.0)
```

### Timing Information

Get comprehensive timing statistics:

```julia
info = get_timing_info(dnet)

println("Observation period: ", info.observation_period)
println("Earliest data: ", info.data_start)
println("Latest data: ", info.data_end)
println("Vertex spells: ", info.n_vertex_spells)
println("Edge spells: ", info.n_edge_spells)
```

The `data_start` and `data_end` fields reflect the actual range of spell data, which may differ from the observation period.

## Graphs.jl Interface

`DynamicNetwork` forwards key Graphs.jl queries to its underlying `Network`:

```julia
using Graphs

nv(dnet)            # Total number of vertices (maximum set)
ne(dnet)            # Total number of edges (maximum set)
vertices(dnet)      # Iterate over all vertex IDs
is_directed(dnet)   # Check if directed
```

These operate on the **maximum** set of vertices and edges, not the active set at any particular time. To get the active set, use `network_extract`.

## Network Extraction

Network extraction produces a static `Network{T}` from a `DynamicNetwork` at a given time or during an interval.

### Point Extraction

```julia
# Static network at time 25.0
snapshot = network_extract(dnet, 25.0)

# Use with any Graphs.jl function
println("Active vertices: ", nv(snapshot))
println("Active edges: ", ne(snapshot))
println("Density: ", ne(snapshot) / (nv(snapshot) * (nv(snapshot) - 1)))
```

Vertices and edges are re-indexed in the extracted network. If vertices 2, 4, and 5 are active, they become vertices 1, 2, and 3 in the snapshot.

### Interval Extraction

```julia
# Any activity during [10, 30] -- union of active elements
snapshot_any = network_extract(dnet, 10.0, 30.0; rule=:any)

# Active throughout [10, 30] -- intersection
snapshot_all = network_extract(dnet, 10.0, 30.0; rule=:all)
```

The `:any` rule includes any element active at any point during the interval. The `:all` rule requires continuous activity throughout.

### Slice and Collapse

```julia
# Extract a sequence of snapshots
times = collect(0.0:5.0:50.0)
snapshots = network_slice(dnet, times)

# Collapse to static (union of all ever-active elements)
static = network_collapse(dnet)
```

## Converting from Static Networks

Convert an existing static `Network` to a `DynamicNetwork`:

```julia
using Networks

# Create static network
net = network(5; directed=true)
add_edge!(net, 1, 2)
add_edge!(net, 2, 3)
add_edge!(net, 3, 1)

# Convert: all elements active during [0, 100]
dnet = as_dynamic_network(net; onset=0.0, terminus=100.0)

# Verify
println("Vertex spells for v=1: ", get_spells(dnet; vertex=1))
println("Edge spells for (1,2): ", get_spells(dnet; edge=(1, 2)))
```

## Reconciling Activity

Edge activity should be consistent with vertex activity. An edge `(i, j)` can only be active when both vertices `i` and `j` are active. After modifying vertex spells, call `reconcile_activity!` to enforce this constraint:

```julia
# Initial setup
activate!(dnet, 0.0, 50.0; vertex=1)
activate!(dnet, 0.0, 100.0; vertex=2)
activate!(dnet, 0.0, 80.0; edge=(1, 2))

# Vertex 1 is only active until t=50, but edge (1,2) is marked active until t=80
# reconcile_activity! will trim the edge spell to [0, 50]
reconcile_activity!(dnet)

# After reconciliation, edge (1,2) is only active during [0, 50]
spells = get_spells(dnet; edge=(1, 2))
println(spells)  # Spell(0.0, 50.0)
```

### How Reconciliation Works

For each edge spell, the function computes the intersection with the vertex activity of both endpoints. If neither endpoint has vertex spells defined, the edge is assumed to be valid (vertices are always active).

```julia
# Example: Edge intersected with vertex activity
# Vertex 1: active [0, 30] and [50, 80]
# Vertex 2: active [10, 90]
# Edge (1,2): active [0, 100]
# After reconciliation: edge active [10, 30] and [50, 80]
#   (intersection of edge spell with both vertex spells)
```

## Building Dynamic Networks from Data

### From a List of Edges with Times

```julia
# Edge data: (source, target, onset, terminus)
edge_data = [
    (1, 2, 0.0, 10.0),
    (2, 3, 5.0, 15.0),
    (1, 3, 10.0, 20.0),
    (3, 4, 15.0, 25.0),
]

# Create network
n_vertices = 4
dnet = DynamicNetwork(n_vertices;
    observation_start=0.0,
    observation_end=30.0
)

# Activate all vertices for the full period
activate_vertices!(dnet, collect(1:n_vertices), 0.0, 30.0)

# Add edge spells
for (i, j, onset, terminus) in edge_data
    activate!(dnet, onset, terminus; edge=(i, j))
end
```

### From Panel Data (Discrete Time)

When you have a sequence of static networks at fixed time points:

```julia
using Networks
using Graphs: src, dst

# Suppose you have networks at times 1, 2, 3
net_t1 = network(10); add_edge!(net_t1, 1, 2)
net_t2 = network(10); add_edge!(net_t2, 1, 2); add_edge!(net_t2, 2, 3)
net_t3 = network(10); add_edge!(net_t3, 2, 3)
nets = [net_t1, net_t2, net_t3]
n = nv(nets[1])

dnet = DynamicNetwork(n;
    observation_start=1.0,
    observation_end=4.0  # one past last time point
)

# Activate all vertices for the full period
activate_vertices!(dnet, collect(1:n), 1.0, 4.0)

# Add edge spells from each time step
for (t, net) in enumerate(nets)
    for e in edges(net)
        activate!(dnet, Float64(t), Float64(t + 1); edge=(src(e), dst(e)))
    end
end

# Merge adjacent spells for edges that persist across time points
for ((i, j), _) in dnet.edge_spells
    merge_spells!(dnet; edge=(i, j))
end
```

## Memory and Performance

### Storage Considerations

- Each spell object stores onset, terminus, and two boolean flags
- Vertex spells are stored in a `Dict{T, Vector{Spell{Time}}}`
- Edge spells are stored in a `Dict{Tuple{T,T}, Vector{Spell{Time}}}`
- Time-varying attributes add additional storage per attribute per spell

### Performance Tips

1. **Merge spells**: Call `merge_spells!` to reduce the number of spell objects when overlapping spells accumulate
2. **Extract once**: If you need the same snapshot repeatedly, extract it once and reuse the `Network` object
3. **Use appropriate time types**: `Float64` is faster than `DateTime` for arithmetic
4. **Pre-allocate vertices**: Specify the vertex count at construction time rather than growing incrementally

## Printing and Inspection

```julia
# Basic info
println("Vertices: ", nv(dnet))
println("Edges: ", ne(dnet))
println("Directed: ", is_directed(dnet))
println("Observation: ", get_observation_period(dnet))

# Detailed timing
info = get_timing_info(dnet)
println("Data range: $(info.data_start) to $(info.data_end)")
println("Vertex spells: $(info.n_vertex_spells)")
println("Edge spells: $(info.n_edge_spells)")

# Inspect specific elements
for v in 1:nv(dnet)
    spells = when_vertex(dnet, v)
    if !isempty(spells)
        println("Vertex $v: ", spells)
    end
end
```
