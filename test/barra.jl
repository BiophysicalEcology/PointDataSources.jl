using PointDataSources, Test, Dates

@testset "BARRA point" begin
    @test PointDataSources.pointbackend(BARRA{BARRAC2,AUST04}) == PointDataSources.OpenDAPBackend()
    @test PointDataSources.getpoint_keywords(BARRA{BARRAC2,AUST04}) == (:date,)
    @test :tas in pointlayers(BARRA{BARRAR2,AUS11})

    if !Sys.iswindows()
        # BARRA default frequency is Hour -- 24 timesteps/day.
        nt = getpoint(BARRA{BARRAC2,AUST04}, :tas; lon=145.0, lat=-37.8,
            date=(Date(1979,1,1), Date(1979,1,2)))
        @test length(nt.times) == 48
        @test all(250.0 .< nt.values .< 330.0)
        @test nt.units == "K"

        # spans two monthly files -- confirms multi-file concatenation works.
        mm = getpoint(BARRA{BARRAC2,AUST04}, :tas; lon=145.0, lat=-37.8,
            date=(Date(1979,1,30), Date(1979,2,2)))
        @test length(mm.times) == 96

        orog = getpoint(BARRA{BARRAC2,AUST04}, :orog; lon=145.0, lat=-37.8)
        @test orog.value isa Real
        @test orog.units == "m"

        @test_throws ArgumentError getpoint(BARRA{BARRAR2,AUS11}, :tasmax;
            lon=145.0, lat=-37.8, date=Date(2020,1,1))
    end
end
