using Documenter
using NetworkDynamic

DocMeta.setdocmeta!(NetworkDynamic, :DocTestSetup, :(using NetworkDynamic); recursive=true)

makedocs(
    sitename = "NetworkDynamic.jl",
    modules = [NetworkDynamic],
    authors = "Statistical Network Analysis with Julia",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://Statistical-network-analysis-with-Julia.github.io/NetworkDynamic.jl",
        edit_link = "main",
    ),
    repo = Documenter.Remotes.GitHub("Statistical-network-analysis-with-Julia", "NetworkDynamic.jl"),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "User Guide" => [
            "Dynamic Networks" => "guide/dynamic_networks.md",
            "Spells and Activity" => "guide/spells.md",
            "Time Queries" => "guide/queries.md",
        ],
        "API Reference" => [
            "Types" => "api/types.md",
            "Functions" => "api/functions.md",
        ],
    ],
    # STRICT. Undefined bindings, bad cross-references, duplicate docs and
    # malformed markdown are build ERRORS, so they cannot silently accumulate
    # again (a docs build that passes while warning is one that will rot).
    #
    # `checkdocs = :exports` is the one deliberate exclusion: every *exported*
    # name must be documented, but internal machinery (materialized/private
    # types, `Base`/`Graphs` method extensions, inner constructors) need not be
    # -- filler docstrings for names a user never types are worse than none.
    warnonly = false,
    checkdocs = :exports,
)

deploydocs(
    repo = "github.com/Statistical-network-analysis-with-Julia/NetworkDynamic.jl.git",
    devbranch = "main",
    versions = [
        "stable" => "dev",
        "dev" => "dev",
    ],
    push_preview = true,
)
