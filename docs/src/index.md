# NetworkDynamic.jl

*Dynamic Network Data Structures for Julia*

A Julia package for representing and manipulating dynamic (time-varying) networks with activity spells, time-varying attributes, and network extraction at any point in time.

## Overview

Dynamic networks are networks whose structure changes over time. Vertices and edges can appear and disappear, and attributes can vary across the observation period. NetworkDynamic.jl provides the data structures needed to represent, query, and manipulate such networks.

NetworkDynamic.jl is a port of the R [networkDynamic](https://cran.r-project.org/package=networkDynamic) package from the [StatNet](https://statnet.org/) collection.

### What is a Dynamic Network?

A dynamic network is a network where the set of active vertices and edges changes over time. Each vertex and edge has one or more **activity spells** -- time intervals during which it is active:

```text
Vertex 1:  |=====|     |====|
Vertex 2:  |================|
Edge 1-2:     |===|     |==|
             ──────────────────→ time
             0    5    10   15
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Dynamic Network** | A network with time-varying structure and attributes |
| **Spell** | A time interval `[onset, terminus)` during which an element is active |
| **Activity** | Whether a vertex or edge exists at a given time |
| **Network Extraction** | Obtaining a static snapshot of the network at a point in time |
| **Time-Varying Attribute** | A vertex or edge attribute whose value changes over time |
| **Observation Period** | The overall time window during which the network is observed |

### Applications

Dynamic network data structures are foundational for:

- **Temporal ERGM (TERGM)**: Statistical models for network evolution
- **Temporal SNA (TSNA)**: Descriptive analysis of network dynamics
- **Network visualization**: Animating networks over time (NDTV)
- **Epidemiology**: Modeling disease spread through time-varying contacts
- **Organizational studies**: Tracking collaboration network evolution
- **Online platforms**: Modeling evolving user interaction networks

## Features

- **Activity spells**: Track when vertices and edges are active with `Spell` objects
- **Time-varying attributes**: Store attributes that change over time
- **Network extraction**: Extract static network snapshots at any time point or over intervals
- **Spell operations**: Add, remove, merge, and query activity spells
- **Graphs.jl integration**: Built on Network.jl, which implements the Graphs.jl interface
- **Flexible timestamps**: Supports `Float64`, `DateTime`, `Date`, and other ordered types
- **Conversion utilities**: Convert between static and dynamic networks

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/Network.jl")
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl")
```

Or for development:

```julia
using Pkg
Pkg.develop(path="/path/to/NetworkDynamic.jl")
```

## Quick Start

```julia
using NetworkDynamic

# Create a dynamic network with 5 vertices
dnet = DynamicNetwork{Int, Float64}(5;
    observation_start=0.0,
    observation_end=10.0
)

# Activate vertices during specific time intervals
activate!(dnet, 0.0, 8.0; vertex=1)
activate!(dnet, 0.0, 10.0; vertex=2)
activate!(dnet, 2.0, 10.0; vertex=3)

# Activate edges
activate!(dnet, 1.0, 5.0; edge=(1, 2))
activate!(dnet, 3.0, 7.0; edge=(2, 3))

# Query activity at a time point
is_active(dnet, 2.0; edge=(1, 2))  # true
is_active(dnet, 6.0; edge=(1, 2))  # false

# Extract a static snapshot at time 4.0
snapshot = network_extract(dnet, 4.0)

# Get timing information
info = get_timing_info(dnet)
println("Vertex spells: ", info.n_vertex_spells)
println("Edge spells: ", info.n_edge_spells)
```

## Relationship to Other Packages

| Package | Role |
|---------|------|
| **Network.jl** | Static network data structure (dependency) |
| **NetworkDynamic.jl** | Dynamic network data structure (this package) |
| **TERGM.jl** | Temporal ERGM models (uses NetworkDynamic for data) |
| **TSNA.jl** | Temporal SNA descriptive analysis (uses NetworkDynamic for data) |
| **NDTV.jl** | Network visualization and animation |

## Documentation

```@contents
Pages = [
    "getting_started.md",
    "guide/dynamic_networks.md",
    "guide/spells.md",
    "guide/queries.md",
    "api/types.md",
    "api/functions.md",
]
Depth = 2
```

## Theoretical Background

### Discrete vs. Continuous Time

Dynamic networks can be modeled in two paradigms:

- **Discrete time**: Network changes at fixed time steps $t = 1, 2, 3, \ldots$ (panel data)
- **Continuous time**: Changes can occur at any time, represented by spells $[t_{\text{onset}}, t_{\text{terminus}})$

NetworkDynamic.jl supports continuous-time representation, which subsumes discrete time as a special case. Continuous-time spells can represent any pattern of activity, including instantaneous events and long-duration ties.

### Activity Algebra

Spells follow interval algebra rules:

- **Overlap**: Two spells overlap if $s_1.\text{onset} < s_2.\text{terminus}$ and $s_2.\text{onset} < s_1.\text{terminus}$
- **Containment**: Spell $s_1$ contains $s_2$ if $s_1.\text{onset} \leq s_2.\text{onset}$ and $s_1.\text{terminus} \geq s_2.\text{terminus}$
- **Duration**: $d(s) = s.\text{terminus} - s.\text{onset}$
- **Merging**: Overlapping spells can be merged into a single contiguous spell

## References

1. Butts, C.T. (2008). `network`: A package for managing relational data in R. *Journal of Statistical Software*, 24(2), 1-36.

2. Almquist, Z.W., Butts, C.T. (2014). Logistic network regression for scalable analysis of networks with joint edge/vertex dynamics. *Sociological Methodology*, 44(1), 273-321.

3. Bender-deMoll, S., Morris, M. (2012). `networkDynamic`: Dynamic extensions for network objects. R package.

4. Holme, P., Saramaki, J. (2012). Temporal networks. *Physics Reports*, 519(3), 97-125.
