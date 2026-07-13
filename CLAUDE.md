# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NetworkDynamic.jl is a Julia port of the R `networkDynamic` package from the StatNet collection. It provides data structures for representing and manipulating dynamic (time-varying) networks with activity spells, time-varying attributes, and network snapshot extraction.

## Development Commands

- **Run tests:** `julia --project -e 'using Pkg; Pkg.test()'`
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

### Conversion invariants

Both directions between `Network` and `DynamicNetwork` honour the **ecosystem conversion contract** (Networks.jl `src/conversion.jl`): preserve what the target can represent, reject or policy-gate what it cannot, report what was dropped. The full per-path table for the whole ecosystem is `Networks.jl/docs/src/guide/conversion_invariants.md`.

- **`as_dynamic_network` is lossless.** A `DynamicNetwork` *wraps* a `Network`, so the whole static object is carried in by `copy` — directedness, the `loops` flag, two-mode metadata, vertex/edge/network attributes, and the **missing-dyad mask**. It used to rebuild a bare `Network` from `nv(net)`, which silently discarded all of them (a masked network round-tripped to zero masked dyads) and, with `loops=true`, left a self-loop recorded as an edge *spell* while `add_edge!` refused it on the loop-less base network.
- **`network_extract` / `network_collapse` preserve everything a static network can hold**: directedness, `loops`, static vertex/edge/network attributes, and the missing-dyad mask (an unobserved dyad of the base network is unobserved in every snapshot of it — it must not become an absent tie). Two-mode metadata survives only under `retain_all_vertices=true`; renumbering to `1:k` destroys the "vertices `1:k` are mode 1" invariant that the flag encodes.
- What a static network *cannot* hold — spells, TEAs, the observation window, plus mask entries whose endpoints an extraction drops — is named in a `Networks.ConversionReport`: pass `report=true` to get `(net, rep)` and inspect `dropped_fields(rep)` / `is_lossless(rep)`.
- Pinned by the six "Conversion invariants: ..." testsets in `test/runtests.jl`, which cover directed and undirected, with/without attributes, masked dyads with a **present** face value *and* an **absent** one, self-loops, isolates, two-mode networks, overlapping spells, point spells, and observation-window boundaries.

### Design Patterns

- Keyword dispatch: most functions take `vertex=` or `edge=` keyword arguments to select the target element, throwing `ArgumentError` if neither is provided.
- Undirected edge normalization: edges in undirected networks are stored with `(min, max)` ordering.
- Spells are kept sorted after insertion via `sort!`.
- `Graphs.jl` interface methods (`nv`, `ne`, `vertices`, `is_directed`) are forwarded to the underlying `Network`.

## Key Dependencies

- **Networks.jl** -- Local/sibling package (via `[sources]` path dependency at `../Networks.jl`); provides the static network type that `DynamicNetwork` wraps.
- **Graphs.jl** -- Julia standard graph interface; `DynamicNetwork` forwards core methods to it.
- **Dates** -- stdlib; supports `DateTime`/`Date` as timestamp types.

## Conventions

- Julia 1.12+ required (Networks.jl cannot load on earlier versions).
- Mutating functions use `!` suffix (e.g., `activate!`, `reconcile_activity!`).
- All public API is exported at the top of the module file.
- Docstrings use the standard Julia triple-quote format with `# Fields` / `# Type Parameters` sections.
- Spells use half-open intervals: `[onset, terminus)`.
- The package uses parametric types throughout; generic over vertex ID type and time type.
- Behavioral tests live in `test/runtests.jl` (extraction, TEAs, point spells, censoring, DateTime time axes).
- Point (zero-duration) spells `[t,t)` are instantaneous events, active exactly at `t`.
- `network_extract` records original vertex IDs in the `:vertex_pid` vertex attribute when it renumbers; `retain_all_vertices=true` keeps IDs stable.
- TEA lookups return the most recently set matching value when attribute spells overlap.
