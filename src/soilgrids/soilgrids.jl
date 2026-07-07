pointbackend(::Type{SoilGrids}) = RestJSONBackend()
getpoint_keywords(::Type{SoilGrids}) = (:depth, :quantile)
pointlayers(T::Type{SoilGrids}) = RasterDataSources.layers(T)

const SOILGRIDS_REST_URL = "https://rest.isric.org/soilgrids/v2.0/properties/query"

@doc """
    getpoint(::Type{SoilGrids}, layer; lon, lat, depth="0-5cm", quantile="mean")

Point value from ISRIC's SoilGrids point-query REST API (a different ISRIC
service from the VRT tiles `getraster` uses). `depth` is one of
`RasterDataSources.depths(SoilGrids, layer)`; `quantile` is one of
`Q0.05, mean, Q0.5, Q0.95, uncertainty`.
""" getpoint(::Type{SoilGrids}, ::Symbol; kw...)

function getpoint(T::Type{SoilGrids}, layer::Symbol; lon, lat,
        depth=RasterDataSources._defdepth(T, Val(layer)), quantile="mean")
    layer in RasterDataSources.layers(T) || throw(ArgumentError("SoilGrids layer `$layer` not recognised"))
    depth in depths(T, layer) || throw(ArgumentError(
        "depth \"$depth\" not valid for layer `$layer`; valid: $(depths(T, layer))"
    ))
    resp = _retry(; sleep=5) do
        HTTP.get(SOILGRIDS_REST_URL; query=Dict(
            "lon"=>string(lon), "lat"=>string(lat), "property"=>string(layer),
            "depth"=>depth, "value"=>quantile,
        ))
    end
    body = JSON.parse(String(resp.body))
    entry = body["properties"]["layers"][1]["depths"][1]
    value = entry["values"][quantile]
    units = body["properties"]["layers"][1]["unit_measure"]["target_units"]
    return (value=value === nothing ? missing : Float64(value), units=units)
end
