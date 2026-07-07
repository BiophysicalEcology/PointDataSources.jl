using PointDataSources, RasterDataSources, Test, Dates

@testset "ERA5 point (extension)" begin
    ext = Base.get_extension(PointDataSources, :PointDataSourcesRastersExt)
    if ext === nothing
        @test_skip "Rasters.jl/ZarrDatasets.jl not loaded -- ERA5 point extension inactive"
    else
        @test PointDataSources.pointbackend(ERA5) == PointDataSources.ZarrBackend()
        if !Sys.iswindows()
            nt = getpoint(ERA5, :t2m; lon=145.0, lat=-37.8, date=(DateTime(2020,1,1), DateTime(2020,1,1,3)))
            @test length(nt.times) >= 1
        end
    end
end
