# Changelog

All notable changes to NetworkDynamic.jl are documented in this file. The
format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the package adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

Release driven by the 2026-07 expert-panel review: R-networkDynamic-faithful
spell semantics (instantaneous point spells, deactivation, censoring-aware
merging), attribute-preserving extraction, and mutation tracking that lets
downstream packages (TSNA.jl) memoize derived indexes.

### Breaking

- **Point (zero-duration) spells `[t, t)` are now instantaneous events
  active exactly at `t`** (R networkDynamic semantics). Previously they
  matched nothing — a zero-duration spell was inert in every query.
  *Migration:* if you relied on zero-duration spells being inactive, give
  them a small positive duration.
- **Removed phantom exports `ActivitySpell`, `VertexSpell`, `EdgeSpell`** —
  these names were exported in 0.1.0 without any backing definition, so
  removal cannot break working code. *Migration:* none.
- **Minimum Julia raised to 1.12**; package UUID regenerated. *Migration:*
  upgrade Julia and re-resolve environments pinning the old UUID.

### Added

- **Conversion invariants, published and enforced** (issue #1). Every
  `Network` ↔ `DynamicNetwork` path now has an explicit, tested contract; the
  table lives in Networks.jl `docs/src/guide/conversion_invariants.md`.
  `as_dynamic_network`, `network_extract` and `network_collapse` accept
  `report=true` and return `(result, ::Networks.ConversionReport)` naming
  every field they could not carry (spells, TEAs, the observation window,
  two-mode metadata under renumbering, mask entries on dropped vertices).

- `deactivate!(dnet, onset, terminus; vertex=, edge=)` — removes activity in
  `[onset, terminus)`, truncating or splitting existing spells while
  preserving censoring flags on the surviving fragments.
- `get_vertex_activity(dnet, v)` / `get_edge_activity(dnet, i, j)` —
  R-networkDynamic-style activity accessors.
- `mutation_count` field on `DynamicNetwork`, bumped on every
  spell/observation-window mutation, so downstream packages can detect
  staleness and memoize derived indexes (used by TSNA.jl's contact index).
- `retain_all_vertices` keyword on `network_extract`, `network_slice`, and
  `network_collapse` for stable vertex IDs across snapshots;
  `network_extract` records original IDs in a `:vertex_pid` attribute when
  renumbering.
- `network_collapse` gains `onset`/`terminus`/`rule` interval filtering and
  now copies vertex and edge attributes onto the collapsed network.
- Censoring-aware `show` for `Spell` and `DynamicNetwork`;
  `Base.hash(::Spell)`.

### Fixed

- **`as_dynamic_network` silently discarded everything but the vertex count,
  directedness and the edge set.** It rebuilt a bare `Network` from `nv(net)`,
  so vertex, edge and network attributes, the `loops` and two-mode flags and
  the **missing-dyad mask** all vanished — a masked network round-tripped to
  zero masked dyads. With `loops=true` it was worse than lossy: a self-loop was
  recorded as an edge *spell* while `add_edge!` refused it on the freshly built
  loop-less base network, leaving the two inconsistent. It now carries the whole
  static object across with `copy`, and is lossless.
- **`network_extract` / `network_collapse` dropped the missing-dyad mask, the
  network-level attributes and the `loops` flag.** They now preserve all three
  (and two-mode metadata when vertex IDs are stable). An unobserved dyad of the
  base network is unobserved in every snapshot of it; mask entries whose
  endpoints an extraction drops are reported, not silently lost.

### Changed

- `spell_overlap` has explicit point-spell semantics; touching half-open
  intervals (`[0,10)` / `[10,20)`) do not overlap.
- `merge_spells!` and `reconcile_activity!` propagate censoring flags to
  merged spells and store sorted, merged spell sets.
- Dynamic (TEA) attribute getters return the most-recently-set value when
  activity spells overlap.
- Time arguments are no longer restricted to one `Time` type: public
  methods accept mixed numeric types (converted), `DateTime`/`Date` axes
  get sensible default observation windows, and `as_dynamic_network`
  promotes mixed onset/terminus types.

### Performance

- Hot `is_active` query loops reuse a shared empty-spell-vector cache
  instead of allocating on every dictionary miss.

## [0.1.0] - 2026-02-09

Initial release: `DynamicNetwork` with vertex/edge activity spells,
observation windows, dynamic attributes, and extraction to static networks.
