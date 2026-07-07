pointbackend(::Type{GRIDMET}) = OpenDAPBackend()
getpoint_keywords(::Type{GRIDMET}) = (:date,)

# fm1 has no working OPeNDAP URL; spi/spei/eddi 404 even on plain HTTPS.
const GRIDMET_POINT_LAYERS = filter(
    !in((:fm1, :spi, :spei, :eddi)),
    RasterDataSources.layers(GRIDMET),
)
pointlayers(::Type{GRIDMET}) = GRIDMET_POINT_LAYERS

# OPeNDAP variable names don't match RasterDataSources' short symbols.
const GRIDMET_NC_VARNAME = (
    tmmx = "daily_maximum_temperature",
    tmmn = "daily_minimum_temperature",
    pr   = "precipitation_amount",
    rmax = "daily_maximum_relative_humidity",
    rmin = "daily_minimum_relative_humidity",
    sph  = "daily_mean_specific_humidity",
    srad = "daily_mean_shortwave_radiation_at_surface",
    th   = "daily_mean_wind_direction",
    vs   = "daily_mean_wind_speed",
    etr  = "daily_mean_reference_evapotranspiration_alfalfa",
    pet  = "daily_mean_reference_evapotranspiration_grass",
    vpd  = "daily_mean_vapor_pressure_deficit",
    erc  = "daily_mean_energy_release_component-g",
    bi   = "daily_mean_burning_index_g",
    fm100= "dead_fuel_moisture_100hr",
    pdsi = "daily_mean_palmer_drought_severity_index",
    z    = "daily_mean_palmer_z_index",  # not "category" -- verified trap
)

const GRIDMET_OPENDAP_BASE = "http://thredds.northwestknowledge.net:8080/thredds/dodsC/agg_met_"
const GRIDMET_ELEV_OPENDAP = "http://thredds.northwestknowledge.net:8080/thredds/dodsC/MET/elev/metdata_elevationdata.nc"

_gridmet_opendap_url(layer::Symbol) =
    layer === :elev ? GRIDMET_ELEV_OPENDAP : "$(GRIDMET_OPENDAP_BASE)$(layer)_1979_CurrentYear_CONUS.nc"

@doc """
    getpoint(::Type{GRIDMET}, layer; lon, lat, date)

Point time series from GRIDMET's THREDDS OPeNDAP endpoint. `date` is a
`Date` or `Tuple` of start/end dates, not required for `:elev`. Layers:
`$(GRIDMET_POINT_LAYERS)` (`fm1`/`spi`/`spei`/`eddi` excluded -- no working
OPeNDAP access).
""" getpoint(::Type{GRIDMET}, ::Symbol; kw...)

function getpoint(T::Type{GRIDMET}, layer::Symbol; lon, lat, date=nothing)
    layer in GRIDMET_POINT_LAYERS || throw(ArgumentError(
        "GRIDMET layer `$layer` not supported for point extraction; available: $GRIDMET_POINT_LAYERS"
    ))
    units = RasterDataSources.GRIDMET_LAYERS[layer].units
    _retry() do
        NCDataset(_gridmet_opendap_url(layer)) do ds
            lonv, latv = Float64.(ds["lon"][:]), Float64.(ds["lat"][:])
            loni = _nearest_index(lonv, _normalize_lon(lonv, lon), _half_cell(lonv))
            lati = _nearest_index(latv, lat, _half_cell(latv))
            if layer === :elev
                return (value=Float64(ds["elevation"][loni, lati, 1]), units)
            end
            date === nothing && throw(ArgumentError("`date` keyword is required for GRIDMET layer `$layer`"))
            t = Date.(ds["day"][:])  # CF-decoded to DateTime already; GRIDMET is daily-only
            start, finish = _point_daterange(date)
            i0, i1 = findfirst(>=(start), t), findlast(<=(finish), t)
            (i0 === nothing || i1 === nothing || i0 > i1) && throw(ArgumentError(
                "no data for GRIDMET layer `$layer` in date range $start..$finish"
            ))
            vals = Float64.(ds[GRIDMET_NC_VARNAME[layer]][loni, lati, i0:i1])
            return (times=t[i0:i1], values=vals, units)
        end
    end
end
