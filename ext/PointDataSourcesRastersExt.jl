module PointDataSourcesRastersExt

using PointDataSources
using RasterDataSources: ERA5, ARCO_ERA5_URL, layername
import RasterDataSources
using Rasters
using Rasters.DimensionalData: dims
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

function getpoint(T::Type{ERA5}, layer::Symbol; lon, lat, date)
    stack = RasterStack(ARCO_ERA5_URL; source=Rasters.Zarrsource(), lazy=true)
    start, finish = PointDataSources._point_daterange(date)
    r = stack[layername(T, layer)][X(Near(lon)), Y(Near(lat)), Ti(start .. finish)]
    times = Date.(collect(dims(r, Ti)))
    values = Float64.(collect(r))
    return (times=times, values=values, units="")
end

end
