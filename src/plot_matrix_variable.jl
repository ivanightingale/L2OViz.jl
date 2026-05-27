"""
    plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                         solver_names=nothing, n=nothing,
                         xlabel=nothing, var_name="",
                         vis_threshold::Int=20, significance_fn=default_significance) -> Figure

Visualize a symmetric matrix variable (given in COO format) across multiple problem instances.
The matrix variable is assumed to have the same COO across all the problem instances, and to be
symmetric: the COO coordinates should not contain repeated symmetry pairs, and entries are
visualized for only the given half of the matrix specified by the coordinates.

`x` is either:
- A single `Vector`: the same x is used for every solver's data matrix. Length must equal the
number of instances in the data of each solver.
- Multiple `Vector`s: one `Vector` per solver, in the same order as `var_data`. `length(x)`
must equal the number of solvers, and length of each Vector must equal the number of instances in
the data of each solver.

`var_data` is one or more `(nnz × n_instances)` data matrices, one per solver.

If not provided, solver names default to "Solver 1", "Solver 2", ...

The x-axis label defaults to `"Unknown Parameter"` unless `xlabel` is given.

**Thresholding**: if number of unique rows/columns exceeds `vis_threshold`, select an induced
submatrix with dimension `vis_threshold`. `significance_fn` (default: 1-norm) is applied
to the values of the k-th entry of the variable across all solvers and instances to get the
score of coordinate `(I[k], J[k])`, and the score of each column/row is the max entry score in
that column/row.

**Grid dimensions**: `n` fixes the side length of the (square) matrix; otherwise
`max(maximum(I), maximum(J))` is used.
"""
function plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                              solver_names=nothing, n=nothing,
                              xlabel=nothing, var_name="",
                              vis_threshold::Int=20,
                              significance_fn=default_significance)
    length(var_data) >= 1 || throw(ArgumentError("At least one data matrix must be provided"))
    nnz = validate_var_data_dims(var_data)
    length(I) == nnz || throw(DimensionMismatch("Length of I must equal number of rows in var_data"))
    length(J) == nnz || throw(DimensionMismatch("Length of J must equal number of rows in var_data"))
    x_vecs = resolve_x_vecs(x, var_data)
    n_solvers = length(var_data)
    solver_names = resolve_solver_names(solver_names, n_solvers)
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # Resolve full matrix dimension; symmetric matrix is square
    effective_n_full = isnothing(n) ? max(maximum(I), maximum(J)) : n

    all(1 .<= I .<= effective_n_full) || throw(ArgumentError("All row indices must be in [1, n=$effective_n_full]"))
    all(1 .<= J .<= effective_n_full) || throw(ArgumentError("All column indices must be in [1, n=$effective_n_full]"))

    # For each entry, combine values across all solvers and all instances for significance score
    entry_scores = compute_entry_scores(var_data, nnz, significance_fn)
    I_plot, J_plot, nz_idx, sel_indices, filtered =
        select_matrix_entries(entry_scores, I, J, vis_threshold)

    n_grid_rows, n_grid_cols, grid_pos =
        matrix_grid_layout(sel_indices, filtered, effective_n_full)

    solver_colors = solver_palette(n_solvers)

    fig = Figure(size=(320 * n_grid_cols, 260 * n_grid_rows + 60))
    gl = fig[1, 1] = GridLayout(n_grid_rows, n_grid_cols)

    axes, legend_handles = draw_matrix_panels!(
        gl, var_data, x_vecs, x_label, var_name,
        I_plot, J_plot, nz_idx, grid_pos, solver_colors)

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
