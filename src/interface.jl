"""
    getpoint(source::Type, [layer]; lon, lat, date, kw...)

Fetch a single point's time series (or static value) from `source`, without
downloading a whole raster file. Mirrors `RasterDataSources.getraster`'s
`(source, [layer]; kw...)` convention, returning values directly instead of
a file path. `source` is one of RasterDataSources.jl's existing types
(`GRIDMET`, `NCEP`, `BARRA`, `SILO`, `SoilGrids`, `ERA5`).

# Keywords
- `lon`, `lat`: decimal degrees.
- `date`: a `Date`/`DateTime`, or a `Tuple` of start/end dates. Not required
    for static layers.
- Other keywords are source-specific (`depth`/`quantile` for `SoilGrids`,
    `username` for `SILO`) -- see each source's docstring.

Returns a `NamedTuple`: `(times, values, units)` for time-series layers
(`times` is `Vector{Date}` or `Vector{DateTime}` depending on the source's
native resolution), or `(value, units)` for static layers. Without a
`layer` argument, returns a `NamedTuple` of these keyed by layer name.
"""
function getpoint end

getpoint(T::Type, layers::Union{Tuple,AbstractArray}; kw...) =
    NamedTuple{Tuple(layers)}(map(l -> getpoint(T, l; kw...), Tuple(layers)))
getpoint(T::Type; kw...) = getpoint(T, RasterDataSources.layers(T); kw...)

"""
    getpoint_keywords(source::Type) -> NTuple{N,Symbol}

Keywords `getpoint` accepts for `source`, mirroring `getraster_keywords`.
"""
function getpoint_keywords end

"""
    pointlayers(source::Type) -> Tuple

Subset of `RasterDataSources.layers(source)` retrievable via `getpoint`
(some layers have no working point access -- see each source's docstring).
"""
function pointlayers end

"""
    pointbackend(source::Type) -> PointBackend

Which remote-access mechanism `source` uses for point extraction.
Informational only -- each source's `getpoint` implements what its own
backend needs.
"""
function pointbackend end

abstract type PointBackend end

"Point access via a THREDDS `dodsC` (OPeNDAP) URL, nearest-cell slice. Used by `GRIDMET`, `NCEP`, `BARRA`."
struct OpenDAPBackend <: PointBackend end

"Point access via a server-side point-query CSV API (no grid access). Used by `SILO`."
struct RestCSVBackend <: PointBackend end

"Point access via a server-side point-query JSON API. Used by `SoilGrids`."
struct RestJSONBackend <: PointBackend end

"Point access via a cloud-optimised Zarr store (`PointDataSourcesRastersExt`). Used by `ERA5`."
struct ZarrBackend <: PointBackend end
