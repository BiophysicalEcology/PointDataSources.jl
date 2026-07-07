module PointDataSources
@doc let
    path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end PointDataSources

using Dates
using URIs
using HTTP
using CSV
using JSON
using NCDatasets
import RasterDataSources
using RasterDataSources: GRIDMET, NCEP, BARRA, SILO, SoilGrids
using RasterDataSources: Surface, PressureLevels, SurfaceFlux, SixHour
using RasterDataSources: BARRAR2, BARRAC2, AUS11, AUST11, AUST04
using RasterDataSources: depths

export GRIDMET, NCEP, BARRA, SILO, SoilGrids
export Surface, PressureLevels, SurfaceFlux, SixHour
export BARRAR2, BARRAC2, AUS11, AUST11, AUST04
export getpoint, pointlayers, getpoint_keywords, pointbackend
export OpenDAPBackend, RestCSVBackend, RestJSONBackend, ZarrBackend

include("interface.jl")
include("shared.jl")

include("gridmet/gridmet.jl")
include("ncep/ncep.jl")
include("barra/barra.jl")
include("silo/silo.jl")
include("soilgrids/soilgrids.jl")

end
