pointbackend(::Type{SILO}) = RestCSVBackend()
getpoint_keywords(::Type{SILO}) = (:date, :username)

# monthly_rain and et_morton_wet have no letter code on this API.
const SILO_POINT_CODE = (
    daily_rain=:R, max_temp=:X, min_temp=:N, rh_tmin=:G, rh_tmax=:H,
    radiation=:J, evap_pan=:E, vp_deficit=:D, et_short_crop=:F,
    et_morton_potential=:P, vp=:V, mslp=:M, evap_syn=:S, et_tall_crop=:T,
    et_morton_actual=:B, evap_morton_lake=:A,
)
const SILO_POINT_LAYERS = keys(SILO_POINT_CODE)
pointlayers(::Type{SILO}) = SILO_POINT_LAYERS
const SILO_DATADRILL_URL = "https://www.longpaddock.qld.gov.au/cgi-bin/silo/DataDrillDataset.php"

@doc """
    getpoint(::Type{SILO}, layer; lon, lat, date, username)

Point time series from SILO's DataDrill point-query API (server-side
spatial interpolation, no grid access). `username` is an email, required
by SILO, defaulting to `ENV["SILO_EMAIL"]`. Layers: `$(SILO_POINT_LAYERS)`
(`monthly_rain`/`et_morton_wet` excluded -- no letter code on this API).
""" getpoint(::Type{SILO}, ::Symbol; kw...)

function getpoint(T::Type{SILO}, layer::Symbol; lon, lat, date, username=get(ENV, "SILO_EMAIL", ""))
    layer in SILO_POINT_LAYERS || throw(ArgumentError(
        "SILO layer `$layer` is not available via the point API; available: $SILO_POINT_LAYERS"
    ))
    isempty(username) && throw(ArgumentError(
        "SILO requires an email as `username` keyword or ENV[\"SILO_EMAIL\"]"
    ))
    start, finish = _point_daterange(date)
    units = RasterDataSources.SILO_LAYERS[layer].units
    resp = _retry() do
        HTTP.get(SILO_DATADRILL_URL; query=Dict(
            "lat"=>string(lat), "lon"=>string(lon),
            "start"=>Dates.format(start, "yyyymmdd"), "finish"=>Dates.format(finish, "yyyymmdd"),
            "format"=>"csv", "comment"=>string(SILO_POINT_CODE[layer]),
            "username"=>username, "dataset"=>"Official",
        ))
    end
    tbl = CSV.File(resp.body)
    datecol = Symbol("YYYY-MM-DD")
    valid = .!ismissing.(tbl[datecol])
    times = Date.(tbl[datecol][valid])
    values = Float64.(getproperty(tbl, layer)[valid])
    return (; times, values, units)
end
