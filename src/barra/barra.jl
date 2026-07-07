using RasterDataSources: BARRAR2, BARRAC2, AUS11, AUST11, AUST04

pointbackend(::Type{<:BARRA}) = OpenDAPBackend()
getpoint_keywords(::Type{<:BARRA}) = (:date,)
pointlayers(T::Type{<:BARRA}) = RasterDataSources.layers(T)

const BARRA_OPENDAP_BASE = URI(scheme="https", host="thredds.nci.org.au",
    path="/thredds/dodsC/ob53/output/reanalysis")

function _barra_opendap_url(T::Type{<:BARRA{P,D}}, layer::Symbol; date) where {P,D}
    freqdir = RasterDataSources._is_static(layer) ? "fx" : RasterDataSources._freq_token(RasterDataSources.frequency(T))
    string(joinpath(BARRA_OPENDAP_BASE, RasterDataSources._domain_name(D), "BOM", "ERA5", "historical", "hres",
        RasterDataSources._product_name(P), "v1", freqdir, string(layer), "latest",
        RasterDataSources.rastername(T, layer; date)))
end

@doc """
    getpoint(::Type{<:BARRA}, layer; lon, lat, date)

Point time series from BARRA's THREDDS OPeNDAP endpoint. `date` is a `Date`
or `Tuple` of start/end dates, not required for static layers (`:orog`,
`:sftlf`). Layer availability follows `RasterDataSources.layers(T)` (e.g.
`tasmax` unavailable hourly for `BARRAR2`).
""" getpoint(::Type{<:BARRA}, ::Symbol; kw...)

function getpoint(T::Type{<:BARRA}, layer::Symbol; lon, lat, date=nothing)
    layer in RasterDataSources.layers(T) || throw(ArgumentError(
        "BARRA layer `$layer` not in $(RasterDataSources.layers(T))"
    ))
    is_static = RasterDataSources._is_static(layer)
    if is_static
        return _retry() do
            NCDataset(_barra_opendap_url(T, layer; date=nothing)) do ds
                lonv, latv = Float64.(ds["lon"][:]), Float64.(ds["lat"][:])
                loni = _nearest_index(lonv, lon, _half_cell(lonv))
                lati = _nearest_index(latv, lat, _half_cell(latv))
                var = ds[string(layer)]
                units = haskey(var.attrib, "units") ? var.attrib["units"] : ""
                v = ndims(var) == 2 ? var[loni, lati] : var[loni, lati, 1]
                (value=Float64(v), units)
            end
        end
    end
    date === nothing && throw(ArgumentError("`date` keyword is required for BARRA layer `$layer`"))
    start, finish = _point_daterange(date)
    dates_seq = _periods_spanned(RasterDataSources.date_step(T), Date(start), Date(finish))
    times, values, units = _concat_over_files(dates_seq, d -> _retry() do
        NCDataset(_barra_opendap_url(T, layer; date=d)) do ds
            lonv, latv = Float64.(ds["lon"][:]), Float64.(ds["lat"][:])
            loni = _nearest_index(lonv, lon, _half_cell(lonv))
            lati = _nearest_index(latv, lat, _half_cell(latv))
            var = ds[string(layer)]
            u = haskey(var.attrib, "units") ? var.attrib["units"] : ""
            t = DateTime.(ds["time"][:])
            i0, i1 = findfirst(>=(start), t), findlast(<=(finish), t)
            (i0 === nothing || i1 === nothing || i0 > i1) && return (DateTime[], Float64[], "")
            vals = Float64.(var[loni, lati, i0:i1])
            (t[i0:i1], vals, u)
        end
    end)
    isempty(times) && throw(ArgumentError("no data for BARRA layer `$layer` in date range $start..$finish"))
    return (; times, values, units)
end
