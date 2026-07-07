# PointDataSources.jl

`PointDataSources.jl` fetches a single point's time series (or static value)
directly from remote climate/soil data sources, without downloading a whole
raster file. Sibling package to
[RasterDataSources.jl](https://github.com/EcoJulia/RasterDataSources.jl):
`getpoint(source, [layer]; lon, lat, date...)` returns real values, mirroring
`getraster`'s convention but never writing a file to disk. Dispatches on
RasterDataSources.jl's existing source types rather than defining its own.

Currently supported:

| Source    | Access mechanism                          |
| --------- | ------------------------------------------ |
| GRIDMET   | THREDDS OPeNDAP, nearest-grid-cell slice    |
| NCEP      | THREDDS OPeNDAP, nearest-grid-cell slice    |
| BARRA     | THREDDS OPeNDAP, nearest-grid-cell slice    |
| SILO      | server-side point-query REST API (CSV)      |
| SoilGrids | server-side point-query REST API (JSON)     |
| ERA5      | cloud-optimised Zarr store (package extension, requires Rasters.jl + ZarrDatasets.jl) |

## Installation and setup

```julia
] add PointDataSources
```

## Usage

```julia
using PointDataSources, Dates

getpoint(GRIDMET, :tmmx; lon=-120.5, lat=39.0, date=(Date(2020,1,1), Date(2020,1,10)))
```
