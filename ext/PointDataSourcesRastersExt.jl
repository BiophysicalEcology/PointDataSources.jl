module PointDataSourcesRastersExt

using PointDataSources
using RasterDataSources: ERA5, ARCO_ERA5_URL, layername
import RasterDataSources
using Rasters
using ZarrDatasets
using Dates

import PointDataSources: getpoint, pointbackend, getpoint_keywords, pointlayers, ZarrBackend

pointbackend(::Type{ERA5}) = ZarrBackend()
getpoint_keywords(::Type{ERA5}) = (:date,)
pointlayers(T::Type{ERA5}) = RasterDataSources.layers(T)

@doc """
    getpoint(::Type{ERA5}, layer; lon, lat, date)

Point time series from the ARCO-ERA5 Zarr store, via `Rasters.jl` +
`ZarrDatasets.jl` (only exists once both are loaded, as a package
extension).
""" getpoint(::Type{ERA5}, ::Symbol; kw...)

# This Zarr V3 store has no decoded coordinates -- ZarrDatasets.jl exposes
# lon/lat/time as raw NoLookup integer axes. Indices reconstructed manually
# from ERA5's 0.25deg grid (lon 0..359.75E, lat 90..-90) and ECMWF's "hours
# since 1900-01-01" epoch; verified live against known valid_time_start and
# a physically sane Alice Springs temperature.
const _ERA5_TIME_EPOCH = DateTime(1900, 1, 1)
_era5_time_index(dt::DateTime) = Int(Dates.value(dt - _ERA5_TIME_EPOCH) ÷ 3_600_000) + 1
_era5_lon_index(lon::Real) = round(Int, (lon < 0 ? lon + 360 : lon) / 0.25) + 1
_era5_lat_index(lat::Real) = round(Int, (90 - lat) / 0.25) + 1

function getpoint(T::Type{ERA5}, layer::Symbol; lon, lat, date)
    stack = RasterStack(ARCO_ERA5_URL; source=Rasters.Zarrsource(), lazy=true)
    start, finish = PointDataSources._point_daterange(date)

    md = Rasters.metadata(stack)
    valid_start = Date(md["valid_time_start"])
    valid_stop = Date(get(md, "valid_time_stop_era5t", md["valid_time_stop"]))
    (Date(start) < valid_start || Date(finish) > valid_stop) && throw(ArgumentError(
        "requested range $(Date(start))..$(Date(finish)) is outside ERA5's currently " *
        "valid data range $valid_start..$valid_stop"
    ))

    loni, lati = _era5_lon_index(lon), _era5_lat_index(lat)
    i0, i1 = _era5_time_index(DateTime(start)), _era5_time_index(DateTime(finish))
    r = stack[layername(T, layer)][X(loni), Y(lati), Ti(i0:i1)]
    times = collect(_ERA5_TIME_EPOCH .+ Hour.(i0-1:i1-1))
    values = Float64.(collect(r))
    return (times=times, values=values, units="")
end

end
