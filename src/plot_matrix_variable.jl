"""
    plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                         solver_names=nothing, m=nothing, n=nothing,
                         xlabel=nothing, var_name="",
                         vis_threshold::Int=20, significance_fn=default_significance,
                         symmetric=false) -> Figure

Visualize a matrix variable (given in COO format) across multiple problem instances. The matrix
variable is assumed to have the same COO across all the problem instances.

`x` is either:
- A single `Vector`: the same x is used for every solver's data matrix. Length must equal the
number of instances in the data of each solver.
- Multiple `Vector`s: one `Vector` per solver, in the same order as `var_data`. `length(x)`
must equal the number of solvers, and length of each Vector must equal the number of instances in
the data of each solver.

`var_data` is one or more `(nnz × n_instances)` data matrices, one per solver.

If not provided, solver names default to "Solver 1", "Solver 2", ...

The x-axis label defaults to `"Unknown Parameter"` unless `xlabel` is given.

**Symmetric mode** (`symmetric = true`): the COO coordinates should not contain repeated
symmetry pairs. Entries are visualized for only the given half of the matrix specified
by the coordinates.

**Thresholding**: if `length(unique(I)) > vis_threshold` or `length(unique(J)) > vis_threshold`,
only the top-`vis_threshold` most significant rows *and* columns are visualized. `significance_fn`
(default: 1-norm) is applied to `vcat([d[k, :] for d in var_data]...)` to get the score of
coordinate (I[k], J[k]). Score of each row/column is the max entry score in that row/column.

When `symmetric = true`, the top `vis_threshold` row-column pairs are selected.

**Grid dimensions**:
- `m`/`n` fix the number of rows/columns; otherwise `maximum(I)`/`maximum(J)` is used.
- When `symmetric = true`, the grid is forced to be square.
"""
function plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, x, var_data::Matrix...;
                               solver_names=nothing, m=nothing, n=nothing,
                               xlabel=nothing, var_name="",
                               vis_threshold::Int=20, significance_fn=default_significance,
                               symmetric=false)
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

    # Resolve full matrix dimensions
    if symmetric
        if !isnothing(m) && !isnothing(n)
            m == n || throw(ArgumentError("Symmetric matrix must be square (m=$m, n=$n)"))
            effective_m_full = m; effective_n_full = n
        elseif !isnothing(m)
            effective_m_full = m; effective_n_full = m
        elseif !isnothing(n)
            effective_m_full = n; effective_n_full = n
        else
            d = max(maximum(I), maximum(J))
            effective_m_full = d; effective_n_full = d
        end
    else
        effective_m_full = isnothing(m) ? maximum(I) : m
        effective_n_full = isnothing(n) ? maximum(J) : n
    end

    all(1 .<= I .<= effective_m_full) || throw(ArgumentError("All row indices must be in [1, m=$effective_m_full]"))
    all(1 .<= J .<= effective_n_full) || throw(ArgumentError("All column indices must be in [1, n=$effective_n_full]"))

    # At each coordinate, combine values across all solvers and all instances for significance score
    entry_scores = [significance_fn(vcat([d[k, :] for d in var_data]...)) for k in 1:nnz]
    I_plot, J_plot, nz_idx, sel_rows, sel_cols, filtered =
        select_matrix_entries(entry_scores, I, J, vis_threshold, symmetric)

    n_plot = length(I_plot)

    # Compressed grid when filtering; full m×n grid otherwise
    if filtered
        row_map = Dict(r => idx for (idx, r) in enumerate(sel_rows))
        col_map = Dict(c => idx for (idx, c) in enumerate(sel_cols))
        n_grid_rows, n_grid_cols = length(sel_rows), length(sel_cols)
        grid_pos = (i, j) -> (row_map[i], col_map[j])
    else
        n_grid_rows, n_grid_cols = effective_m_full, effective_n_full
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
