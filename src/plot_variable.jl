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
                       var_name="", vis_threshold::Int=20,
                       significance_fn=default_significance)
    length(var_data) >= 1 || throw(ArgumentError("At least one data matrix must be provided"))
    n_entries = validate_var_data_dims(var_data)
    x_vecs = resolve_x_vecs(x, var_data)
    n_solvers = length(var_data)
    solver_names = resolve_solver_names(solver_names, n_solvers)
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # For each entry, combine values across all solvers and all instances for significance score
    entry_scores = compute_entry_scores(var_data, n_entries, significance_fn)
    selected_indices = select_variable_entries(entry_scores, vis_threshold)

    n_plot = length(selected_indices)
    n_rows, n_cols = vector_grid_layout(n_plot)
    solver_colors = solver_palette(n_solvers)
    fig = Figure(size=(320 * n_cols, 260 * n_rows + 60))

    axes, legend_handles = draw_vector_panels!(
        fig, var_data, x_vecs, x_label, var_name,
        selected_indices, solver_colors, n_cols)

    linkxaxes!(axes...)
    linkyaxes!(axes...)
    Legend(fig[n_rows + 1, 1:n_cols], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)
    return fig
end
