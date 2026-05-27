"""
    animate_matrix_variable(I::Vector{Int}, J::Vector{Int}, x, time_steps,
                            var_data::Union{AbstractMatrix, AbstractArray{<:Any,3}}...;
                            solver_names=nothing, n=nothing,
                            xlabel=nothing, var_name="",
                            vis_threshold::Int=20,
                            significance_fn=default_significance,
                            ylims=nothing,
                            time_label="t")
        -> (fig::Figure, frame_obs::Observable{Int})

Build an animatable figure for a symmetric matrix variable (given in COO format) across a
sequence of time-stepped frames. Each frame mirrors the layout of [`plot_matrix_variable`](@ref):
one subplot per displayed `(I[k], J[k])` entry, arranged on the matrix grid.

`I`, `J` give the COO coordinates of the (symmetric, half-stored) matrix; they are shared
across all frames and solvers.

`x` follows the same convention as [`plot_matrix_variable`](@ref):
- A single `Vector`: shared x-axis values for every solver's data.
- A `Vector` of `Vector`s: one per solver, in the same order as `var_data`.

`time_steps` is a `Vector` of length `n_frames` giving the value displayed for each frame.

`var_data` is one or more arrays, one per solver. Each array may be either:
- A 3D `(nnz × n_instances × n_frames)` array, giving the variable's values at each frame.
- A 2D `(nnz × n_instances)` matrix, displayed as constant across every frame.

Different solvers can mix the two shapes — useful for comparing an animated solver against a
static reference solution. All arrays must agree on `nnz`, and any 3D array must have
`size(d, 3) == length(time_steps)`. `n_instances` may differ across solvers when a per-solver
`x` is supplied.

Thresholding (`vis_threshold`, `significance_fn`) follows the same induced-submatrix rule as
`plot_matrix_variable`, with significance scores aggregated over all instances AND all frames
so that the set of displayed entries — and therefore the grid layout — stays stable for the
whole animation. `n` fixes the side length of the (square) matrix; otherwise inferred from
`max(maximum(I), maximum(J))`.

The y-axis range is held fixed for every frame. By default the limits are computed once from
the full min/max of the displayed data across all selected entries, solvers, instances and
frames. Pass `ylims=(ymin, ymax)` to override with explicit limits.

The returned `frame_obs::Observable{Int}` controls which frame is currently displayed. To
export a GIF, drive it via Makie's `record`:

```julia
fig, frame_obs = animate_matrix_variable(I, J, x, time_steps, data_A, data_B; ...)
record(fig, "anim.gif", 1:length(time_steps); framerate=10) do f
    frame_obs[] = f
end
```
"""
function animate_matrix_variable(I::Vector{Int}, J::Vector{Int}, x,
                                 time_steps::AbstractVector,
                                 var_data::Union{AbstractMatrix, AbstractArray{<:Any,3}}...;
                                 solver_names=nothing, n=nothing,
                                 xlabel=nothing, var_name="",
                                 vis_threshold::Int=20,
                                 significance_fn=default_significance,
                                 ylims::Union{Nothing,Tuple{Real,Real}}=nothing,
                                 time_label::AbstractString="t")
    if !isnothing(ylims)
        ylims[1] < ylims[2] || throw(ArgumentError(
            "ylims must satisfy ylims[1] < ylims[2], got $ylims"))
    end
    length(var_data) >= 1 || throw(ArgumentError("At least one data array must be provided"))
    n_solvers = length(var_data)
    nnz = size(var_data[1], 1)
    n_frames = length(time_steps)
    n_frames >= 1 || throw(ArgumentError("time_steps must contain at least one frame"))

    length(I) == nnz || throw(DimensionMismatch("Length of I must equal number of rows in var_data"))
    length(J) == nnz || throw(DimensionMismatch("Length of J must equal number of rows in var_data"))

    # All arrays must agree on nnz (rows); 3D arrays must additionally match the number of
    # frames. Matrices have no time dimension and are constant across frames.
    for (i, d) in enumerate(var_data)
        size(d, 1) == nnz || throw(DimensionMismatch(
            "Variable dimension of solver $(i): $(size(d, 1)); mismatches with variable dimension of solver 1: $(nnz)"))
        if ndims(d) == 3
            size(d, 3) == n_frames || throw(DimensionMismatch(
                "Number of frames in data of solver $(i): $(size(d, 3)); does not equal length(time_steps) = $(n_frames)"))
        end
    end

    if isnothing(solver_names)
        solver_names = ["Solver $i" for i in 1:n_solvers]
    else
        length(solver_names) == n_solvers || throw(ArgumentError("solver_names must have length $n_solvers"))
    end

    if all(isa.(x, AbstractVector))
        # x is multiple vectors, one per solver
        x_vecs = collect(x)
        length(x_vecs) == n_solvers || throw(ArgumentError(
            "Number of x vectors ($(length(x_vecs))) must equal number of data arrays ($n_solvers)"))
        for (i, xi) in enumerate(x_vecs)
            n_instances_i = size(var_data[i], 2)
            length(xi) == n_instances_i || throw(DimensionMismatch(
                "Length of x[$(i)] ($(length(xi))) must equal number of columns in data array $(i) ($n_instances_i)"))
        end
    else
        # x is a single vector shared across all solvers
        for (i, d) in enumerate(var_data)
            n_instances_i = size(d, 2)
            length(x) == n_instances_i || throw(DimensionMismatch(
                "Length of x ($(length(x))) must equal number of columns in data array $(i) ($n_instances_i)"))
        end
        x_vecs = [x for _ in 1:n_solvers]
    end
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # Resolve full matrix dimension; symmetric matrix is square
    effective_n_full = isnothing(n) ? max(maximum(I), maximum(J)) : n

    all(1 .<= I .<= effective_n_full) || throw(ArgumentError("All row indices must be in [1, n=$effective_n_full]"))
    all(1 .<= J .<= effective_n_full) || throw(ArgumentError("All column indices must be in [1, n=$effective_n_full]"))

    # Per-coordinate, per-solver values for significance and ylims computations. For 3D arrays
    # this collapses both instances and frames; for matrices it is just the row across instances.
    entry_values(d, k) = ndims(d) == 3 ? vec(@view d[k, :, :]) : @view d[k, :]

    # Significance score per coordinate: aggregate values across ALL instances and ALL frames
    # of every solver, so that the chosen entries and the grid layout stay fixed across frames.
    entry_scores = [significance_fn(vcat([Vector(entry_values(d, k)) for d in var_data]...))
                    for k in 1:nnz]
    I_plot, J_plot, nz_idx, sel_indices, filtered =
        select_matrix_entries(entry_scores, I, J, vis_threshold)

    n_plot = length(I_plot)

    # Compressed grid when filtering; full n×n grid otherwise (same as plot_matrix_variable).
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

    # Extra vertical space at the top accommodates the time-step label.
    fig = Figure(size=(320 * n_grid_cols, 260 * n_grid_rows + 120))

    # Observable that drives the animation. Callers mutate this to advance frames.
    frame_obs = Observable(1)

    # Time-step indicator at the top of the figure; updates with frame_obs.
    Label(fig[0, 1],
          @lift(string(time_label, " = ", time_steps[$frame_obs]));
          fontsize=20, tellwidth=false, halign=:center)

    # Subplot grid lives in its own GridLayout so the matrix coordinates map cleanly.
    gl = fig[1, 1] = GridLayout(n_grid_rows, n_grid_cols)

    legend_handles = []
    axes = Axis[]

    for k in 1:n_plot
        entry_label = isempty(var_name) ? "[$(I_plot[k]),$(J_plot[k])]" :
                                          "$(var_name)[$(I_plot[k]),$(J_plot[k])]"
        gr, gc = grid_pos(I_plot[k], J_plot[k])
        ax = Axis(gl[gr, gc]; title=entry_label, xlabel=x_label)
        push!(axes, ax)

        # Bind once per (entry, solver) iteration so the closure captures the right row index.
        coo_row = nz_idx[k]
        for (i, d) in enumerate(var_data)
            # 3D data lifts on frame_obs so each frame shows that frame's slice; matrix data
            # is plotted as a plain Vector and stays constant across frames.
            y_plot = ndims(d) == 3 ? (@lift d[coo_row, :, $frame_obs]) : d[coo_row, :]
            p = scatter!(ax, x_vecs[i], y_plot; color=solver_colors[i])
            if k == 1
                push!(legend_handles, p)
            end
        end
    end

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    # Fix a single global y-range for the entire animation. Because the y-axes are linked,
    # setting limits on one axis propagates to all panels.
    if isnothing(ylims)
        # Default: full min/max across selected COO entries / solvers / instances / frames.
        ymin = Inf
        ymax = -Inf
        for k in 1:n_plot
            for d in var_data
                slice = entry_values(d, nz_idx[k])
                ymin = min(ymin, minimum(slice))
                ymax = max(ymax, maximum(slice))
            end
        end
        span = ymax - ymin
        pad = span > 0 ? 0.05 * span : 0.5 * max(abs(ymax), 1.0)
        ylims!(axes[1], ymin - pad, ymax + pad)
    else
        # User-supplied limits used verbatim, no padding.
        ylims!(axes[1], ylims[1], ylims[2])
    end

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig, frame_obs
end
