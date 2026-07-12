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
