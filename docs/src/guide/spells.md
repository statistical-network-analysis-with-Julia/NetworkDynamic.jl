# Spells and Activity

This guide covers the `Spell` type and all operations for managing activity spells on vertices and edges in a dynamic network.

## The Spell Type

A `Spell{Time}` represents a time interval during which a network element is active. The interval is half-open: `[onset, terminus)` -- the onset is inclusive and the terminus is exclusive.

### Creating Spells

```julia
using NetworkDynamic

# Basic spell
s = Spell(0.0, 10.0)

# With censoring information
s = Spell(0.0, 10.0;
    onset_censored=true,     # Activity may have started before onset
    terminus_censored=false   # Terminus is known
)
```

### Censoring

Censoring indicates that a spell boundary may not represent the true start or end of activity:

| Flag | Meaning |
|------|---------|
| `onset_censored=true` | Activity may have started before the observed onset |
| `terminus_censored=true` | Activity may continue beyond the observed terminus |
| Both `false` (default) | Both boundaries are observed precisely |

Censoring is metadata -- it does not change how spells are processed in queries or extraction. It is useful for recording data quality information.

```julia
# Left-censored: we started observing at t=0, but the tie may predate observation
s = Spell(0.0, 50.0; onset_censored=true)

# Right-censored: observation ended at t=100, but the tie may persist
s = Spell(30.0, 100.0; terminus_censored=true)

# Interval-censored: both boundaries are uncertain
s = Spell(0.0, 100.0; onset_censored=true, terminus_censored=true)
```

### Spell Properties

```julia
s = Spell(5.0, 15.0)

s.onset            # 5.0
s.terminus         # 15.0
s.onset_censored   # false
s.terminus_censored # false
```

### Spell Utilities

```julia
# Duration of a spell
d = spell_duration(s)  # 10.0

# Check if two spells overlap
s1 = Spell(0.0, 10.0)
s2 = Spell(5.0, 15.0)
spell_overlap(s1, s2)  # true

s3 = Spell(10.0, 20.0)
spell_overlap(s1, s3)  # false (s1 ends exactly when s3 starts)

# Comparison (by onset, then terminus)
s1 < s2  # true (onset 0 < 5)
s1 == Spell(0.0, 10.0)  # true
```

### Spell Ordering

Spells are ordered first by onset, then by terminus:

```julia
spells = [Spell(5.0, 15.0), Spell(0.0, 10.0), Spell(5.0, 10.0)]
sort!(spells)
# Result: [Spell(0.0, 10.0), Spell(5.0, 10.0), Spell(5.0, 15.0)]
```

## Adding Spells

### Using activate!

The most common way to add spells is the `activate!` function:

```julia
dnet = DynamicNetwork(5; observation_start=0.0, observation_end=100.0)

# Activate a vertex
activate!(dnet, 0.0, 50.0; vertex=1)

# Activate an edge
activate!(dnet, 10.0, 30.0; edge=(1, 2))
```

`activate!` is a convenience wrapper that creates a `Spell` and calls `add_spell!`.

### Using add_spell!

For more control, use `add_spell!` with a `Spell` object:

```julia
# With censoring
add_spell!(dnet, Spell(0.0, 50.0; onset_censored=true); vertex=1)

# Edge spell
add_spell!(dnet, Spell(10.0, 30.0); edge=(2, 3))
```

### Batch Activation

Activate multiple elements at once:

```julia
# Activate vertices 1 through 10 from time 0 to 100
activate_vertices!(dnet, collect(1:10), 0.0, 100.0)

# Activate several edges simultaneously
edges = [(1, 2), (2, 3), (3, 4), (4, 5)]
activate_edges!(dnet, edges, 5.0, 50.0)
```

### Edge Auto-Creation

When you add a spell to an edge that does not exist in the underlying static network, the edge is automatically created:

```julia
dnet = DynamicNetwork(5; observation_start=0.0, observation_end=10.0)
# No edges exist yet

activate!(dnet, 1.0, 5.0; edge=(1, 2))
# Edge (1,2) is now in the base network and has one spell
```

## Removing Spells

Remove a specific spell from a vertex or edge:

```julia
# Remove a specific spell
remove_spell!(dnet, Spell(10.0, 30.0); edge=(1, 2))

# The spell must match exactly (onset and terminus)
s = Spell(10.0, 30.0)
remove_spell!(dnet, s; vertex=1)
```

If the specified spell does not exist, the function silently does nothing.

## Retrieving Spells

### Get All Spells

```julia
# Get spells for a vertex
spells = get_spells(dnet; vertex=1)
println("Vertex 1 has $(length(spells)) spells")
for s in spells
    println("  [$(s.onset), $(s.terminus))")
end

# Get spells for an edge
spells = get_spells(dnet; edge=(1, 2))
```

### Convenience Aliases

```julia
# Equivalent to get_spells(dnet; vertex=v)
when_vertex(dnet, 1)

# Equivalent to get_spells(dnet; edge=(i, j))
when_edge(dnet, 1, 2)
```

### Activity Range

Get the earliest and latest times for an element:

```julia
range = get_activity_range(dnet; vertex=1)
if !isnothing(range)
    println("Vertex 1 active from $(range[1]) to $(range[2])")
end

range = get_activity_range(dnet; edge=(1, 2))
```

## Merging Spells

When a vertex or edge accumulates overlapping or adjacent spells, merge them into minimal non-overlapping spells:

```julia
# Before merging: vertex 1 has overlapping spells
activate!(dnet, 0.0, 20.0; vertex=1)
activate!(dnet, 15.0, 40.0; vertex=1)
activate!(dnet, 35.0, 60.0; vertex=1)

# Spells: [0,20), [15,40), [35,60)
println(get_spells(dnet; vertex=1))  # 3 spells

# Merge overlapping spells
merge_spells!(dnet; vertex=1)

# After: [0,60) - one contiguous spell
println(get_spells(dnet; vertex=1))  # 1 spell
```

### Merge Rules

- **Overlapping** spells (s1.terminus > s2.onset) are merged
- **Adjacent** spells (s1.terminus == s2.onset) are merged
- **Disjoint** spells (gap between them) remain separate

```julia
# These merge: [0,10) and [10,20) -> [0,20)
activate!(dnet, 0.0, 10.0; vertex=2)
activate!(dnet, 10.0, 20.0; vertex=2)
merge_spells!(dnet; vertex=2)
# Result: [0,20)

# These remain separate: [0,10) and [15,25)
activate!(dnet, 0.0, 10.0; vertex=3)
activate!(dnet, 15.0, 25.0; vertex=3)
merge_spells!(dnet; vertex=3)
# Result: [0,10) and [15,25) -- gap from 10 to 15
```

### Merging Edge Spells

```julia
merge_spells!(dnet; edge=(1, 2))
```

## Spell Patterns

### Continuous Activity

A vertex or edge active for the entire observation period:

```julia
activate!(dnet, 0.0, 100.0; vertex=1)
```

### Intermittent Activity

Active in separate periods with gaps:

```julia
activate!(dnet, 0.0, 20.0; vertex=1)    # First period
activate!(dnet, 40.0, 60.0; vertex=1)    # Second period
activate!(dnet, 80.0, 100.0; vertex=1)   # Third period
```

### Progressive Formation

Edges form over time:

```julia
activate!(dnet, 0.0, 100.0; edge=(1, 2))   # Exists from start
activate!(dnet, 20.0, 100.0; edge=(2, 3))   # Forms at t=20
activate!(dnet, 50.0, 100.0; edge=(3, 4))   # Forms at t=50
```

### Temporal Ordering

Events with short duration, representing interactions:

```julia
# Each "interaction" lasts a brief period
activate!(dnet, 1.0, 1.1; edge=(1, 2))
activate!(dnet, 3.5, 3.6; edge=(2, 3))
activate!(dnet, 5.0, 5.1; edge=(1, 3))
activate!(dnet, 7.2, 7.3; edge=(3, 2))
```

## Working with Different Time Types

### Float64 (Default)

```julia
dnet = DynamicNetwork(5; observation_start=0.0, observation_end=100.0)
activate!(dnet, 0.0, 50.0; vertex=1)
spell_duration(Spell(0.0, 50.0))  # 50.0
```

### DateTime

```julia
using Dates

dnet = DynamicNetwork{Int, DateTime}(5;
    observation_start=DateTime(2024, 1, 1),
    observation_end=DateTime(2024, 12, 31)
)

activate!(dnet, DateTime(2024, 1, 1), DateTime(2024, 6, 30); vertex=1)

s = Spell(DateTime(2024, 1, 1), DateTime(2024, 6, 30))
d = spell_duration(s)  # Millisecond duration
```

### Date

```julia
using Dates

dnet = DynamicNetwork{Int, Date}(5;
    observation_start=Date(2024, 1, 1),
    observation_end=Date(2024, 12, 31)
)

activate!(dnet, Date(2024, 1, 1), Date(2024, 6, 30); vertex=1)

s = Spell(Date(2024, 1, 1), Date(2024, 6, 30))
d = spell_duration(s)  # Day duration
```

## Best Practices

### Spell Management

1. **Merge periodically**: Call `merge_spells!` after adding many spells to reduce memory usage
2. **Check for gaps**: Use `get_activity_range` to verify elements are active when expected
3. **Consistent time types**: All spells in a network must use the same `Time` type
4. **Order matters**: Spells are automatically sorted by onset when added

### Data Quality

1. **Mark censoring**: Use `onset_censored` and `terminus_censored` to document observation boundaries
2. **Validate constraints**: An edge should only be active when both endpoints are active -- use `reconcile_activity!`
3. **Check onset <= terminus**: The `Spell` constructor enforces this, throwing `ArgumentError` otherwise

### Performance

1. **Batch operations**: Use `activate_vertices!` and `activate_edges!` instead of loops
2. **Minimize spell count**: Merge overlapping spells to reduce storage and query time
3. **Use `get_spells` sparingly**: For frequent queries, cache the result rather than calling repeatedly
