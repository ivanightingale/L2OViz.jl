# exp/viz_opf.jl
# Utility function for visualizing OPF solution variables.

using CairoMakie
using L2OViz
using PGLib
using PowerModels

# Load branch COO indices and bus/branch counts from a PGLib system.
function _get_power_system_data(system_name::String)
    network = make_basic_network(pglib(system_name))
    branch_dict = network["branch"]
    sorted_branch_keys = sort(collect(keys(branch_dict)), by=k -> parse(Int, string(k)))
    I_branches = [branch_dict[k]["f_bus"] for k in sorted_branch_keys]
    J_branches = [branch_dict[k]["t_bus"] for k in sorted_branch_keys]
    n_branches = length(sorted_branch_keys)
    n_buses    = length(network["bus"])
    return I_branches, J_branches, n_branches, n_buses
end

"""
    viz_opf(system_name, variables, x, var_data::T...; kwargs...) where {T <: Union{Matrix, Dict}}

Visualize OPF solution variables and save one image per variable to `output_dir`.

Two calling modes, determined by `T`:

- **`T <: Matrix`**: `variables` is a `String`; each `var_data` is a `Matrix`
  `(n_dim × n_instances)`, one per solver.
- **`T <: Dict`**: `variables` is a `Vector{String}`; each `var_data` is a `Dict` mapping
  variable names to matrices, one per solver.

`x` is either a single `Vector` (shared across solvers) or a `Vector` of `Vector`s (one per solver).

**Variable dispatch** (when `flat=false`):
- Dimension equals the number of **branches** → `plot_matrix_variable`, with COO indices from
  `f_bus`/`t_bus` in sorted branch key order.
- Dimension equals the number of **buses** → `plot_variable`.

**Keyword arguments**: `solver_names`, `output_dir` (default `"."`), `vis_threshold` (default `20`),
`flat` (default `false`, bypasses network loading and always uses `plot_variable`).
Output images are named `{system_name}_{variable}.png`.
"""
function viz_opf(
    system_name::String,
    variables::Union{String, Vector{String}},
    x,
    var_data::T...;
    solver_names=nothing,
    output_dir::String=".",
    vis_threshold::Int=20,
    flat::Bool=false
) where {T <: Union{Matrix, Dict}}
    if !flat
        I_branches, J_branches, n_branches, n_buses = _get_power_system_data(system_name)
    end

    if T <: Matrix
        # var_data are Matrix only if variables is a String.
        variables isa String || throw(ArgumentError("`variables` should be a String when visualizing a single variable (var_data are Matrix)"))
        # Single variable: var_data are the per-solver matrices directly.
        var_data_pairs = [(variables, collect(var_data))]
    else
        # Multiple variables: extract each variable's matrices from the per-solver Dicts.
        # Check that all solvers have all variables.
        variables isa Vector{String} || throw(ArgumentError("`variables` should be a Vector{String} when visualizing multiple variables (var_data are Dict)"))
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
                                vis_threshold=vis_threshold)
        elseif n_dim == n_branches
            fig = plot_matrix_variable(I_branches, J_branches, x, solvers_data...;
                                       solver_names=solver_names,
                                       var_name=var_name,
                                       vis_threshold=vis_threshold)
        else
            n_dim == n_buses || throw(ArgumentError("Variable '$var_name' has dimension $n_dim, expected $n_branches (branches) or $n_buses (buses)"))
            fig = plot_variable(x, solvers_data...;
                                solver_names=solver_names,
                                var_name=var_name,
                                vis_threshold=vis_threshold)
        end

        output_path = joinpath(output_dir, "$(system_name)_$(var_name).png")
        save(output_path, fig)
        println("Saved $output_path")
    end
end
