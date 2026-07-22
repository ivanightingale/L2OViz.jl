"""
    plot_graph_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                         solver_names=nothing,
                         xlabel=nothing, var_name="",
                         vis_threshold::Int=20, significance_fn=default_significance,
                         symlog::Bool=false, palette=nothing, alpha=1.0) -> Figure

Visualize a graph variable across multiple problem instances.
The variable is assumed to have the same graph topology across all the problem instances.
The edges specified by `I` and `J` should not contain both (i, j) and (j, i).

`x` is either:
- A single `Vector`: the same x is used for every solver's data matrix. Length must equal the
number of instances in the data of each solver.
- Multiple `Vector`s: one `Vector` per solver, in the same order as `var_data`. `length(x)`
must equal the number of solvers, and length of each Vector must equal the number of instances in
the data of each solver.

`var_data` is one or more `(n_e × n_instances)` data matrices, one per solver.

If not provided, solver names default to "Solver 1", "Solver 2", ...

The x-axis label defaults to `"Unknown Parameter"` unless `xlabel` is given.

**Thresholding**: if number of unique rows/columns exceeds `vis_threshold`, select an induced
subgraph with dimension `vis_threshold`. `significance_fn` (default: 1-norm) is applied
to the values of the k-th entry of the variable across all solvers and instances to get the
score of coordinate `(I[k], J[k])`, and the score of each column/row is the max entry score in
that column/row. If multiple edges between `(i, j)` are selected, only the highest-scoring one is
kept.

Set `symlog=true` to draw the y-axis on a symmetric log scale.

`palette` sets the per-solver colors; it defaults to `Makie.wong_colors()`. It may be a vector
of colors (of any type Makie accepts, e.g. `[:red, :blue]`), which is cycled through when there
are more solvers than colors, or a `Symbol` naming a Makie/ColorSchemes palette (e.g. `:tab10`,
`:viridis`): categorical palettes use their discrete colors, and continuous colormaps are sampled
into as many evenly spaced colors as there are solvers.
"""
function plot_graph_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                              solver_names=nothing,
                              xlabel=nothing, var_name="",
                              vis_threshold::Int=20,
                              significance_fn=default_significance,
                              symlog::Bool=false, palette=nothing, alpha::Real=1.0)
    length(var_data) >= 1 || throw(ArgumentError("At least one data matrix must be provided"))
    n_e = validate_var_data_dims(var_data)
    length(I) == n_e || throw(DimensionMismatch("Length of I must equal number of rows in var_data"))
    length(J) == n_e || throw(DimensionMismatch("Length of J must equal number of rows in var_data"))
    x_vecs = resolve_x_vecs(x, var_data)
    n_solvers = length(var_data)
    solver_names = resolve_solver_names(solver_names, n_solvers)
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # For each entry, combine values across all solvers and all instances for significance score
    entry_scores = compute_entry_scores(var_data, n_e, significance_fn)
    I_plot, J_plot, selected_indices = select_variable_edges(entry_scores, I, J, vis_threshold)

    n, grid_pos = matrix_grid_layout(I_plot, J_plot)

    solver_colors = solver_palette(n_solvers, palette)

    fig = Figure(size=(320 * n, 260 * n + 60))
    gl = fig[1, 1] = GridLayout(n, n)

    yscale = resolve_yscale(symlog, var_data, selected_indices)

    axes, legend_handles = draw_matrix_panels!(
        gl, var_data, x_vecs, x_label, var_name,
        I_plot, J_plot, selected_indices, grid_pos, solver_colors; yscale=yscale, alpha=alpha)

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
