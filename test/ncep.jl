using PointDataSources, Test, Dates

@testset "NCEP point" begin
    @test PointDataSources.pointbackend(NCEP{Surface,2}) == PointDataSources.OpenDAPBackend()
    @test PointDataSources.getpoint_keywords(NCEP{Surface,2}) == (:date,)

    if !Sys.iswindows()
        # NCEP{Surface,2} is native 6-hourly -- 4 timesteps/day.
        nt = getpoint(NCEP{Surface,2}, :pres_sfc;
            lon=-120.5, lat=39.0, date=(Date(2020,1,1), Date(2020,1,10)))
        @test length(nt.times) == 40
        @test all(50000.0 .< nt.values .< 110000.0)

        @test_throws ArgumentError getpoint(NCEP{PressureLevels,1}, :hgt;
            lon=-120.5, lat=39.0, date=Date(2020,1,1))

        pl = getpoint(NCEP{PressureLevels,1}, :hgt;
            lon=-120.5, lat=39.0, date=Date(2020,1,1), level=850)
        @test length(pl.times) == 4
        @test all(pl.values .> 0)

        # SurfaceFlux gaussian-grid files carry a degenerate length-1 "level"
        # axis even for surface variables (4D, unlike Surface's plain 3D) --
        # no `level` keyword needed, but still real data (regression check
        # for a dimensionality bug that threw a BoundsError here before).
        sf = getpoint(NCEP{SurfaceFlux,2}, :tmax;
            lon=-120.5, lat=39.0, date=(Date(2020,1,1), Date(2020,1,2)))
        @test length(sf.times) == 8
        @test all(250.0 .< sf.values .< 330.0)
    end
end
