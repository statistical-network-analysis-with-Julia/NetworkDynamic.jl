# Getting Started

This tutorial walks through common use cases for NetworkDynamic.jl, from creating dynamic networks to extracting snapshots and working with time-varying attributes.

## Installation

Install NetworkDynamic.jl from GitHub:

```julia
using Pkg
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/Network.jl")
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl")
```

## Basic Workflow

The typical NetworkDynamic.jl workflow consists of four steps:

1. **Create a dynamic network** - Define the base structure and observation period
2. **Add activity spells** - Specify when vertices and edges are active
3. **Query activity** - Check what is active at given times
4. **Extract snapshots** - Obtain static networks at specific time points

## Step 1: Create a Dynamic Network

A dynamic network wraps a static `Network` with temporal information:

```julia
using NetworkDynamic

# Create a directed dynamic network with 5 vertices
dnet = DynamicNetwork{Int, Float64}(5;
    observation_start=0.0,
    observation_end=100.0
)

# Simplified constructor (defaults to Int vertices, Float64 time)
dnet = DynamicNetwork(5;
    observation_start=0.0,
    observation_end=100.0
)
```

### Type Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `T` | Vertex ID type (`Int`, `Int32`) | `Int` |
| `Time` | Timestamp type (`Float64`, `DateTime`) | `Float64` |

### Constructor Options

| Option | Description | Default |
|--------|-------------|---------|
| `observation_start` | Start of observation window | `0.0` |
| `observation_end` | End of observation window | `1.0` |
| `directed` | Whether the network is directed | `true` |

```julia
# Undirected dynamic network
dnet = DynamicNetwork(10;
    observation_start=0.0,
    observation_end=50.0,
    directed=false
)
```

### Using DateTime

For calendar-based timestamps:

```julia
using Dates

dnet_dt = DynamicNetwork{Int, DateTime}(10;
    observation_start=DateTime(2024, 1, 1),
    observation_end=DateTime(2024, 12, 31)
)
```

## Step 2: Add Activity Spells

Activity spells define when vertices and edges are active.

### Activating Vertices

```julia
# Activate vertex 1 from time 0.0 to 50.0
activate!(dnet, 0.0, 50.0; vertex=1)

# Activate vertex 2 from time 0.0 to 100.0
activate!(dnet, 0.0, 100.0; vertex=2)

# Activate multiple vertices at once
activate_vertices!(dnet, [3, 4, 5], 0.0, 100.0)
```

### Activating Edges

```julia
# Activate edge from vertex 1 to vertex 2
activate!(dnet, 5.0, 30.0; edge=(1, 2))

# Activate edge from vertex 2 to vertex 3
activate!(dnet, 10.0, 50.0; edge=(2, 3))

# Activate multiple edges at once
activate_edges!(dnet, [(3, 4), (4, 5)], 20.0, 80.0)
```

### Multiple Spells

A vertex or edge can have multiple activity spells (e.g., intermittent activity):

```julia
# Vertex 1 is active in two separate periods
activate!(dnet, 0.0, 30.0; vertex=1)
activate!(dnet, 50.0, 80.0; vertex=1)

# Edge (1,2) is active intermittently
activate!(dnet, 5.0, 20.0; edge=(1, 2))
activate!(dnet, 40.0, 60.0; edge=(1, 2))
```

### Using Spell Objects Directly

For more control, create `Spell` objects:

```julia
# Create a spell with censoring information
s = Spell(0.0, 50.0; onset_censored=true)  # May have started earlier

# Add spell to vertex
add_spell!(dnet, s; vertex=1)

# Add spell to edge
add_spell!(dnet, Spell(10.0, 30.0); edge=(1, 2))
```

## Step 3: Query Activity

### Point Queries

Check if an element is active at a specific time:

```julia
# Is vertex 1 active at time 25?
is_active(dnet, 25.0; vertex=1)  # true

# Is edge (1,2) active at time 25?
is_active(dnet, 25.0; edge=(1, 2))  # depends on spells
```

### Interval Queries

Check activity during a time interval:

```julia
# Is vertex 1 active at ANY point during [10, 40]?
is_active(dnet, 10.0, 40.0; vertex=1, rule=:any)  # true

# Is vertex 1 active THROUGHOUT [10, 40]?
is_active(dnet, 10.0, 40.0; vertex=1, rule=:all)  # depends on spells
```

### Listing Active Elements

```julia
# Get all vertices active at time 25
active_verts = active_vertices(dnet, 25.0)
println("Active vertices: ", active_verts)

# Get all edges active at time 25
active_edgs = active_edges(dnet, 25.0)
println("Active edges: ", active_edgs)
```

### Retrieving Spells

```julia
# Get all spells for vertex 1
spells = get_spells(dnet; vertex=1)
for s in spells
    println("Active from $(s.onset) to $(s.terminus)")
end

# Convenience aliases
spells = when_vertex(dnet, 1)
spells = when_edge(dnet, 1, 2)
```

## Step 4: Extract Network Snapshots

### At a Single Time Point

```julia
using Network   # for nv/ne on the extracted static network

# Extract static network at time 25
snapshot = network_extract(dnet, 25.0)

# The result is a standard Network{Int}
println("Vertices: ", nv(snapshot))
println("Edges: ", ne(snapshot))
```

### Over a Time Interval

```julia
# Extract network with any activity during [10, 30]
snapshot_any = network_extract(dnet, 10.0, 30.0; rule=:any)

# Extract network active throughout [10, 30]
snapshot_all = network_extract(dnet, 10.0, 30.0; rule=:all)
```

### Sequence of Snapshots

```julia
# Extract snapshots at regular intervals
times = collect(0.0:10.0:100.0)
snapshots = network_slice(dnet, times)

for (t, snap) in zip(times, snapshots)
    println("t=$t: $(nv(snap)) vertices, $(ne(snap)) edges")
end
```

### Collapse to Static

```julia
# Get a static network with all ever-active elements
static = network_collapse(dnet)
println("Total ever-active edges: ", ne(static))
```

## Working with Time-Varying Attributes

### Setting Attributes

```julia
# Set a time-varying vertex attribute
set_vertex_attribute_active!(dnet, 1, :status, "susceptible", 0.0, 10.0)
set_vertex_attribute_active!(dnet, 1, :status, "infected", 10.0, 30.0)
set_vertex_attribute_active!(dnet, 1, :status, "recovered", 30.0, 100.0)

# Set a time-varying edge attribute
set_edge_attribute_active!(dnet, 1, 2, :weight, 1.0, 5.0, 20.0)
set_edge_attribute_active!(dnet, 1, 2, :weight, 2.5, 20.0, 50.0)
```

### Getting Attributes

```julia
# Get attribute at a specific time
status = get_vertex_attribute_active(dnet, 1, :status, 15.0)
println(status)  # "infected"

status = get_vertex_attribute_active(dnet, 1, :status, 35.0)
println(status)  # "recovered"

# Get edge attribute at a time
w = get_edge_attribute_active(dnet, 1, 2, :weight, 10.0)
println(w)  # 1.0
```

### Listing Available Attributes

```julia
# What time-varying vertex attributes exist?
attrs = list_vertex_attributes_active(dnet)
println("Vertex TEAs: ", attrs)

# What time-varying edge attributes exist?
edge_attrs = list_edge_attributes_active(dnet)
println("Edge TEAs: ", edge_attrs)
```

## Complete Example

```julia
using NetworkDynamic

# Create a small dynamic network representing a classroom
dnet = DynamicNetwork(5;
    observation_start=0.0,
    observation_end=60.0  # 60-minute class
)

# All students present for the full class
activate_vertices!(dnet, [1, 2, 3, 4, 5], 0.0, 60.0)

# Communication edges (who talks to whom and when)
activate!(dnet, 0.0, 15.0; edge=(1, 2))    # 1 talks to 2 early
activate!(dnet, 10.0, 30.0; edge=(2, 3))   # 2 talks to 3 mid-early
activate!(dnet, 20.0, 45.0; edge=(1, 3))   # 1 talks to 3 middle
activate!(dnet, 30.0, 55.0; edge=(3, 4))   # 3 talks to 4 mid-late
activate!(dnet, 40.0, 60.0; edge=(4, 5))   # 4 talks to 5 late
activate!(dnet, 5.0, 50.0; edge=(2, 1))    # 2 reciprocates 1

# Track discussion topic as a time-varying vertex attribute
for v in 1:5
    set_vertex_attribute_active!(dnet, v, :topic, "intro", 0.0, 20.0)
    set_vertex_attribute_active!(dnet, v, :topic, "main", 20.0, 45.0)
    set_vertex_attribute_active!(dnet, v, :topic, "conclusion", 45.0, 60.0)
end

# Extract snapshots at different points in the class
println("=== Beginning of class (t=5) ===")
snap1 = network_extract(dnet, 5.0)
println("Edges: ", ne(snap1))

println("\n=== Middle of class (t=30) ===")
snap2 = network_extract(dnet, 30.0)
println("Edges: ", ne(snap2))

println("\n=== End of class (t=55) ===")
snap3 = network_extract(dnet, 55.0)
println("Edges: ", ne(snap3))

# Summary information
info = get_timing_info(dnet)
println("\n=== Summary ===")
println("Observation period: ", info.observation_period)
println("Data range: $(info.data_start) to $(info.data_end)")
println("Vertex spells: ", info.n_vertex_spells)
println("Edge spells: ", info.n_edge_spells)
```

## Converting Between Static and Dynamic

### Static to Dynamic

```julia
using Network

# Create a static network
net = network(4; directed=true)
add_edge!(net, 1, 2)
add_edge!(net, 2, 3)
add_edge!(net, 3, 4)

# Convert to dynamic with all elements active from 0 to 100
dnet = as_dynamic_network(net; onset=0.0, terminus=100.0)
```

### Dynamic to Static

```julia
# Collapse to static (all ever-active elements)
static = network_collapse(dnet)

# Or extract at a specific time
static_at_50 = network_extract(dnet, 50.0)
```

## Ensuring Consistency

Edge activity should be consistent with vertex activity -- an edge can only be active when both endpoints are active:

```julia
# After modifying vertex spells, reconcile edge activity
reconcile_activity!(dnet)
```

## Best Practices

1. **Set the observation period**: Always specify `observation_start` and `observation_end`
2. **Activate vertices before edges**: Ensure endpoints are active before adding edge spells
3. **Use `reconcile_activity!`**: After modifying vertex spells, ensure edge consistency
4. **Merge overlapping spells**: Call `merge_spells!` to simplify spell lists
5. **Use appropriate time types**: `Float64` for abstract time, `DateTime` for calendar time
6. **Extract snapshots for analysis**: Use `network_extract` to get static networks for SNA functions

## Next Steps

- Learn about [Dynamic Networks](guide/dynamic_networks.md) in detail
- Understand [Spells and Activity](guide/spells.md) operations
- Master [Time Queries](guide/queries.md) for extracting and querying temporal data
