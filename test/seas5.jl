using PointDataSources, RasterDataSources, Test, Dates
using PointDataSources: NCDatasets, Extent, _seas5_cell, _seas5_times, _read_seas5_point
using .NCDatasets: NCDataset, defDim, defVar

# Synthetic stand-ins for CDS's SEAS5 NetCDF output (no CDS key in CI).
# `value(lon, lat, lead, member)` makes every cell distinguishable.
value(x, y, l, m) = 1000x + 100y + 10l + m

function write_seas5(path; lons=[145.0, 146.0], lats=[-37.0, -38.0], nlead=3,
        members=0:2, order=(:lon, :lat, :lead, :member, :ref), leadname="forecast_period",
        member_coord=true, extra_valid_time=false)
    dimname = Dict(:lon => "longitude", :lat => "latitude", :lead => leadname,
        :member => "number", :ref => "forecast_reference_time")
    len = Dict(:lon => length(lons), :lat => length(lats), :lead => nlead,
        :member => members === nothing ? 0 : length(members), :ref => 1)
    dims = members === nothing ? filter(!=(:member), order) : order
    data = [begin
        i = Dict(zip(dims, I.I))
        value(lons[i[:lon]], lats[i[:lat]], i[:lead], members === nothing ? 0 : members[i[:member]])
    end for I in CartesianIndices(Tuple(len[d] for d in dims))]
    NCDataset(path, "c") do ds
        foreach(d -> defDim(ds, dimname[d], len[d]), dims)
        defVar(ds, "longitude", lons, ("longitude",))
        defVar(ds, "latitude", lats, ("latitude",))
        members !== nothing && member_coord && defVar(ds, "number", collect(members), ("number",))
        extra_valid_time && defVar(ds, "valid_time", zeros(1, nlead), ("forecast_reference_time", leadname))
        defVar(ds, "t2m", data, Tuple(dimname[d] for d in dims); attrib=["units" => "K"])
    end
    path
end

@testset "SEAS5 point" begin
    @test PointDataSources.pointbackend(SEAS5) == CDSBackend()
    @test PointDataSources.pointbackend(SEAS5Monthly) == CDSBackend()
    @test getpoint_keywords(SEAS5Monthly) == (:date, :leadtime, :product_type, :system)

    @test _seas5_cell(145.3, -37.8) == Extent(X=(145.0, 146.0), Y=(-38.0, -37.0))
    @test _seas5_cell(145.0, -38.0) == Extent(X=(145.0, 146.0), Y=(-38.0, -37.0))
    @test _seas5_cell(180.0, 90.0) == Extent(X=(179.0, 180.0), Y=(89.0, 90.0))
    @test _seas5_cell(-180.0, -90.0) == Extent(X=(-180.0, -179.0), Y=(-90.0, -89.0))
    @test_throws ArgumentError _seas5_cell(200.0, 0.0)
    @test_throws ArgumentError _seas5_cell(0.0, -91.0)

    @test _seas5_times(SEAS5, Date(2026, 9, 1), [24, 30]) == [DateTime(2026, 9, 2), DateTime(2026, 9, 2, 6)]
    @test _seas5_times(SEAS5Monthly, Date(2026, 11, 1), [1, 2, 3]) == [Date(2026, 11, 1), Date(2026, 12, 1), Date(2027, 1, 1)]

    mktempdir() do dir
        # Nearest point to (145.3, -37.8) is (145, -38); values come back
        # as lead × member regardless of the file's dimension order.
        expected = [value(145.0, -38.0, l, m) for l in 1:3, m in 0:2]

        a = write_seas5(joinpath(dir, "a.nc"))
        nt = _read_seas5_point(SEAS5, a; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=[24, 48, 72])
        @test nt.values == expected
        @test nt.members == [0, 1, 2]
        @test nt.units == "K"
        @test nt.times == DateTime(2026, 9, 1) .+ Hour.([24, 48, 72])

        # Layout of a real CDS download: the whole-degree request box holds a
        # single grid point at the cell centre, dims in this order.
        r = write_seas5(joinpath(dir, "real.nc"); lons=[144.5], lats=[-37.5],
            order=(:lon, :lat, :lead, :ref, :member), members=0:50)
        nt = _read_seas5_point(SEAS5, r; lon=144.96, lat=-37.81, date=Date(2026, 9, 1), leadtime=[24, 48, 72])
        @test nt.values == [value(144.5, -37.5, l, m) for l in 1:3, m in 0:50]
        @test nt.members == 0:50

        # Member-first order, monthly lead axis name, no member coordinate,
        # and a 2-D valid_time coordinate that must not be taken as data.
        b = write_seas5(joinpath(dir, "b.nc"); order=(:member, :ref, :lead, :lat, :lon),
            leadname="forecastMonth", member_coord=false, extra_valid_time=true)
        nt = _read_seas5_point(SEAS5Monthly, b; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=[1, 2, 3])
        @test nt.values == expected
        @test nt.members == [0, 1, 2]
        @test nt.times == [Date(2026, 9, 1), Date(2026, 10, 1), Date(2026, 11, 1)]

        # Ensemble-mean products have no member dimension.
        c = write_seas5(joinpath(dir, "c.nc"); members=nothing)
        nt = _read_seas5_point(SEAS5Monthly, c; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=[1, 2, 3])
        @test nt.values == reshape([value(145.0, -38.0, l, 0) for l in 1:3], 3, 1)
        @test nt.members === nothing

        # A lead-time count that doesn't match the file must error, not
        # silently mislabel values.
        @test_throws ErrorException _read_seas5_point(SEAS5, a; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=[24, 48])
        # Points outside the downloaded cell are rejected by the tolerance check.
        @test_throws ArgumentError _read_seas5_point(SEAS5, a; lon=150.0, lat=-37.8, date=Date(2026, 9, 1), leadtime=[24, 48, 72])
    end

    # End to end through `getraster`'s cache: a file already at the path
    # `getraster` would download to is used without any CDS request or key.
    mktempdir() do dir
        withenv("RASTERDATASOURCES_PATH" => dir, "CDSAPI_KEY" => nothing, "HOME" => dir, "USERPROFILE" => dir) do
            extent = _seas5_cell(145.3, -37.8)
            for (var, init) in (("2m_temperature", Date(2026, 9, 1)), ("2m_dewpoint_temperature", Date(2026, 9, 1)),
                                ("2m_temperature", Date(2026, 10, 1)))
                path = RasterDataSources.rasterpath(SEAS5, (var,); date=init, extent, leadtime=[24, 48, 72], system="51")
                mkpath(dirname(path))
                write_seas5(path)
            end
            nt = getpoint(SEAS5, "2m_temperature"; lon=145.3, lat=-37.8, date=Date(2026, 9, 15), leadtime=24:24:72)
            @test size(nt.values) == (3, 3)
            @test first(nt.times) == DateTime(2026, 9, 2)

            both =getpoint(SEAS5, ["2m_temperature", "2m_dewpoint_temperature"]; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=24:24:72)
            @test keys(both) == (Symbol("2m_temperature"), Symbol("2m_dewpoint_temperature"))

            series = getpoint(SEAS5, "2m_temperature"; lon=145.3, lat=-37.8, date=(Date(2026, 9, 1), Date(2026, 10, 1)), leadtime=24:24:72)
            @test length(series) == 2
            @test first(series[2].times) == DateTime(2026, 10, 2)
        end
    end

    @test_throws ArgumentError getpoint(SEAS5; lon=145.3, lat=-37.8, date=Date(2026, 9, 1))
    @test_throws ArgumentError getpoint(SEAS5, "2m_temperature"; lon=145.3, lat=-37.8, date=Date(2026, 9, 1), leadtime=7)
end
