using NetworkDynamic
using Network
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

    @testset "Activity queries" begin
        dnet = DynamicNetwork(3; observation_start=0.0, observation_end=10.0)
        activate!(dnet, 0.0, 5.0; vertex=1)
        activate!(dnet, 2.0, 8.0; vertex=2)

        @test is_active(dnet, 1.0; vertex=1) == true
        @test is_active(dnet, 6.0; vertex=1) == false
        @test is_active(dnet, 3.0; vertex=2) == true
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
end
