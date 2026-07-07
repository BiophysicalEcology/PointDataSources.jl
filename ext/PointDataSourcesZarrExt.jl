module PointDataSourcesZarrExt

using PointDataSources
using RasterDataSources: ERA5
using Zarr
using ZarrDatasets
using CommonDataModel
using HTTP
using Dates

import PointDataSources: getpoint, pointbackend, getpoint_keywords, pointlayers, ZarrBackend
import PointDataSources: _nearest_index, _half_cell, _point_daterange, _retry

pointbackend(::Type{ERA5}) = ZarrBackend()
getpoint_keywords(::Type{ERA5}) = (:date,)

# ECMWF's official ARCO Zarr mirror of the CDS "ERA5 hourly time-series data
# on single levels" product, geo-chunked (optimised for long time series at
# one point, unlike Google's ARCO-ERA5 bucket, which is chunked one hour x
# the whole globe per chunk -- fine for area reads, impractical for a single
# point's full time series). Needs a free CDS API key.
const _CDS_ARCO_SFC_URL = "https://arco.datastores.ecmwf.int/cadl-arco-geo-002/arco/reanalysis_era5_single_levels/sfc/geoChunked.zarr"

# "Name in file" column from the CDS ARCO product documentation -- these are
# used directly as the Zarr variable names (no long/short mapping needed).
const ERA5_ARCO_LAYERS = (
    :blh, :cbh, :d2m, :fdir, :fg10, :msl, :skt, :sp, :ssrd, :sst, :strd,
    :t2m, :tcc, :tp, :u10, :u100, :v10, :v100,
)
pointlayers(::Type{ERA5}) = ERA5_ARCO_LAYERS

# Bearer-token-authenticated HTTP store. Zarr.jl's built-in `HTTPStore`
# supports no custom headers at all, so a custom `AbstractStore` is needed --
# the interface only requires `Base.getindex(store, key) -> Vector{UInt8}`.
struct CDSStore <: Zarr.AbstractStore
    url::String
    headers::Vector{Pair{String,String}}
    allowed_codes::Set{Int}
end
CDSStore(url::AbstractString, token::AbstractString) =
    CDSStore(url, ["Authorization" => "Bearer $token"], Set((404, 403)))

function Base.getindex(s::CDSStore, k::AbstractString)
    r = _retry(; sleep=1) do
        HTTP.get(string(s.url, "/", k), s.headers; status_exception=false)
    end
    if r.status >= 300
        r.status in s.allowed_codes ? nothing : throw(ErrorException(
            "HTTP $(r.status) fetching $k from $(s.url)"
        ))
    else
        r.body
    end
end
Zarr.missing_chunk_return_code!(s::CDSStore, code::Integer) = push!(s.allowed_codes, code)
Zarr.missing_chunk_return_code!(s::CDSStore, codes::AbstractVector{<:Integer}) =
    foreach(c -> push!(s.allowed_codes, c), codes)
Zarr.store_read_strategy(::CDSStore) = Zarr.ConcurrentRead(Zarr.concurrent_io_tasks[])

function _cds_api_key()
    key = get(ENV, "CDS_API_KEY", "")
    isempty(key) && throw(ArgumentError(
        "ERA5 point access needs a free CDS API key -- register at " *
        "https://cds.climate.copernicus.eu, accept the ERA5-reanalysis terms, " *
        "then set ENV[\"CDS_API_KEY\"]"
    ))
    key
end

# Builds a getindex index tuple matching `v`'s actual dimension order (CF/
# xarray-written stores conventionally order dims (time, lat, lon), not
# (lon, lat, time) -- this reads the real order rather than assuming one).
function _point_index(v, loni::Int, lati::Int, timerange::UnitRange{Int})
    lookup = Dict("longitude" => loni, "latitude" => lati, "time" => timerange)
    return Tuple(
        get(lookup, d) do
            throw(ArgumentError(
                "unexpected dimension `$d` on ERA5 ARCO variable -- expected " *
                "longitude/latitude/time"
            ))
        end
        for d in CommonDataModel.dimnames(v)
    )
end

@doc """
    getpoint(::Type{ERA5}, layer; lon, lat, date)

Point time series from ECMWF's geo-chunked CDS ARCO Zarr mirror of ERA5
(only exists once `ZarrDatasets.jl` is loaded, as a package extension).
Needs `ENV["CDS_API_KEY"]` -- see `PointDataSourcesZarrExt._cds_api_key`.
""" getpoint(::Type{ERA5}, ::Symbol; kw...)

function getpoint(T::Type{ERA5}, layer::Symbol; lon, lat, date)
    layer in ERA5_ARCO_LAYERS || throw(ArgumentError(
        "ERA5 layer `$layer` not available via the CDS ARCO surface store; " *
        "available: $ERA5_ARCO_LAYERS"
    ))
    start, finish = _point_daterange(date)

    store = Zarr.zopen(CDSStore(_CDS_ARCO_SFC_URL, _cds_api_key()), "r"; consolidated=true)
    ds = ZarrDatasets.ZarrDataset(store)

    lonv, latv = ds["longitude"][:], ds["latitude"][:]
    loni = _nearest_index(Float64.(lonv), Float64(lon), _half_cell(lonv))
    lati = _nearest_index(Float64.(latv), Float64(lat), _half_cell(latv))

    t = ds["time"][:]
    dates = Date.(t)
    i0 = findfirst(>=(Date(start)), dates)
    i1 = findlast(<=(Date(finish)), dates)
    (i0 === nothing || i1 === nothing) && throw(ArgumentError(
        "requested range $(Date(start))..$(Date(finish)) is outside this store's time coverage"
    ))

    v = ds[string(layer)]
    vals = Float64.(v[_point_index(v, loni, lati, i0:i1)...])
    units = get(v.attrib, "units", "")
    return (times=collect(t[i0:i1]), values=vals, units=units)
end

end
