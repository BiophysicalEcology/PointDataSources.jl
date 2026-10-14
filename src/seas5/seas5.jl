const _AbstractSEAS5 = RasterDataSources.AbstractSEAS5

pointbackend(::Type{<:_AbstractSEAS5}) = CDSBackend()
getpoint_keywords(::Type{SEAS5}) = (:date, :leadtime, :system)
getpoint_keywords(::Type{SEAS5Monthly}) = (:date, :leadtime, :product_type, :system)

# Dimension names as written by CDS's GRIB-to-NetCDF conversion (and its
# CF/xarray-style alternatives) -- matched by name, not position, so the
# reader doesn't depend on the file's dimension order.
const _SEAS5_LON_DIMS = ("longitude", "lon")
const _SEAS5_LAT_DIMS = ("latitude", "lat")
const _SEAS5_MEMBER_DIMS = ("number", "realization", "member")

# CDS serves SEAS5 on a 1° grid with points at whole degrees. Requesting the
# whole surrounding cell means the area always holds grid points on both
# sides of the point, and every point in that cell shares one cached file.
function _seas5_cell(lon::Real, lat::Real)
    (-180 <= lon <= 180 && -90 <= lat <= 90) || throw(ArgumentError(
        "`lon`/`lat` must lie within [-180, 180]/[-90, 90], got ($lon, $lat)"
    ))
    x0 = min(floor(lon), 179.0)
    y0 = min(floor(lat), 89.0)
    Extent(X=(x0, x0 + 1), Y=(y0, y0 + 1))
end

# Forecasts start at 00 UTC on the 1st of the initialisation month.
_seas5_times(::Type{SEAS5}, init::Date, leadtime) = DateTime(init) .+ Hour.(leadtime)
_seas5_times(::Type{SEAS5Monthly}, init::Date, leadtime) = init .+ Month.(leadtime .- 1)

_find_dim(dims, names) = something(findfirst(in(names), dims), 0)

# The one variable on the lon/lat grid; the rest are coordinates (time,
# lead time, member, valid time).
function _seas5_datavar(ds)
    names = filter(keys(ds)) do k
        d = NCDatasets.dimnames(ds[k])
        any(in(_SEAS5_LON_DIMS), d) && any(in(_SEAS5_LAT_DIMS), d)
    end
    length(names) == 1 || error(
        "expected exactly one gridded data variable in SEAS5 file, found $(collect(names))"
    )
    ds[only(names)]
end

"""
    _read_seas5_point(T, path; lon, lat, date, leadtime)

Nearest grid point's `(times, values, members, units)` from a SEAS5 NetCDF
file holding one variable. `values` is `length(leadtime) × n_members`;
lead times come from the request (CDS returns exactly those, ascending), not
from the file's lead-time coordinate, whose encoding varies.
"""
function _read_seas5_point(T, path; lon, lat, date, leadtime)
    NCDataset(path) do ds
        var = _seas5_datavar(ds)
        dims = collect(NCDatasets.dimnames(var))
        lond = dims[_find_dim(dims, _SEAS5_LON_DIMS)]
        latd = dims[_find_dim(dims, _SEAS5_LAT_DIMS)]
        lonv, latv = Float64.(ds[lond][:]), Float64.(ds[latd][:])
        loni = _nearest_index(lonv, _normalize_lon(lonv, lon), _half_cell(lonv))
        lati = _nearest_index(latv, lat, _half_cell(latv))

        idx = map(d -> d == lond ? loni : d == latd ? lati : Colon(), dims)
        data = var[idx...]
        rest = filter(d -> d != lond && d != latd, dims)

        # Member axis last, so a column-major reshape gives (lead, member).
        mi = _find_dim(rest, _SEAS5_MEMBER_DIMS)
        if mi > 0
            data = permutedims(data, [setdiff(1:length(rest), mi); mi])
        end
        nmem = mi > 0 ? size(data, ndims(data)) : 1
        other = mi > 0 ? size(data)[1:end-1] : size(data)
        # Anything besides lead time (forecast reference time, a level) must
        # be a length-1 axis, or values from different axes would interleave.
        (prod(other) == length(leadtime) && count(>(1), other) <= 1) || error(
            "SEAS5 file dimensions $(Tuple(rest)) of size $(size(data)) don't " *
            "match $(length(leadtime)) requested lead times"
        )
        values = reshape(Float64[ismissing(x) ? NaN : x for x in data], length(leadtime), nmem)
        members = if mi == 0
            nothing
        elseif haskey(ds, rest[mi])
            Int.(ds[rest[mi]][:])
        else
            collect(0:nmem-1)
        end
        units = haskey(var.attrib, "units") ? var.attrib["units"] : ""
        times = _seas5_times(T, date, leadtime)
        return (; times, values, members, units)
    end
end

@doc """
    getpoint(::Type{SEAS5}, variable; lon, lat, date, leadtime, system)
    getpoint(::Type{SEAS5Monthly}, variable; lon, lat, date, leadtime, product_type, system)

Ensemble forecast at a point from ECMWF SEAS5, via the CDS API. There is no
point endpoint for the seasonal datasets, so this downloads the 1° grid cell
containing the point through `RasterDataSources.getraster` (queued CDS
request, cached, shared by every point in that cell), then reads the
nearest grid point. Needs a CDS API key, as for `getraster`.

`variable` is a CDS variable name (`String` or `Symbol`, e.g.
`"2m_temperature"`); each variable is a separate download. A `Tuple`/`Vector`
of variables returns a `NamedTuple` keyed by variable. `date` is the
initialisation month; a `Tuple` of start/end dates or a `Vector` returns a
`Vector`, one forecast per initialisation month. Other keywords and their
defaults are as for `getraster(SEAS5, ...)`.

Returns `(times, values, members, units)`:
- `times`: valid times -- `DateTime`s (initialisation + lead hours) for
    `SEAS5`, the first `Date` of each forecast month for `SEAS5Monthly`.
- `values`: `Matrix{Float64}`, lead time × ensemble member (`NaN` where
    missing). Products without members (`"ensemble_mean"`,
    `"hindcast_climate_mean"`) have one column.
- `members`: ensemble member numbers, or `nothing` for those products.

Accumulated variables (e.g. `"total_precipitation"`, radiation fluxes) are
accumulated from the forecast start, as delivered by CDS -- difference along
`times` (`diff(values; dims=1)`) for per-step totals.
""" getpoint(::Type{<:_AbstractSEAS5}, ::Union{AbstractString,Symbol}; kw...)

function getpoint(T::Type{<:_AbstractSEAS5}, variable::Union{AbstractString,Symbol}; lon, lat, date, kw...)
    extent = _seas5_cell(lon, lat)
    leadtime = RasterDataSources._check_seas5_leadtime(
        T, get(kw, :leadtime, RasterDataSources._seas5_default_leadtime(T))
    )
    _each_init(T, date) do init
        path = RasterDataSources.getraster(T, string(variable); date=init, extent, kw...)
        _read_seas5_point(T, path; lon, lat, date=init, leadtime)
    end
end

# CDS queues each request; a few at a time keeps within its per-user limits.
const _SEAS5_CONCURRENT_REQUESTS = 4

_each_init(f, T, date::Dates.TimeType) = f(_period_start(Month, Date(date)))
_each_init(f, T, dates) = asyncmap(
    d -> f(_period_start(Month, Date(d))),
    RasterDataSources.date_sequence(T, dates);
    ntasks=_SEAS5_CONCURRENT_REQUESTS,
)

function getpoint(T::Type{<:_AbstractSEAS5}, variables::Union{Tuple,AbstractArray}; kw...)
    names = Tuple(unique(Symbol.(collect(variables))))
    isempty(names) && throw(ArgumentError("at least one SEAS5 variable must be specified"))
    results = asyncmap(v -> getpoint(T, v; kw...), names; ntasks=_SEAS5_CONCURRENT_REQUESTS)
    NamedTuple{names}(Tuple(results))
end

# Open-ended CDS variable catalogue, as for `getraster` -- no layer list to
# fall back to.
getpoint(T::Type{<:_AbstractSEAS5}; kw...) = throw(ArgumentError(
    "variables must be specified, e.g. getpoint($T, \"2m_temperature\"; lon, lat, date)"
))
