using Pkg
Pkg.activate(@__DIR__)
Pkg.develop(PackageSpec(path=joinpath(@__DIR__, "..")))
Pkg.instantiate()

using Documenter
using Bilge

const ON_CI = get(ENV, "CI", "false") == "true"

makedocs(
    sitename = "Bilge.jl",
    modules  = [Bilge],
    format   = Documenter.HTML(
        prettyurls = ON_CI,
        assets     = ["assets/theme.css"],
    ),
    pages    = [
        "Home" => "index.md",
        "Quick Start" => "quickstart.md",
        "User Guide" => Any[
            "REPL Interface"     => "repl.md",
            "Tools"              => "tools.md",
            "Configuration"      => "configuration.md",
            "Ollama Integration" => "ollama.md",
        ],
        "API Reference" => "api.md",
    ],
    checkdocs = :none,
)

deploydocs(
    repo      = "github.com/taf-society/Bilge.jl",
    devbranch = "main",
)
