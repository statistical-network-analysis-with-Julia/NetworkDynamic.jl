using NetworkDynamic
using Test
using Graphs

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

    @testset "Network extraction" begin
        @test isdefined(NetworkDynamic, :network_extract)
        @test isdefined(NetworkDynamic, :network_collapse)
        @test isdefined(NetworkDynamic, :network_slice)
    end

    @testset "Time-varying attributes" begin
        @test isdefined(NetworkDynamic, :set_vertex_attribute_active!)
        @test isdefined(NetworkDynamic, :get_vertex_attribute_active)
        @test isdefined(NetworkDynamic, :set_edge_attribute_active!)
        @test isdefined(NetworkDynamic, :get_edge_attribute_active)
    end

    @testset "Conversion utilities" begin
        @test isdefined(NetworkDynamic, :as_dynamic_network)
        @test isdefined(NetworkDynamic, :reconcile_activity!)
    end

    @testset "Observation period" begin
        dnet = DynamicNetwork(2; observation_start=0.0, observation_end=5.0)
        @test get_observation_period(dnet) == (0.0, 5.0)
        set_observation_period!(dnet, 1.0, 10.0)
        @test get_observation_period(dnet) == (1.0, 10.0)
    end
end
