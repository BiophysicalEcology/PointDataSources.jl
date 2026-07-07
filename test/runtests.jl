using SafeTestsets

@time @safetestset "nearest_index" begin include("nearest_index.jl") end
@time @safetestset "gridmet" begin include("gridmet.jl") end
@time @safetestset "ncep" begin include("ncep.jl") end
@time @safetestset "barra" begin include("barra.jl") end
@time @safetestset "silo" begin include("silo.jl") end
@time @safetestset "soilgrids" begin include("soilgrids.jl") end
@time @safetestset "era5" begin include("era5.jl") end
