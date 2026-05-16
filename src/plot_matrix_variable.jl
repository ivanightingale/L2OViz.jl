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
                               vis_threshold::Int=20, significance_fn=default_significance)
    length(var_data) >= 1 || throw(ArgumentError("At least one data matrix must be provided"))
    n_solvers = length(var_data)
    nnz = size(var_data[1], 1)
    length(I) == nnz || throw(DimensionMismatch("Length of I must equal number of rows in var_data"))
    length(J) == nnz || throw(DimensionMismatch("Length of J must equal number of rows in var_data"))
    # All matrices must have the same number of rows (nnz of the variable)
    for (i, d) in enumerate(var_data)
        size(d, 1) == nnz || throw(DimensionMismatch("Variable dimension of solver $(i): $(size(d, 1)); mismatches with variable dimension of solver 1: $(nnz)"))
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

    # Resolve full matrix dimension; symmetric matrix is square
    effective_n_full = isnothing(n) ? max(maximum(I), maximum(J)) : n

    all(1 .<= I .<= effective_n_full) || throw(ArgumentError("All row indices must be in [1, n=$effective_n_full]"))
    all(1 .<= J .<= effective_n_full) || throw(ArgumentError("All column indices must be in [1, n=$effective_n_full]"))

    # At each coordinate, combine values across all solvers and all instances for significance score
    entry_scores = [significance_fn(vcat([d[k, :] for d in var_data]...)) for k in 1:nnz]
    I_plot, J_plot, nz_idx, sel_indices, filtered =
        select_matrix_entries(entry_scores, I, J, vis_threshold)

    n_plot = length(I_plot)

    # Compressed grid when filtering; full n×n grid otherwise
    if filtered
        index_map = Dict(c => idx for (idx, c) in enumerate(sel_indices))
        n_grid_rows = n_grid_cols = length(sel_indices)
        grid_pos = (i, j) -> (index_map[i], index_map[j])
    else
        n_grid_rows, n_grid_cols = effective_n_full, effective_n_full
        grid_pos = (i, j) -> (i, j)
    end

    palette = Makie.wong_colors()
    solver_colors = [palette[mod1(i, length(palette))] for i in 1:n_solvers]

    fig = Figure(size=(320 * n_grid_cols, 260 * n_grid_rows + 60))
    gl = fig[1, 1] = GridLayout(n_grid_rows, n_grid_cols)

    legend_handles = []
    axes = Axis[]

    for k in 1:n_plot
        entry_label = isempty(var_name) ? "[$(I_plot[k]),$(J_plot[k])]" : "$(var_name)[$(I_plot[k]),$(J_plot[k])]"
        gr, gc = grid_pos(I_plot[k], J_plot[k])
        ax = Axis(gl[gr, gc]; title=entry_label, xlabel=x_label)
        push!(axes, ax)

        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], d[nz_idx[k], :]; color=solver_colors[i])
            if k == 1
                push!(legend_handles, p)
            end
        end
    end

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
