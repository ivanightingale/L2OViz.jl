"""
    animate_variable(x, time_steps,
                     var_data::Union{AbstractMatrix, AbstractArray{<:Any,3}}...;
                     solver_names=nothing, xlabel=nothing,
                     var_name="", vis_threshold::Int=20,
                     significance_fn=default_significance,
                     ylims=nothing,
                     time_label="t")
        -> (fig::Figure, frame_obs::Observable{Int})

Build an animatable figure for a vector variable across a sequence of time-stepped frames.

`x` follows the same convention as [`plot_variable`](@ref):
- A single `Vector`: shared x-axis values for every solver's data.
- A `Vector` of `Vector`s: one per solver, in the same order as `var_data`.

`time_steps` is a `Vector` of length `n_frames` giving the value displayed for each frame
(e.g. the simulation time at each frame).

`var_data` is one or more arrays, one per solver. Each array may be either:
- A 3D `(n_entries × n_instances × n_frames)` array, giving the variable's values at each frame.
- A 2D `(n_entries × n_instances)` matrix, displayed as constant across every frame.

Different solvers can mix the two shapes — useful for comparing an animated solver against a
static reference solution. All arrays must agree on `n_entries`, and any 3D array must have
`size(d, 3) == length(time_steps)`. `n_instances` may differ across solvers when a per-solver
`x` is supplied.

Significance-based entry selection (`vis_threshold`, `significance_fn`) is computed ONCE
across all frames so that the grid layout and which entries are plotted stay stable
throughout the animation.

The y-axis range is held fixed for every frame so the animation is visually stable. By
default the limits are computed once from the full min/max of the data across all selected
entries, solvers, instances and frames. Pass `ylims=(ymin, ymax)` to override with explicit
limits — useful e.g. when early-iteration solver state contains outliers that would otherwise
dominate the range and make the rest of the animation unreadable.

The returned `frame_obs::Observable{Int}` controls which frame is currently displayed.
To export a GIF, drive it via Makie's `record`:

```julia
fig, frame_obs = animate_variable(x, time_steps, data_A, data_B; ...)
record(fig, "anim.gif", 1:length(time_steps); framerate=10) do f
    frame_obs[] = f
end
```
"""
function animate_variable(x, time_steps::AbstractVector,
                          var_data::Union{AbstractMatrix, AbstractArray{<:Any,3}}...;
                          solver_names=nothing, xlabel=nothing,
                          var_name="", vis_threshold::Int=20,
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
    n_entries = validate_var_data_dims(var_data, n_frames)
    x_vecs = resolve_x_vecs(x, var_data)
    n_solvers = length(var_data)
    solver_names = resolve_solver_names(solver_names, n_solvers)
    x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel

    # For each entry, combine values across all solvers, instances and frames for significance score
    entry_scores = compute_entry_scores(var_data, n_entries, significance_fn)
    selected_indices = select_variable_entries(entry_scores, vis_threshold)

    n_plot = length(selected_indices)
    n_rows, n_cols = vector_grid_layout(n_plot)
    solver_colors = solver_palette(n_solvers)

    # Extra vertical space at the top accommodates the time-step label.
    fig = Figure(size=(320 * n_cols, 260 * n_rows + 120))

    # Observable that drives the animation. Callers mutate this to advance frames.
    frame_obs = Observable(1)

    # Time-step indicator at the top of the figure; updates with frame_obs.
    Label(fig[0, 1:n_cols],
          @lift(string(time_label, " = ", time_steps[$frame_obs]));
          fontsize=20, tellwidth=false, halign=:center)

    axes, legend_handles = draw_vector_panels!(
        fig, var_data, x_vecs, x_label, var_name,
        selected_indices, solver_colors, n_cols; frame_obs=frame_obs)

    linkxaxes!(axes...)
    linkyaxes!(axes...)

    # Fix a single global y-range for the entire animation. Because the y-axes are linked,
    # setting limits on one axis propagates to all panels.
    apply_fixed_ylims!(axes[1], ylims, var_data, selected_indices)

    Legend(fig[n_rows + 1, 1:n_cols], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig, frame_obs
end
