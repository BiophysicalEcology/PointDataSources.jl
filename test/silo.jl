using PointDataSources, Test, Dates

@testset "SILO point" begin
    @test PointDataSources.pointbackend(SILO) == PointDataSources.RestCSVBackend()
    @test :daily_rain in pointlayers(SILO)
    @test !(:monthly_rain in pointlayers(SILO))
    @test !(:et_morton_wet in pointlayers(SILO))

    if !Sys.iswindows() && haskey(ENV, "SILO_EMAIL")
        nt = getpoint(SILO, :daily_rain; lon=145.0, lat=-37.8,
            date=(Date(2020,1,1), Date(2020,1,5)))
        @test length(nt.times) == 5
        @test all(nt.values .>= 0)
        @test nt.units == "mm"
    end
end
