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
                          time_label::AbstractString="t")
    if !isnothing(ylims)
        ylims[1] < ylims[2] || throw(ArgumentError(
            "ylims must satisfy ylims[1] < ylims[2], got $ylims"))
    end
    length(var_data) >= 1 || throw(ArgumentError("At least one data array must be provided"))
    n_solvers = length(var_data)
    n_entries = size(var_data[1], 1)
    n_frames = length(time_steps)
    n_frames >= 1 || throw(ArgumentError("time_steps must contain at least one frame"))

    # All arrays must agree on the variable dimension (rows); 3D arrays must additionally
    # match the number of frames. Matrices have no time dimension and are constant across frames.
    for (i, d) in enumerate(var_data)
        size(d, 1) == n_entries || throw(DimensionMismatch(
            "Variable dimension of solver $(i): $(size(d, 1)); mismatches with variable dimension of solver 1: $(n_entries)"))
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

    # Per-entry, per-solver values for significance and ylims computations. For 3D arrays
    # this collapses both instances and frames; for matrices it is just the row across instances.
    entry_values(d, k) = ndims(d) == 3 ? vec(@view d[k, :, :]) : @view d[k, :]

    # Significance score per entry: aggregate values over ALL instances and ALL frames
    # across every solver, so that the chosen entries stay fixed throughout the animation.
    scores = [significance_fn(vcat([Vector(entry_values(d, k)) for d in var_data]...))
              for k in 1:n_entries]
    selected_indices, _ = select_variable_entries(scores, vis_threshold)

    n_plot = length(selected_indices)
    n_cols = ceil(Int, sqrt(n_plot))
    n_rows = ceil(Int, n_plot / n_cols)

    palette = Makie.wong_colors()
    solver_colors = [palette[mod1(i, length(palette))] for i in 1:n_solvers]

    # Extra vertical space at the top accommodates the time-step label.
    fig = Figure(size=(320 * n_cols, 260 * n_rows + 120))

    # Observable that drives the animation. Callers mutate this to advance frames.
    frame_obs = Observable(1)

    # Time-step indicator at the top of the figure; updates with frame_obs.
    Label(fig[0, 1:n_cols],
          @lift(string(time_label, " = ", time_steps[$frame_obs]));
          fontsize=20, tellwidth=false, halign=:center)

    legend_handles = []
    axes = Axis[]

    for (k, data_idx) in enumerate(selected_indices)
        grid_row = div(k - 1, n_cols) + 1
        grid_col = mod(k - 1, n_cols) + 1
        entry_label = isempty(var_name) ? "[$data_idx]" : "$(var_name)[$data_idx]"
        ax = Axis(fig[grid_row, grid_col]; title=entry_label, xlabel=x_label)
        push!(axes, ax)

        for (i, d) in enumerate(var_data)
            # 3D data lifts on frame_obs so each frame shows that frame's slice; matrix data
            # is plotted as a plain Vector and stays constant across frames.
            y_plot = ndims(d) == 3 ? (@lift d[data_idx, :, $frame_obs]) : d[data_idx, :]
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
        # Default: compute from full min/max across all selected entries / solvers /
        # instances / frames.
        ymin = Inf
        ymax = -Inf
        for data_idx in selected_indices
            for d in var_data
                slice = entry_values(d, data_idx)
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

    Legend(fig[n_rows + 1, 1:n_cols], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig, frame_obs
end
