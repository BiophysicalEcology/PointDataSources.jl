# PointDataSources.jl

```@docs
PointDataSources
```

# getpoint

PointDataSources.jl exports a single function, `getpoint`.

```@docs
getpoint
```

```@docs
pointlayers
getpoint_keywords
pointbackend
```

Specific implementations are included with each source, below.

# Backends

```@docs
PointDataSources.PointBackend
OpenDAPBackend
RestCSVBackend
RestJSONBackend
ZarrBackend
```

# Sources

## GRIDMET

```@docs
getpoint(::Type{GRIDMET}, ::Symbol)
```

## NCEP

```@docs
getpoint(::Type{<:NCEP}, ::Symbol)
```

## BARRA

```@docs
getpoint(::Type{<:BARRA}, ::Symbol)
```

## SILO

```@docs
getpoint(::Type{SILO}, ::Symbol)
```

## SoilGrids

```@docs
getpoint(::Type{SoilGrids}, ::Symbol)
```

## ERA5

Requires `Rasters.jl` + `ZarrDatasets.jl` to be installed (loaded via the
`PointDataSourcesRastersExt` package extension).

```@docs
getpoint(::Type{ERA5}, ::Symbol)
```
