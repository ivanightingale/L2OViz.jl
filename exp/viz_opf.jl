# exp/viz_opf.jl
# Utility function for visualizing OPF solution variables.

using CairoMakie
using L2OViz
using PGLib
using PowerModels

# Load branch and bus-pair connectivity (from-bus/to-bus indices) plus component counts
# from a PowerModels network dict. Bus pairs are the unique branch endpoint pairs, so
# parallel branches sharing endpoints collapse to a single pair.
function _get_power_system_data(network::Dict)
    branch_dict = network["branch"]
    sorted_branch_keys = sort(collect(keys(branch_dict)), by=k -> parse(Int, string(k)))
    I_branches = [branch_dict[k]["f_bus"] for k in sorted_branch_keys]
    J_branches = [branch_dict[k]["t_bus"] for k in sorted_branch_keys]
    n_branches = length(sorted_branch_keys)
    n_buses    = length(network["bus"])

    # Bus pairs are the unique (f_bus, t_bus) branch endpoints, kept in order of first
    # occurrence among the sorted branches; parallel branches collapse to a single pair.
    unique_buspairs = unique(zip(I_branches, J_branches))
    I_buspairs = [buspair[1] for buspair in unique_buspairs]
    J_buspairs = [buspair[2] for buspair in unique_buspairs]
    n_buspairs = length(unique_buspairs)

    return I_branches, J_branches, n_branches, n_buses, I_buspairs, J_buspairs, n_buspairs
end

"""
    viz_opf(network::Dict, variables, x, var_data::T...; kwargs...) where {T <: Union{Matrix, Dict}}
    viz_opf(system_identifier::String, variables, x, var_data...; kwargs...)

Visualize OPF solution variables and save one image per variable to `output_dir`.

Provide either a network data `Dict` similar to PowerModels format, or the name of the
system compatible with PGLib.jl, for which data is obtained with
`make_basic_network(pglib(system_identifier))`.

Two calling modes, determined by `T`:

- **`T <: Matrix`**: `variables` is a `String`; each `var_data` is a `Matrix`
  `(n_dim × n_instances)`, one per solver.
- **`T <: Dict`**: `variables` is a `Vector{String}`; each `var_data` is a `Dict` mapping
  variable names to matrices, one per solver.

`x` is either a single `Vector` (shared across solvers) or a `Vector` of `Vector`s (one per solver).

**Variable dispatch** (when `flat=false`):
- Dimension equals the number of **branches** → [`plot_graph_variable`](@ref), where `I`/`J` are 
  `f_bus`/`t_bus` in sorted branch key order.
- Dimension equals the number of **bus pairs** → [`plot_graph_variable`](@ref), where `I`/`J` are
  `f_bus`/`t_bus` of the bus pairs in order of first occurrences in sorted branches.
- Dimension equals the number of **buses** → [`plot_variable`](@ref).

All the branches are assumed to be active and are accounted for.


**Keyword arguments**: `system_name` (label used in figure titles and output filenames; defaults to the
network's `"name"` field, or `"system"` if absent), `solver_names`, `output_dir` (default `"."`),
`vis_threshold` (default `20`), `flat` (default `false`, bypasses network loading and always uses
`plot_variable`), `xlabel` (forwarded to the underlying plotting functions; defaults to their default),
`symlog` (default `false`, draws the y-axis on a symmetric log scale).
Output images are named `{system_name}_{variable}.png`.
"""
function viz_opf(
    network::Dict,
    variables::Union{String, Vector{String}},
    x,
    var_data::T...;
    system_name::String=get(network, "name", "system"),
    solver_names=nothing,
    output_dir::String=".",
    vis_threshold::Int=20,
    flat::Bool=false,
    xlabel=nothing,
    symlog::Bool=false
) where {T <: Union{Matrix, Dict}}
    if !flat
        I_branches, J_branches, n_branches, n_buses,
            I_buspairs, J_buspairs, n_buspairs = _get_power_system_data(network)
    end

    if T <: Matrix
        # var_data are Matrix only if variables is a String.
        variables isa String || throw(ArgumentError("`variables` should be a String when visualizing a single variable (var_data are Matrix)"))
        # Single variable: var_data are the per-solver matrices directly.
        var_data_pairs = [(variables, collect(var_data))]
    else
        # Multiple variables: extract each variable's matrices from the per-solver Dicts.
        variables isa Vector{String} || throw(ArgumentError("`variables` should be a Vector{String} when visualizing multiple variables (var_data are Dict)"))
        # Check that all solvers have all variables.
        for (i, d) in enumerate(var_data)
            for v in variables
                haskey(d, v) || throw(ArgumentError("Variable '$v' not found in data for solver $(i)"))
            end
        end
        var_data_pairs = [(v, [d[v] for d in var_data]) for v in variables]
    end

    mkpath(output_dir)
    for (var_name, solvers_data) in var_data_pairs
        n_dim = size(solvers_data[1], 1)

        if flat
            fig = plot_variable(x, solvers_data...;
                                solver_names=solver_names,
                                var_name=var_name,
                                vis_threshold=vis_threshold,
                                xlabel=xlabel,
                                symlog=symlog)
        elseif n_dim == n_branches
            fig = plot_graph_variable(I_branches, J_branches, x, solvers_data...;
                                       solver_names=solver_names,
                                       var_name=var_name,
                                       vis_threshold=vis_threshold,
                                       xlabel=xlabel,
                                       symlog=symlog)
        elseif n_dim == n_buspairs
            fig = plot_graph_variable(I_buspairs, J_buspairs, x, solvers_data...;
                                       solver_names=solver_names,
                                       var_name=var_name,
                                       vis_threshold=vis_threshold,
                                       xlabel=xlabel,
                                       symlog=symlog)
        else
            n_dim == n_buses || throw(ArgumentError("Variable '$var_name' has dimension $n_dim, expected $n_branches (branches), $n_buspairs (bus pairs) or $n_buses (buses)"))
            fig = plot_variable(x, solvers_data...;
                                solver_names=solver_names,
                                var_name=var_name,
                                vis_threshold=vis_threshold,
                                xlabel=xlabel,
                                symlog=symlog)
        end

        # Add a figure-level title above the subplot grid. Row 0 places the
        # label above row 1 (where the subplots/inner layout start). We set
        # `tellwidth=false` so the label's natural text width does not feed
        # back into column sizing — important for `plot_graph_variable`,
        # whose contents live inside a nested GridLayout at `fig[1, 1]`.
        Label(fig[0, :], "$(system_name): $(var_name)";
              fontsize=20, font=:bold, halign=:center,
              tellwidth=false, tellheight=true)

        output_path = joinpath(output_dir, "$(system_name)_$(var_name).png")
        save(output_path, fig)
        println("Saved $output_path")
    end
end

function viz_opf(
    system_identifier::String,
    variables::Union{String, Vector{String}},
    x,
    var_data::T...;
    system_name::String=system_identifier,
    flat::Bool=false,
    kwargs...
) where {T <: Union{Matrix, Dict}}
    if flat
        network = Dict()
    else
        network = make_basic_network(pglib(system_identifier))
    end
    return viz_opf(network, variables, x, var_data...; system_name=system_name, flat=flat, kwargs...)
end

"""
    animate_opf(network::Dict, variables, x, time_steps, var_data...; kwargs...)
    animate_opf(system_identifier::String, variables, x, time_steps, var_data...; kwargs...)

Animate OPF solution variables over a sequence of time-stepped frames and save one
GIF per variable to `output_dir`. Animated analogue of [`viz_opf`](@ref).

Provide either a network data `Dict` similar to PowerModels format, or the name of the
system compatible with PGLib.jl, for which data is obtained with
`make_basic_network(pglib(system_identifier))`.

Two calling modes, determined by the element type of `var_data`:

- **Array mode**: `variables` is a `String`. Each `var_data` element is either an
  `(n_dim × n_instances)` `AbstractMatrix` (held constant across frames) or an
  `(n_dim × n_instances × n_frames)` 3D `AbstractArray` (animated). One element per solver.
- **Dict mode**: `variables` is a `Vector{String}`. Each `var_data` element is a
  `Dict` mapping variable names to either of the two shapes above.

Within either mode, different solvers may supply different shapes for the same variable
(e.g. an animated solver alongside a static reference) — see
[`animate_variable`](@ref) / [`animate_graph_variable`](@ref).

`x` is either a single `Vector` (shared across solvers) or a `Vector` of `Vector`s
(one per solver), following the same convention as [`viz_opf`](@ref).

`time_steps` is a `Vector` whose length must match the third dimension of any 3D `var_data`.

**Variable dispatch** (when `flat=false`):
- Dimension equals the number of **branches** → [`animate_graph_variable`](@ref),
  where `I`/`J` are `f_bus`/`t_bus` in sorted branch key order.
- Dimension equals the number of **bus pairs** → [`animate_graph_variable`](@ref),
  where `I`/`J` are `f_bus`/`t_bus` of the bus pairs in order of first occurrences
  in sorted branches.
- Dimension equals the number of **buses** → [`animate_variable`](@ref).

All the branches are assumed to be active and are accounted for.

**Keyword arguments**: `system_name` (label used in figure titles and output filenames; defaults to the
network's `"name"` field, or `"system"` if absent), `solver_names`, `output_dir` (default `"."`),
`vis_threshold` (default `20`), `flat` (default `false`, bypasses network loading and always uses
`animate_variable`), `xlabel`, `time_label` (default `"t"`), `framerate` (default `10`),
`ylims` (default `nothing`), `symlog` (default `false`, draws the y-axis on a symmetric log
scale). Output files are named `{system_name}_{variable}.gif`.
"""
function animate_opf(
    network::Dict,
    variables::Union{String, Vector{String}},
    x,
    time_steps::AbstractVector,
    var_data...;
    system_name::String=get(network, "name", "system"),
    solver_names=nothing,
    output_dir::String=".",
    vis_threshold::Int=20,
    flat::Bool=false,
    xlabel=nothing,
    time_label::String="t",
    framerate::Int=10,
    ylims::Union{Nothing,Tuple{Real,Real}}=nothing,
    symlog::Bool=false,
)
    length(var_data) >= 1 || throw(ArgumentError("At least one var_data element is required"))

    # Dispatch on element type: all Dicts → multi-variable, all arrays → single variable.
    # We use runtime checks rather than a uniform type parameter because the array mode
    # legitimately mixes 2D and 3D shapes (animated solver vs. static reference).
    all_dict  = all(d -> d isa Dict, var_data)
    all_array = all(d -> d isa AbstractArray, var_data)
    all_dict || all_array || throw(ArgumentError(
        "All var_data elements must be Dicts, or all must be arrays (Matrix or 3D array)"))

    if !flat
        I_branches, J_branches, n_branches, n_buses,
            I_buspairs, J_buspairs, n_buspairs = _get_power_system_data(network)
    end

    if all_array
        # var_data are the per-solver arrays only if variables is a String.
        variables isa String || throw(ArgumentError(
            "`variables` should be a String when animating a single variable (var_data are arrays)"))
        for (i, d) in enumerate(var_data)
            ndims(d) in (2, 3) || throw(ArgumentError(
                "var_data[$i] must be a Matrix (2D) or a 3D array, got ndims=$(ndims(d))"))
        end
        var_data_pairs = [(variables, collect(var_data))]
    else
        # Multiple variables: extract each variable's arrays from the per-solver Dicts.
        variables isa Vector{String} || throw(ArgumentError(
            "`variables` should be a Vector{String} when animating multiple variables (var_data are Dicts)"))
        # Check that all solvers have all variables.
        for (i, d) in enumerate(var_data)
            for v in variables
                haskey(d, v) || throw(ArgumentError("Variable '$v' not found in data for solver $(i)"))
            end
        end
        var_data_pairs = [(v, [d[v] for d in var_data]) for v in variables]
    end

    mkpath(output_dir)
    n_frames = length(time_steps)
    for (var_name, solvers_data) in var_data_pairs
        n_dim = size(solvers_data[1], 1)

        if flat
            fig, frame_obs = animate_variable(x, time_steps, solvers_data...;
                                              solver_names=solver_names,
                                              var_name=var_name,
                                              vis_threshold=vis_threshold,
                                              xlabel=xlabel,
                                              time_label=time_label,
                                              ylims=ylims,
                                              symlog=symlog)
        elseif n_dim == n_branches
            fig, frame_obs = animate_graph_variable(I_branches, J_branches, x, time_steps,
                                                     solvers_data...;
                                                     solver_names=solver_names,
                                                     var_name=var_name,
                                                     vis_threshold=vis_threshold,
                                                     xlabel=xlabel,
                                                     time_label=time_label,
                                                     ylims=ylims,
                                                     symlog=symlog)
        elseif n_dim == n_buspairs
            fig, frame_obs = animate_graph_variable(I_buspairs, J_buspairs, x, time_steps,
                                                     solvers_data...;
                                                     solver_names=solver_names,
                                                     var_name=var_name,
                                                     vis_threshold=vis_threshold,
                                                     xlabel=xlabel,
                                                     time_label=time_label,
                                                     ylims=ylims,
                                                     symlog=symlog)
        else
            n_dim == n_buses || throw(ArgumentError(
                "Variable '$var_name' has dimension $n_dim, expected $n_branches (branches), $n_buspairs (bus pairs) or $n_buses (buses)"))
            fig, frame_obs = animate_variable(x, time_steps, solvers_data...;
                                              solver_names=solver_names,
                                              var_name=var_name,
                                              vis_threshold=vis_threshold,
                                              xlabel=xlabel,
                                              time_label=time_label,
                                              ylims=ylims,
                                              symlog=symlog)
        end

        # Add a figure-level title above the time-step label (which already lives at
        # row 0 inside animate_variable / animate_graph_variable). Negative row index
        # prepends a new row above the existing layout.
        Label(fig[-1, :], "$(system_name): $(var_name)";
              fontsize=20, font=:bold, halign=:center,
              tellwidth=false, tellheight=true)

        output_path = joinpath(output_dir, "$(system_name)_$(var_name).gif")
        record(fig, output_path, 1:n_frames; framerate=framerate) do f
            frame_obs[] = f
        end
        println("Saved $output_path")
    end
end

function animate_opf(
    system_identifier::String,
    variables::Union{String, Vector{String}},
    x,
    time_steps::AbstractVector,
    var_data...;
    system_name::String=system_identifier,
    flat::Bool=false,
    kwargs...
)
    if flat
        network = Dict()
    else
        network = make_basic_network(pglib(system_identifier))
    end
    return animate_opf(network, variables, x, time_steps, var_data...; system_name=system_name, flat=flat, kwargs...)
end
