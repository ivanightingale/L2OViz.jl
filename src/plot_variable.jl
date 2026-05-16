"""
    plot_variable(x, var_data::Matrix...; solver_names=nothing, xlabel=nothing,
                  var_name="", vis_threshold::Int=20, significance_fn=default_significance) -> Figure

Visualize a vector variable across multiple problem instances.

`x` is either:
- A single `Vector`: the same x is used for every solver's data matrix. Length must equal the
number of instances in the data of each solver.
- Multiple `Vector`s: one `Vector` per solver, in the same order as `var_data`. `length(x)`
must equal the number of solvers, and length of each Vector must equal the number of instances in
the data of each solver.

`var_data` is one or more `(n_entries × n_instances)` matrices, one per solver.

If not provided, solver names default to "Solver 1", "Solver 2", ...

The x-axis label defaults to `"Unknown Parameter"` unless `xlabel` is given.

Only the top-`vis_threshold` most significant entries are visualized. `significance_fn`
(default: 1-norm) is applied to the values of each entry of the variable across all solvers and
instances to get the score of each entry. Entry labels always reflect the original indices.
"""
function plot_variable(x, var_data::Matrix...;
                       solver_names=nothing, xlabel=nothing,
                       var_name="", vis_threshold::Int=20, significance_fn=default_significance)
    length(var_data) >= 1 || throw(ArgumentError("At least one data matrix must be provided"))
    n_solvers = length(var_data)
    n_entries = size(var_data[1], 1)
    # All matrices must have the same number of rows (dimension of the variable)
    for (i, d) in enumerate(var_data)
        size(d, 1) == n_entries || throw(DimensionMismatch("Variable dimension of solver $(i): $(size(d, 1)); mismatches with variable dimension of solver 1: $(n_entries)"))
    end
    if isnothing(solver_names)
        solver_names = ["Solver $i" for i in 1:n_solvers]
    else
        length(solver_names) == n_solvers || throw(ArgumentError("solver_names must have length $n_solvers"))
    end

    # Resolve x into a per-solver vector of x-axis values
    if all(isa.(x, AbstractVector))
        # x is multiple vectors, one per solver
        x_vecs = collect(x)
        length(x_vecs) == n_solvers || throw(ArgumentError("Number of x vectors ($(length(x_vecs))) must equal number of data matrices ($n_solvers)"))
        for (i, xi) in enumerate(x_vecs)
            n_instances_i = size(var_data[i], 2)
            length(xi) == n_instances_i || throw(DimensionMismatch("Length of x[$(i)] ($(length(xi))) must equal number of columns in data matrix $(i) ($n_instances_i)"))
        end
    else
        # x is a single vector shared across all solvers
        for (i, d) in enumerate(var_data)
            n_instances_i = size(d, 2)
            length(x) == n_instances_i || throw(DimensionMismatch("Length of x ($(length(x))) must equal number of columns in data matrix $(i) ($n_instances_i)"))
        end
        x_vecs = [x for _ in 1:n_solvers]
    end
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # For each entry, combine values across all solvers and all instances for significance score
    scores = [significance_fn(vcat([d[k, :] for d in var_data]...)) for k in 1:n_entries]
    selected_indices, _ = select_variable_entries(scores, vis_threshold)

    n_plot = length(selected_indices)
    n_cols = ceil(Int, sqrt(n_plot))
    n_rows = ceil(Int, n_plot / n_cols)

    palette = Makie.wong_colors()
    solver_colors = [palette[mod1(i, length(palette))] for i in 1:n_solvers]

    fig = Figure(size=(320 * n_cols, 260 * n_rows + 60))

    legend_handles = []
    axes = Axis[]

    for (k, data_idx) in enumerate(selected_indices)
        grid_row = div(k - 1, n_cols) + 1
        grid_col = mod(k - 1, n_cols) + 1
        entry_label = isempty(var_name) ? "[$data_idx]" : "$(var_name)[$data_idx]"
        ax = Axis(fig[grid_row, grid_col]; title=entry_label, xlabel=x_label)
        push!(axes, ax)

        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], d[data_idx, :]; color=solver_colors[i])
            if k == 1
                push!(legend_handles, p)
            end
        end
    end

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    Legend(fig[n_rows + 1, 1:n_cols], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
