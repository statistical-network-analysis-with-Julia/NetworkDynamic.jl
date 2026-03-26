# NetworkDynamic.jl


[![Network Analysis](https://img.shields.io/badge/Network-Analysis-orange.svg)](https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl)
[![Build Status](https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://statistical-network-analysis-with-Julia.github.io/NetworkDynamic.jl/stable/)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://statistical-network-analysis-with-Julia.github.io/NetworkDynamic.jl/dev/)
[![Julia](https://img.shields.io/badge/Julia-1.9+-purple.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

<p align="center">
  <img src="docs/src/assets/logo.svg" alt="NetworkDynamic.jl icon" width="160">
</p>

Dynamic network data structures for Julia.

## Overview

NetworkDynamic.jl provides data structures for representing and manipulating dynamic (time-varying) networks. It supports vertex and edge activity spells, time-varying attributes, and network extraction at any time point.

This package is a Julia port of the R `networkDynamic` package from the StatNet collection.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/statistical-network-analysis-with-Julia/NetworkDynamic.jl")
```

## Features

- **Activity spells**: Track when vertices and edges are active
- **Time-varying attributes**: Attributes that change over time
- **Network extraction**: Get network state at any time point
- **Spell operations**: Add, remove, merge, and query spells

## Quick Start

```julia
using NetworkDynamic

# Create dynamic network with 5 vertices
dnet = DynamicNetwork{Int, Float64}(5;
    observation_start=0.0,
    observation_end=10.0
)

# Activate vertices and edges
activate!(dnet, 0.0, 5.0; vertex=1)
activate!(dnet, 0.0, 5.0; vertex=2)
activate!(dnet, 1.0, 4.0; edge=(1, 2))

# Check activity
is_active(dnet, 2.0; edge=(1, 2))  # true
is_active(dnet, 6.0; edge=(1, 2))  # false

# Extract network at time 2.0
snapshot = network_extract(dnet, 2.0)
```

## Activity Spells

```julia
# Add activity spell
add_spell!(dnet, Spell(0.0, 5.0); vertex=1)
add_spell!(dnet, Spell(1.0, 3.0); edge=(1, 2))

# Convenience function
activate!(dnet, onset, terminus; vertex=v)
activate!(dnet, onset, terminus; edge=(i, j))

# Activate multiple elements
activate_vertices!(dnet, [1, 2, 3], 0.0, 10.0)
activate_edges!(dnet, [(1,2), (2,3)], 0.0, 5.0)

# Remove spell
remove_spell!(dnet, spell; vertex=v)

# Merge overlapping spells
merge_spells!(dnet; vertex=v)
```

## Querying Activity

```julia
# Is element active at a point?
is_active(dnet, 2.0; vertex=1)
is_active(dnet, 2.0; edge=(1, 2))

# Is element active during interval?
is_active(dnet, 1.0, 3.0; vertex=1, rule=:any)   # Active at any point
is_active(dnet, 1.0, 3.0; vertex=1, rule=:all)   # Active throughout

# Get all active elements at a time
active_vertices(dnet, 2.0)
active_edges(dnet, 2.0)

# Get spells for an element
spells = get_spells(dnet; vertex=1)
spells = when_vertex(dnet, 1)
spells = when_edge(dnet, 1, 2)
```

## Network Extraction

```julia
# Extract snapshot at time point
snapshot = network_extract(dnet, 2.0)

# Extract during interval
snapshot = network_extract(dnet, 1.0, 3.0; rule=:any)

# Extract sequence of snapshots
snapshots = network_slice(dnet, [1.0, 2.0, 3.0, 4.0])

# Collapse to static (all ever-active elements)
static = network_collapse(dnet)
```

## Time-Varying Attributes

```julia
# Set attribute active during spell
set_vertex_attribute_active!(dnet, v, :status, "infected", 2.0, 5.0)

# Get attribute at time
status = get_vertex_attribute_active(dnet, v, :status, 3.0)

# Edge attributes
set_edge_attribute_active!(dnet, i, j, :weight, 0.5, 1.0, 4.0)
w = get_edge_attribute_active(dnet, i, j, :weight, 2.0)
```

## Conversion

```julia
# Static to dynamic
dnet = as_dynamic_network(static_net; onset=0.0, terminus=10.0)

# Get timing info
info = get_timing_info(dnet)
# (observation_period, data_start, data_end, n_vertex_spells, n_edge_spells)

# Ensure edge activity consistent with vertex activity
reconcile_activity!(dnet)
```

## Spell Type

```julia
# Create spell
s = Spell(onset, terminus)
s = Spell(onset, terminus; onset_censored=true)  # May have started earlier

# Spell operations
spell_overlap(s1, s2)   # Do spells overlap?
spell_duration(s)       # Duration
```

## Documentation

For more detailed documentation, see:

- [Stable Documentation](https://statistical-network-analysis-with-Julia.github.io/NetworkDynamic.jl/stable/)
- [Development Documentation](https://statistical-network-analysis-with-Julia.github.io/NetworkDynamic.jl/dev/)

## References

1. Butts, C.T. (2023). networkDynamic: Dynamic Extensions for Network Objects. R package. [https://cran.r-project.org/package=networkDynamic](https://cran.r-project.org/package=networkDynamic)

2. Almquist, Z.W., & Butts, C.T. (2014). Logistic Network Regression for Scalable Analysis of Networks with Joint Edge/Vertex Dynamics. *Sociological Methodology*, 44(1), 273-321.

## License

MIT License - see [LICENSE](LICENSE) for details.
