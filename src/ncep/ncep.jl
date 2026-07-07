pointbackend(::Type{<:NCEP}) = OpenDAPBackend()
getpoint_keywords(::Type{<:NCEP}) = (:date,)
pointlayers(T::Type{<:NCEP}) = RasterDataSources.layers(T)

const NCEP_OPENDAP_BASE = "https://psl.noaa.gov/thredds/dodsC/Datasets/ncep."

function _ncep_opendap_url(T::Type{<:NCEP}, layer::Symbol; date)
    R = RasterDataSources.reanalysis(T)
    base = "$(NCEP_OPENDAP_BASE)$(RasterDataSources._dataset_dir(R))/"
    path = join(RasterDataSources._category_dir(T), "/")
    name = RasterDataSources.rastername(T, layer; date)
    "$base$path/$name"
end

# NetCDF variable name = first dot-token of the filename part (e.g. "pres.sfc" -> "pres").
_ncep_varname(T, layer) = first(split(RasterDataSources._filename_part(T, layer), "."))

@doc """
    getpoint(::Type{<:NCEP}, layer; lon, lat, date, level=nothing)

Point time series from NCEP's THREDDS OPeNDAP endpoint. Layers depend on
the `NCEP{Group,Reanalysis,Period}` type parameters, as for `getraster` --
see `RasterDataSources.layers(T)`. `PressureLevels` layers need a `level`
keyword (hPa); `Surface`/`SurfaceFlux` don't. `lon` is -180..180, converted
internally to NCEP's native 0-360°E grid.
""" getpoint(::Type{<:NCEP}, ::Symbol; kw...)

function getpoint(T::Type{<:NCEP}, layer::Symbol; lon, lat, date, level=nothing)
    layer in RasterDataSources.layers(T) || throw(ArgumentError(
        "NCEP layer `$layer` not in $(RasterDataSources.layers(T))"
    ))
    start, finish = _point_daterange(date)
    dates_seq = _periods_spanned(RasterDataSources.date_step(T), Date(start), Date(finish))
    times, values, units = _concat_over_files(dates_seq, d -> _retry() do
        NCDataset(_ncep_opendap_url(T, layer; date=d)) do ds
            lonv, latv = Float64.(ds["lon"][:]), Float64.(ds["lat"][:])
            loni = _nearest_index(lonv, _normalize_lon(lonv, lon), _half_cell(lonv))
            lati = _nearest_index(latv, lat, _half_cell(latv))
            t = DateTime.(ds["time"][:])
            i0, i1 = findfirst(>=(start), t), findlast(<=(finish), t)
            (i0 === nothing || i1 === nothing || i0 > i1) && return (DateTime[], Float64[], "")
            var = ds[_ncep_varname(T, layer)]
            u = haskey(var.attrib, "units") ? var.attrib["units"] : ""
            if haskey(ds, "level")
                level === nothing && throw(ArgumentError("`level` keyword (hPa) is required for NCEP layer `$layer`"))
                li = _nearest_index(ds["level"][:], Float64(level))
                vals = Float64.(var[loni, lati, li, i0:i1])
            else
                vals = Float64.(var[loni, lati, i0:i1])
            end
            return (t[i0:i1], vals, u)
        end
    end)
    isempty(times) && throw(ArgumentError("no data for NCEP layer `$layer` in date range $start..$finish"))
    return (; times, values, units)
end
