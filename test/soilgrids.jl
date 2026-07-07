using PointDataSources, Test

@testset "SoilGrids point" begin
    @test PointDataSources.pointbackend(SoilGrids) == PointDataSources.RestJSONBackend()
    @test PointDataSources.getpoint_keywords(SoilGrids) == (:depth, :quantile)
    @test :soc in pointlayers(SoilGrids)

    if !Sys.iswindows()
        nt = getpoint(SoilGrids, :soc; lon=145.0, lat=-37.8)
        @test nt.value === missing || nt.value isa Real
        @test nt.units isa String
    end
end
