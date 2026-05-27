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
                                 time_label::String="t")
    if !isnothing(ylims)
        ylims[1] < ylims[2] || throw(ArgumentError(
            "ylims must satisfy ylims[1] < ylims[2], got $ylims"))
    end
    length(var_data) >= 1 || throw(ArgumentError("At least one data array must be provided"))
    n_frames = length(time_steps)
    n_frames >= 1 || throw(ArgumentError("time_steps must contain at least one frame"))
    nnz = validate_var_data_dims(var_data, n_frames)
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

    # For each entry, combine values across all solvers, instances and frames for significance score
    entry_scores = compute_entry_scores(var_data, nnz, significance_fn)
    I_plot, J_plot, nz_idx, sel_indices, filtered =
        select_matrix_entries(entry_scores, I, J, vis_threshold)

    n_grid_rows, n_grid_cols, grid_pos =
        matrix_grid_layout(sel_indices, filtered, effective_n_full)

    solver_colors = solver_palette(n_solvers)

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

    axes, legend_handles = draw_matrix_panels!(
        gl, var_data, x_vecs, x_label, var_name,
        I_plot, J_plot, nz_idx, grid_pos, solver_colors; frame_obs=frame_obs)

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    # Fix a single global y-range for the entire animation. Because the y-axes are linked,
    # setting limits on one axis propagates to all panels.
    apply_fixed_ylims!(axes[1], ylims, var_data, nz_idx)

    Legend(fig[2, 1], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig, frame_obs
end
