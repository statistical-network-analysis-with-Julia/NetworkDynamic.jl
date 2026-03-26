# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NetworkDynamic.jl is a Julia port of the R `networkDynamic` package from the StatNet collection. It provides data structures for representing and manipulating dynamic (time-varying) networks with activity spells, time-varying attributes, and network snapshot extraction.

## Development Commands

- **Run tests:** `julia --project -e 'using Pkg; Pkg.test()'` (no test directory exists yet)
- **Build docs:** `julia --project=docs docs/make.jl`
- **Load package in REPL:** `julia --project -e 'using NetworkDynamic'`
- **Instantiate dependencies:** `julia --project -e 'using Pkg; Pkg.instantiate()'`

## Architecture

The entire package lives in a single file: `src/NetworkDynamic.jl`.

### Core Types

- **`Spell{T}`** -- Immutable struct representing a time interval `[onset, terminus)` with optional censoring flags. Supports ordering and overlap checks.
- **`TimeVaryingAttribute{Time, V}`** -- Parallel vectors of values and spells for attributes that change over time (called TEAs, after the R package convention).
- **`DynamicNetwork{T, Time}`** -- Mutable struct wrapping a `Network{T}` with dictionaries for vertex spells, edge spells, vertex TEAs, and edge TEAs. `T` is the vertex ID type (must be `<:Integer`), `Time` is the timestamp type (typically `Float64` or `DateTime`).

### Functional Organization (within the single module)

1. **Spell operations** -- `add_spell!`, `remove_spell!`, `merge_spells!`, `activate!`, `activate_vertices!`, `activate_edges!`
2. **Activity queries** -- `is_active` (point and interval variants with `:any`/`:all` rules), `active_vertices`, `active_edges`, `when_vertex`, `when_edge`
3. **Network extraction** -- `network_extract` (point and interval), `network_slice`, `network_collapse`, `get_timing_info`
4. **Time-varying attributes** -- `set_vertex_attribute_active!`, `get_vertex_attribute_active!`, and edge equivalents
5. **Conversion/reconciliation** -- `as_dynamic_network`, `reconcile_activity!`

### Design Patterns

- Keyword dispatch: most functions take `vertex=` or `edge=` keyword arguments to select the target element, throwing `ArgumentError` if neither is provided.
- Undirected edge normalization: edges in undirected networks are stored with `(min, max)` ordering.
- Spells are kept sorted after insertion via `sort!`.
- `Graphs.jl` interface methods (`nv`, `ne`, `vertices`, `is_directed`) are forwarded to the underlying `Network`.

## Key Dependencies

- **Network.jl** -- Local/sibling package (via `[sources]` path dependency at `../Network`); provides the static network type that `DynamicNetwork` wraps.
- **Graphs.jl** -- Julia standard graph interface; `DynamicNetwork` forwards core methods to it.
- **Dates** -- stdlib; supports `DateTime`/`Date` as timestamp types.

## Conventions

- Julia 1.9+ required.
- Mutating functions use `!` suffix (e.g., `activate!`, `reconcile_activity!`).
- All public API is exported at the top of the module file.
- Docstrings use the standard Julia triple-quote format with `# Fields` / `# Type Parameters` sections.
- Spells use half-open intervals: `[onset, terminus)`.
- The package uses parametric types throughout; generic over vertex ID type and time type.
- No tests exist yet; `Project.toml` lists `Test` in `[extras]` and `[targets]` but there is no `test/` directory.
