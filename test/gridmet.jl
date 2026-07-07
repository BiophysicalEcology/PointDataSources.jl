using PointDataSources, Test, Dates

@testset "GRIDMET point" begin
    @test PointDataSources.pointbackend(GRIDMET) == PointDataSources.OpenDAPBackend()
    @test PointDataSources.getpoint_keywords(GRIDMET) == (:date,)
    @test :tmmx in pointlayers(GRIDMET)
    @test !(:fm1 in pointlayers(GRIDMET))
    @test !(:spi in pointlayers(GRIDMET))

    if !Sys.iswindows()
        nt = getpoint(GRIDMET, :tmmx; lon=-120.5, lat=39.0, date=(Date(2020,1,1), Date(2020,1,10)))
        @test length(nt.times) == 10
        @test nt.times[1] == Date(2020,1,1)
        @test all(250.0 .< nt.values .< 320.0)
        @test nt.units == "K"

        elev = getpoint(GRIDMET, :elev; lon=-120.5, lat=39.0)
        @test elev.value > 0
        @test elev.units == "m"
    end
end
