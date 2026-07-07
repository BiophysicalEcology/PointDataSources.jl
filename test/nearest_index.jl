using PointDataSources: _nearest_index, _normalize_lon
using Test

@testset "_nearest_index" begin
    coord = [10.0, 20.0, 30.0, 40.0]
    @test _nearest_index(coord, 21.0) == 2
    @test _nearest_index(coord, 10.0) == 1
    @test _nearest_index(coord, 40.0) == 4
    @test _nearest_index(coord, 25.0) == 2  # tie -> first argmin

    @test _nearest_index(coord, 21.0, 5.0) == 2
    @test_throws ArgumentError _nearest_index(coord, 100.0, 5.0)
    @test_throws ArgumentError _nearest_index(Float64[], 1.0)
end

@testset "_normalize_lon" begin
    lon_0_360 = collect(0.0:1.0:359.0)
    @test _normalize_lon(lon_0_360, -123.0) == 237.0
    @test _normalize_lon(lon_0_360, 145.0) == 145.0

    lon_pm180 = collect(-180.0:1.0:179.0)
    @test _normalize_lon(lon_pm180, 145.0) == 145.0
    @test _normalize_lon(lon_pm180, -111.9) == -111.9
end
