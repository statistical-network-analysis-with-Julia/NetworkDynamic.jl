using NetworkDynamic
using Networks
using Test
using Graphs
using Dates

@testset "NetworkDynamic.jl" begin
    @testset "Module loading" begin
        @test @isdefined(NetworkDynamic)
    end

    @testset "Spell construction" begin
        s = Spell(0.0, 1.0)
        @test s isa Spell{Float64}
        @test s.onset == 0.0
        @test s.terminus == 1.0
        @test s.onset_censored == false
        @test s.terminus_censored == false

        s2 = Spell(0.0, 1.0; onset_censored=true)
        @test s2.onset_censored == true

        @test_throws ArgumentError Spell(1.0, 0.0)
    end

    @testset "Spell utilities" begin
        s1 = Spell(0.0, 2.0)
        s2 = Spell(1.0, 3.0)
        s3 = Spell(3.0, 4.0)

        @test spell_overlap(s1, s2) == true
        @test spell_overlap(s1, s3) == false
        @test spell_duration(s1) == 2.0
    end

    @testset "DynamicNetwork construction" begin
        dnet = DynamicNetwork(5)
        @test dnet isa DynamicNetwork{Int, Float64}
        @test Graphs.nv(dnet) == 5
        @test Graphs.ne(dnet) == 0

        dnet2 = DynamicNetwork{Int, Float64}(3;
            observation_start=0.0, observation_end=10.0, directed=false)
        @test get_observation_period(dnet2) == (0.0, 10.0)
    end

    @testset "Spell operations" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)

        activate!(dnet, 0.0, 5.0; vertex=1)
        activate!(dnet, 3.0, 8.0; vertex=1)
        spells = get_spells(dnet; vertex=1)
        @test length(spells) == 2

        activate!(dnet, 1.0, 4.0; edge=(1, 2))
        @test is_active(dnet, 2.0; edge=(1, 2)) == true
        @test is_active(dnet, 5.0; edge=(1, 2)) == false
    end

    @testset "deactivate!" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 0.0, 10.0; vertex=1)

        # Punch a hole: [0,10) minus [3,6) leaves [0,3) and [6,10)
        deactivate!(dnet, 3.0, 6.0; vertex=1)
        @test get_spells(dnet; vertex=1) == [Spell(0.0, 3.0), Spell(6.0, 10.0)]
        @test is_active(dnet, 2.0; vertex=1)
        @test !is_active(dnet, 4.0; vertex=1)
        @test is_active(dnet, 7.0; vertex=1)

        # Truncation at the boundaries and full removal
        activate!(dnet, 0.0, 5.0; edge=(1, 2))
        deactivate!(dnet, 0.0, 2.0; edge=(1, 2))
        @test get_spells(dnet; edge=(1, 2)) == [Spell(2.0, 5.0)]
        deactivate!(dnet, 0.0, 10.0; edge=(1, 2))
        @test isempty(get_spells(dnet; edge=(1, 2)))

        # Non-overlapping deactivation is a no-op
        activate!(dnet, 0.0, 2.0; vertex=2)
        deactivate!(dnet, 5.0, 8.0; vertex=2)
        @test get_spells(dnet; vertex=2) == [Spell(0.0, 2.0)]
        # No recorded spells: no-op, no throw
        deactivate!(dnet, 0.0, 5.0; vertex=3)
        @test isempty(get_spells(dnet; vertex=3))

        # Censoring flags survive on the fragments
        dnet2 = DynamicNetwork(2; observation_start=0.0, observation_end=10.0)
        add_spell!(dnet2, Spell(0.0, 10.0; onset_censored=true,
                                terminus_censored=true); vertex=1)
        deactivate!(dnet2, 4.0, 6.0; vertex=1)
        s = get_spells(dnet2; vertex=1)
        @test s[1].onset_censored && !s[1].terminus_censored
        @test !s[2].onset_censored && s[2].terminus_censored

        # Point deactivation removes point spells only
        dnet3 = DynamicNetwork(2; observation_start=0.0, observation_end=10.0)
        activate!(dnet3, 5.0, 5.0; edge=(1, 2))   # instantaneous event
        activate!(dnet3, 0.0, 10.0; vertex=1)
        deactivate!(dnet3, 5.0, 5.0; edge=(1, 2))
        deactivate!(dnet3, 5.0, 5.0; vertex=1)
        @test isempty(get_spells(dnet3; edge=(1, 2)))
        @test get_spells(dnet3; vertex=1) == [Spell(0.0, 10.0)]

        # DateTime time axis
        dnet4 = DynamicNetwork{Int, DateTime}(2;
            observation_start=DateTime(2024, 1, 1),
            observation_end=DateTime(2024, 12, 31))
        activate!(dnet4, DateTime(2024, 1, 1), DateTime(2024, 12, 31); vertex=1)
        deactivate!(dnet4, DateTime(2024, 3, 1), DateTime(2024, 6, 1); vertex=1)
        @test is_active(dnet4, DateTime(2024, 2, 1); vertex=1)
        @test !is_active(dnet4, DateTime(2024, 4, 1); vertex=1)
        @test is_active(dnet4, DateTime(2024, 7, 1); vertex=1)

        @test_throws ArgumentError deactivate!(dnet, 0.0, 1.0)
    end

    @testset "Mutation counter" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        c0 = dnet.mutation_count
        activate!(dnet, 0.0, 5.0; vertex=1)
        @test dnet.mutation_count > c0

        c1 = dnet.mutation_count
        deactivate!(dnet, 1.0, 2.0; vertex=1)
        @test dnet.mutation_count > c1

        c2 = dnet.mutation_count
        activate!(dnet, 0.0, 5.0; edge=(1, 2))
        remove_spell!(dnet, Spell(0.0, 5.0); edge=(1, 2))
        merge_spells!(dnet; vertex=1)
        reconcile_activity!(dnet)
        set_observation_period!(dnet, 0.0, 20.0)
        @test dnet.mutation_count >= c2 + 5

        # Queries do not bump the counter
        c3 = dnet.mutation_count
        is_active(dnet, 1.5; vertex=1)
        get_spells(dnet; vertex=1)
        network_extract(dnet, 1.5)
        @test dnet.mutation_count == c3
    end

    @testset "Activity queries" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 0.0, 5.0; vertex=1)
        activate!(dnet, 2.0, 8.0; vertex=2)

        @test is_active(dnet, 1.0; vertex=1) == true
        @test is_active(dnet, 6.0; vertex=1) == false
        @test is_active(dnet, 3.0; vertex=2) == true

        # Exported spell accessors (R get.vertex.activity/get.edge.activity)
        @test get_vertex_activity(dnet, 1) == [Spell(0.0, 5.0)]
        @test get_vertex_activity(dnet, 1) == when_vertex(dnet, 1)
        activate!(dnet, 1.0, 4.0; edge=(1, 2))
        @test get_edge_activity(dnet, 1, 2) == [Spell(1.0, 4.0)]
        @test get_edge_activity(dnet, 1, 2) == when_edge(dnet, 1, 2)
    end

    @testset "Point (zero-duration) spells" begin
        s = Spell(5.0, 5.0)
        @test spell_duration(s) == 0.0

        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 5.0, 5.0; edge=(1, 2))

        # Instantaneous event: active exactly at t, nowhere else
        @test is_active(dnet, 5.0; edge=(1, 2))
        @test !is_active(dnet, 4.99; edge=(1, 2))
        @test !is_active(dnet, 5.01; edge=(1, 2))

        # Interval queries see the event when the interval covers t
        @test is_active(dnet, 4.0, 6.0; edge=(1, 2))
        @test !is_active(dnet, 6.0, 8.0; edge=(1, 2))

        # Point-vs-point overlap only when identical
        @test spell_overlap(Spell(5.0, 5.0), Spell(5.0, 5.0))
        @test !spell_overlap(Spell(5.0, 5.0), Spell(6.0, 6.0))
        @test spell_overlap(Spell(5.0, 5.0), Spell(0.0, 10.0))
    end

    @testset "Int time arguments on Float64 networks" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 1, 4; vertex=1)      # Int onset/terminus
        @test is_active(dnet, 2; vertex=1)   # Int query
        @test !is_active(dnet, 5; vertex=1)
        @test active_vertices(dnet, 2) == [1]
    end

    @testset "Network extraction" begin
        dnet = DynamicNetwork(4; observation_start=0.0, observation_end=10.0)
        set_vertex_attribute!(dnet.network, :name,
                              Dict(1 => "A", 2 => "B", 3 => "C", 4 => "D"))
        set_edge_attribute!(dnet.network, :w, 2, 3, 7.0)

        activate!(dnet, 0.0, 10.0; vertex=2)
        activate!(dnet, 0.0, 10.0; vertex=3)
        activate!(dnet, 0.0, 4.0; vertex=4)
        activate!(dnet, 1.0, 5.0; edge=(2, 3))
        activate!(dnet, 1.0, 3.0; edge=(3, 4))

        # At t=2: vertices 2,3,4 active; edges (2,3) and (3,4) active
        snap = network_extract(dnet, 2.0)
        @test nv(snap) == 3
        @test ne(snap) == 2

        # Renumbered, but original IDs recorded as :vertex_pid
        pids = get_vertex_attribute(snap, :vertex_pid)
        @test sort(collect(values(pids))) == [2, 3, 4]

        # Static vertex attributes survive extraction (this used to throw)
        names = get_vertex_attribute(snap, :name)
        new_of = Dict(old => new for (new, old) in pids)
        @test names[new_of[2]] == "B"
        @test names[new_of[4]] == "D"
        # Edge attributes survive too
        @test get_edge_attribute(snap, :w, new_of[2], new_of[3]) == 7.0

        # Stable IDs with retain_all_vertices
        snap_stable = network_extract(dnet, 2.0; retain_all_vertices=true)
        @test nv(snap_stable) == 4
        @test has_edge(snap_stable, 2, 3)
        @test has_edge(snap_stable, 3, 4)
        @test get_vertex_attribute(snap_stable, :name, 2) == "B"

        # At t=6: vertex 4 and both edges inactive
        snap6 = network_extract(dnet, 6.0; retain_all_vertices=true)
        @test ne(snap6) == 0

        # Interval extraction with rules
        any_net = network_extract(dnet, 4.5, 6.0; rule=:any,
                                  retain_all_vertices=true)
        @test has_edge(any_net, 2, 3)      # (2,3) active until 5
        @test !has_edge(any_net, 3, 4)     # (3,4) ended at 3
        all_net = network_extract(dnet, 1.0, 5.0; rule=:all,
                                  retain_all_vertices=true)
        @test has_edge(all_net, 2, 3)
        @test !has_edge(all_net, 3, 4)

        # Slices
        slices = network_slice(dnet, [0.5, 2.0, 6.0]; retain_all_vertices=true)
        @test length(slices) == 3
        @test ne(slices[2]) == 2
        @test ne(slices[3]) == 0
    end

    @testset "Network collapse" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        set_vertex_attribute!(dnet.network, :name, Dict(1 => "A", 2 => "B", 3 => "C"))
        activate!(dnet, 0.0, 2.0; edge=(1, 2))
        activate!(dnet, 8.0, 9.0; edge=(2, 3))

        col = network_collapse(dnet)
        @test nv(col) == 3
        @test has_edge(col, 1, 2) && has_edge(col, 2, 3)
        @test get_vertex_attribute(col, :name, 1) == "A"

        # Interval-restricted collapse
        col_early = network_collapse(dnet; onset=0.0, terminus=5.0)
        @test has_edge(col_early, 1, 2)
        @test !has_edge(col_early, 2, 3)
    end

    @testset "Time-varying attributes" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)

        set_vertex_attribute_active!(dnet, 1, :status, "healthy", 0.0, 5.0)
        set_vertex_attribute_active!(dnet, 1, :status, "sick", 5.0, 10.0)

        @test get_vertex_attribute_active(dnet, 1, :status, 2.0) == "healthy"
        @test get_vertex_attribute_active(dnet, 1, :status, 5.0) == "sick"
        @test get_vertex_attribute_active(dnet, 1, :status, 10.0) === nothing
        @test get_vertex_attribute_active(dnet, 2, :status, 2.0) === nothing

        # Overlapping spells: the most recently set value wins
        set_vertex_attribute_active!(dnet, 1, :status, "recovered", 4.0, 6.0)
        @test get_vertex_attribute_active(dnet, 1, :status, 4.5) == "recovered"

        set_edge_attribute_active!(dnet, 1, 2, :strength, 0.5, 0.0, 5.0)
        @test get_edge_attribute_active(dnet, 1, 2, :strength, 1.0) == 0.5
        @test get_edge_attribute_active(dnet, 1, 2, :strength, 7.0) === nothing

        @test :status in list_vertex_attributes_active(dnet)
        @test :strength in list_edge_attributes_active(dnet)
    end

    @testset "Spell merging preserves censoring" begin
        dnet = DynamicNetwork(2; observation_start=0.0, observation_end=10.0)
        add_spell!(dnet, Spell(0.0, 3.0; onset_censored=true); vertex=1)
        add_spell!(dnet, Spell(2.0, 6.0); vertex=1)
        add_spell!(dnet, Spell(6.0, 8.0; terminus_censored=true); vertex=1)
        add_spell!(dnet, Spell(9.0, 10.0); vertex=1)

        merge_spells!(dnet; vertex=1)
        spells = get_spells(dnet; vertex=1)

        @test length(spells) == 2
        @test spells[1].onset == 0.0 && spells[1].terminus == 8.0
        @test spells[1].onset_censored          # from the left-censored spell
        @test spells[1].terminus_censored       # from the right-censored spell
        @test spells[2] == Spell(9.0, 10.0)
    end

    @testset "Conversion utilities" begin
        net = network(3; directed=false)
        add_edge!(net, 1, 2)
        add_edge!(net, 2, 3)

        # Bare call works; mixed Int/Float64 promotes
        dnet = as_dynamic_network(net)
        @test dnet isa DynamicNetwork{Int, Float64}
        @test is_active(dnet, 0.5; vertex=1)
        @test is_active(dnet, 0.5; edge=(1, 2))

        dnet2 = as_dynamic_network(net; onset=0, terminus=10.0)
        @test dnet2 isa DynamicNetwork{Int, Float64}
        @test get_observation_period(dnet2) == (0.0, 10.0)

        @test !is_directed(dnet)
    end

    @testset "DateTime time axis" begin
        # Default construction no longer requires observation kwargs
        dnet = DynamicNetwork{Int, DateTime}(3)
        @test dnet isa DynamicNetwork{Int, DateTime}

        t0 = DateTime(2024, 1, 1)
        t1 = DateTime(2024, 6, 1)
        t2 = DateTime(2024, 12, 31)
        set_observation_period!(dnet, t0, t2)

        activate!(dnet, t0, t1; vertex=1)
        @test is_active(dnet, DateTime(2024, 3, 1); vertex=1)
        @test !is_active(dnet, DateTime(2024, 7, 1); vertex=1)

        snap = network_extract(dnet, DateTime(2024, 3, 1))
        @test nv(snap) == 1

        # Static network conversion with DateTime bounds
        net = network(2)
        add_edge!(net, 1, 2)
        ddnet = as_dynamic_network(net; onset=t0, terminus=t2)
        @test ddnet isa DynamicNetwork{Int, DateTime}
        @test is_active(ddnet, t1; edge=(1, 2))
    end

    @testset "Reconcile activity" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 0.0, 4.0; vertex=1)
        activate!(dnet, 6.0, 10.0; vertex=1)  # gap [4, 6)
        activate!(dnet, 2.0, 8.0; vertex=2)
        activate!(dnet, 0.0, 10.0; edge=(1, 2))

        reconcile_activity!(dnet)
        spells = get_spells(dnet; edge=(1, 2))

        # Edge restricted to when both endpoints are active: [2,4) and [6,8)
        @test spells == [Spell(2.0, 4.0), Spell(6.0, 8.0)]
        @test issorted(spells)
    end

    @testset "Observation period" begin
        dnet = DynamicNetwork(2; observation_start=0.0, observation_end=5.0)
        @test get_observation_period(dnet) == (0.0, 5.0)
        set_observation_period!(dnet, 1.0, 10.0)
        @test get_observation_period(dnet) == (1.0, 10.0)
    end

    # =========================================================================
    # Conversion invariants (see docs/src/guide/conversion_invariants.md)
    #
    # The contract: everything the target representation can hold survives;
    # what it cannot hold is rejected or reported, never silently dropped.
    # The missing-dyad mask is the field that used to vanish — a masked dyad
    # round-tripped to zero masked dyads, which is the exact failure mode the
    # ecosystem missing-data contract exists to prevent.
    # =========================================================================

    # A network exercising every field the contract names: directedness,
    # loops + a self-loop, isolates, vertex/edge/network attributes, and both
    # flavours of masked dyad (one with a PRESENT face value, one ABSENT).
    function _kitchen_sink(; directed::Bool)
        net = network(6; directed=directed, loops=true)
        add_edge!(net, 1, 2)
        add_edge!(net, 2, 3)
        add_edge!(net, 3, 3)             # self-loop
        # vertices 5, 6 are isolates
        set_vertex_attribute!(net, :grp, 1, "a")
        set_vertex_attribute!(net, :grp, 5, "b")   # isolate carries an attribute
        set_edge_attribute!(net, :weight, 1, 2, 2.5)
        set_network_attribute!(net, :title, "kitchen sink")
        set_missing_dyad!(net, 2, 3)     # masked, PRESENT face value
        set_missing_dyad!(net, 4, 5)     # masked, ABSENT face value
        return net
    end

    @testset "Conversion invariants: Network → DynamicNetwork is lossless" begin
        for directed in (true, false)
            net = _kitchen_sink(; directed=directed)
            dnet, rep = as_dynamic_network(net; onset=0.0, terminus=10.0,
                                           report=true)

            @test is_lossless(rep)
            @test isempty(dropped_fields(rep))

            base = dnet.network
            @test is_directed(base) == directed
            @test base.loops
            @test nv(base) == 6
            @test has_edge(base, 3, 3)                     # self-loop survived
            @test get_vertex_attribute(base, :grp, 1) == "a"
            @test get_vertex_attribute(base, :grp, 5) == "b"
            @test get_edge_attribute(base, :weight, 1, 2) == 2.5
            @test get_network_attribute(base, :title) == "kitchen sink"

            # The mask survives — both the present-face and the absent-face
            # masked dyad, and neither turned into a tie or a non-tie.
            @test n_missing_dyads(base) == 2
            @test is_missing_dyad(base, 2, 3)
            @test is_missing_dyad(base, 4, 5)
            @test has_edge(base, 2, 3)                     # present face value
            @test !has_edge(base, 4, 5)                    # absent face value

            # Every vertex and edge active for the whole observation window
            @test get_observation_period(dnet) == (0.0, 10.0)
            @test all(is_active(dnet, 5.0; vertex=v) for v in 1:6)
            @test is_active(dnet, 5.0; edge=(3, 3))
        end
    end

    @testset "Conversion invariants: Network → DynamicNetwork → Network round-trip" begin
        for directed in (true, false)
            net = _kitchen_sink(; directed=directed)
            back = network_collapse(as_dynamic_network(net; onset=0.0, terminus=10.0))

            @test is_directed(back) == directed
            @test back.loops
            @test nv(back) == nv(net)
            @test ne(back) == ne(net)
            @test Set((src(e), dst(e)) for e in edges(back)) ==
                  Set((src(e), dst(e)) for e in edges(net))
            @test has_edge(back, 3, 3)
            @test get_vertex_attribute(back, :grp, 1) == "a"
            @test get_vertex_attribute(back, :grp, 5) == "b"
            @test get_edge_attribute(back, :weight, 1, 2) == 2.5
            @test get_network_attribute(back, :title) == "kitchen sink"

            # THE regression: the mask must not round-trip to zero.
            @test n_missing_dyads(back) == 2
            @test is_missing_dyad(back, 2, 3)
            @test is_missing_dyad(back, 4, 5)
            @test has_edge(back, 2, 3) && !has_edge(back, 4, 5)
        end
    end

    @testset "Conversion invariants: two-mode metadata" begin
        bp = network(5; bipartite=2)
        add_edge!(bp, 1, 3)
        add_edge!(bp, 2, 5)
        set_missing_dyad!(bp, 1, 4)
        dnet = as_dynamic_network(bp; onset=0.0, terminus=10.0)

        @test dnet.network.bipartite == 2
        @test is_two_mode(dnet.network)

        # Stable IDs: the mode partition is meaningful and is preserved.
        collapsed, rep = network_collapse(dnet; report=true)
        @test collapsed.bipartite == 2
        @test n_missing_dyads(collapsed) == 1
        @test !(:bipartite in dropped_fields(rep))

        keep, rep_keep = network_extract(dnet, 5.0; retain_all_vertices=true,
                                         report=true)
        @test keep.bipartite == 2
        @test !(:bipartite in dropped_fields(rep_keep))

        # Renumbering destroys "vertices 1:k are mode 1" — dropped, and SAID so.
        renum, rep_renum = network_extract(dnet, 5.0; retain_all_vertices=false,
                                           report=true)
        @test isnothing(renum.bipartite)
        @test :bipartite in dropped_fields(rep_renum)
    end

    @testset "Conversion invariants: network_extract preserves what it can" begin
        for directed in (true, false)
            net = _kitchen_sink(; directed=directed)
            dnet = as_dynamic_network(net; onset=0.0, terminus=10.0)

            snap, rep = network_extract(dnet, 5.0; retain_all_vertices=true,
                                        report=true)
            @test is_directed(snap) == directed
            @test snap.loops
            @test has_edge(snap, 3, 3)
            @test get_vertex_attribute(snap, :grp, 1) == "a"
            @test get_edge_attribute(snap, :weight, 1, 2) == 2.5
            @test get_network_attribute(snap, :title) == "kitchen sink"
            @test n_missing_dyads(snap) == 2
            @test is_missing_dyad(snap, 2, 3) && is_missing_dyad(snap, 4, 5)

            # A snapshot has no time axis: that IS lossy, and the report says so.
            @test !is_lossless(rep)
            @test :spells in dropped_fields(rep)
            @test :observation_period in dropped_fields(rep)
            @test !(:missing_dyads in dropped_fields(rep))   # nothing lost here
        end
    end

    @testset "Conversion invariants: mask entries on inactive vertices are reported" begin
        dnet = DynamicNetwork(4; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 0.0, 10.0; vertex=1)
        activate!(dnet, 0.0, 10.0; vertex=2)
        activate!(dnet, 0.0, 10.0; edge=(1, 2))
        # Vertices 3 and 4 are never active
        set_missing_dyad!(dnet.network, 3, 4)
        set_missing_dyad!(dnet.network, 1, 2)

        # Renumbering drops vertices 3, 4 — so their masked dyad cannot be
        # carried. It is not silently forgotten.
        renum, rep = network_extract(dnet, 5.0; retain_all_vertices=false,
                                     report=true)
        @test nv(renum) == 2
        @test n_missing_dyads(renum) == 1              # (1,2) survives, remapped
        @test is_missing_dyad(renum, 1, 2)
        @test :missing_dyads in dropped_fields(rep)

        # Keeping all vertices keeps the whole mask.
        keep, rep_keep = network_extract(dnet, 5.0; retain_all_vertices=true,
                                         report=true)
        @test n_missing_dyads(keep) == 2
        @test !(:missing_dyads in dropped_fields(rep_keep))
    end

    @testset "Conversion invariants: TEA drop is reported only when TEAs exist" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate_vertices!(dnet, [1, 2, 3], 0.0, 10.0)
        activate!(dnet, 0.0, 10.0; edge=(1, 2))

        _, rep = network_extract(dnet, 5.0; retain_all_vertices=true, report=true)
        @test !(:time_varying_attributes in dropped_fields(rep))

        set_vertex_attribute_active!(dnet, 1, :mood, "up", 0.0, 5.0)
        _, rep2 = network_extract(dnet, 2.0; retain_all_vertices=true, report=true)
        @test :time_varying_attributes in dropped_fields(rep2)
    end

    @testset "Conversion invariants: temporal edge cases" begin
        dnet = DynamicNetwork(5; observation_start=0.0, observation_end=10.0)
        activate_vertices!(dnet, [1, 2, 3, 4, 5], 0.0, 10.0)
        # Overlapping spells on one edge
        activate!(dnet, 0.0, 6.0; edge=(1, 2))
        activate!(dnet, 4.0, 10.0; edge=(1, 2))
        # Point spell: an instantaneous contact at t = 7
        activate!(dnet, 7.0, 7.0; edge=(2, 3))
        # A spell flush with the observation-window edges
        activate!(dnet, 0.0, 10.0; edge=(3, 4))
        # Vertex 5 is an isolate throughout

        # Overlapping spells: the edge is active across the union, including
        # the overlap, and collapsing it yields exactly one edge.
        @test has_edge(network_extract(dnet, 5.0; retain_all_vertices=true), 1, 2)
        @test has_edge(network_extract(dnet, 8.0; retain_all_vertices=true), 1, 2)
        collapsed = network_collapse(dnet)
        @test ne(collapsed) == 3
        @test nv(collapsed) == 5                       # the isolate survives

        # Point spell: present exactly at its instant, nowhere else.
        @test has_edge(network_extract(dnet, 7.0; retain_all_vertices=true), 2, 3)
        @test !has_edge(network_extract(dnet, 6.99; retain_all_vertices=true), 2, 3)
        @test !has_edge(network_extract(dnet, 7.01; retain_all_vertices=true), 2, 3)

        # Observation-window edges: [0,10) is half-open at the terminus.
        @test has_edge(network_extract(dnet, 0.0; retain_all_vertices=true), 3, 4)
        @test !has_edge(network_extract(dnet, 10.0; retain_all_vertices=true), 3, 4)

        # network_slice is a vector of networks, so it has no single report.
        @test length(network_slice(dnet, [0.0, 5.0, 7.0])) == 3
        @test_throws ArgumentError network_slice(dnet, [0.0]; report=true)
    end
end
