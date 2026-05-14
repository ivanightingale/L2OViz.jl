"""
    plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, var_data::Matrix...;
                         solver_names=nothing, m=nothing, n=nothing,
                         x=nothing, xlabel=nothing, var_name="",
                         vis_threshold::Int=30, significance_fn=default_significance,
                         symmetric=false) -> Figure

Visualize a matrix variable (given in COO format) across multiple problem instances.

Pass `I`, `J` (COO indices), then one or more `(nnz × n_instances)` data matrices,
one per solver. Series are overlaid on each subplot with a shared legend. Solver names
default to "Solver 1", "Solver 2", …

**Grid dimensions** (when not filtering):
- `m`/`n` fix the number of rows/columns; otherwise `maximum(I)`/`maximum(J)` is used.
- When `symmetric = true`, the grid is forced square; only one of `m`/`n` is needed.

**Thresholding**: when `unique(I) > vis_threshold` or `unique(J) > vis_threshold`, only
the top-`vis_threshold` most significant rows *and* columns are shown in a compressed
grid. Row/column score is the max entry score in that row/column; scores come from
`significance_fn` (default: 1-norm) applied to values concatenated across all solvers.
For `symmetric = true`, the top `vis_threshold` row-column pairs are selected.

**Symmetric mode** (`symmetric = true`): the grid is forced square and only column significance
is used for index selection. The COO may store only one triangle; entries are shown as-is.
"""
function plot_matrix_variable(I::Vector{Int}, J::Vector{Int}, var_data::Matrix...;
                               solver_names=nothing, m=nothing, n=nothing,
                               x=nothing, xlabel=nothing, var_name="",
                               vis_threshold::Int=30, significance_fn=default_significance,
                               symmetric=false)
    @assert length(var_data) >= 1 "At least one data matrix must be provided"
    n_solvers = length(var_data)
    first_data = var_data[1]
    nnz, n_instances = size(first_data)
    @assert length(I) == nnz "Length of I must equal number of rows in var_data"
    @assert length(J) == nnz "Length of J must equal number of rows in var_data"
    for (i, d) in enumerate(var_data)
        @assert size(d) == (nnz, n_instances) "All data matrices must have size ($(nnz), $(n_instances)); solver $(i) has size $(size(d))"
    end
    if isnothing(solver_names)
        solver_names = ["Solver $i" for i in 1:n_solvers]
    else
        @assert length(solver_names) == n_solvers "solver_names must have length $n_solvers"
    end

    # Resolve full matrix dimensions
    if symmetric
        if !isnothing(m) && !isnothing(n)
            @assert m == n "Symmetric matrix must be square (m=$m, n=$n)"
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

    @assert all(1 .<= I .<= effective_m_full) "All row indices must be in [1, m=$effective_m_full]"
    @assert all(1 .<= J .<= effective_n_full) "All column indices must be in [1, n=$effective_n_full]"

    if isnothing(x)
        x = collect(1:n_instances)
        x_label = "Instance"
    else
        @assert length(x) == n_instances "Length of x must equal number of instances ($n_instances)"
        x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel
    end

    # Combine scores across all solvers for entry significance
    entry_scores = [significance_fn(vcat([d[k, :] for d in var_data]...)) for k in 1:nnz]
    I_plot, J_plot, data_row_idx, sel_rows, sel_cols, filtered =
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

    for k in 1:n_plot
        entry_label = isempty(var_name) ? "[$(I_plot[k]),$(J_plot[k])]" : "$(var_name)[$(I_plot[k]),$(J_plot[k])]"
        gr, gc = grid_pos(I_plot[k], J_plot[k])
        ax = Axis(gl[gr, gc]; title=entry_label, xlabel=x_label, ylabel="Value")

        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x, d[data_row_idx[k], :]; color=solver_colors[i])
            if k == 1
                push!(legend_handles, p)
            end
        end
    end

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
