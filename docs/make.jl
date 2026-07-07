using Documenter
using PointDataSources

makedocs(;
    modules=[PointDataSources],
    sitename="PointDataSources.jl",
    pages=["Home" => "index.md"],
)
