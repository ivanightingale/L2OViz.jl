# Per-entry values across all instances (and frames for 3D animation data).
entry_values(d::AbstractMatrix, k::Int) = @view d[k, :]
entry_values(d::AbstractArray{<:Any, 3}, k::Int) = vec(@view d[k, :, :])

# Return the y-data to pass to `scatter!` for a single (entry, solver) pair.
# A Matrix becomes a plain Vector (does not relate to any animation frame).
# A 3D array becomes an Observable that re-fires whenever `frame_obs` changes.
plot_y(d::AbstractMatrix, k::Int, ::Any) = d[k, :]
plot_y(d::AbstractArray{<:Any, 3}, k::Int, frame_obs::Observable) = @lift d[k, :, $frame_obs]

# Resolve `solver_names`: default to placeholder names if not supplied, otherwise validate length.
resolve_solver_names(::Nothing, n_solvers::Int) = ["Solver $i" for i in 1:n_solvers]
function resolve_solver_names(solver_names, n_solvers::Int)
    if isa(solver_names, AbstractVector{<:AbstractString})
        length(solver_names) == n_solvers || throw(ArgumentError(
            "solver_names must have length $n_solvers, got $(length(solver_names))"))
        return collect(solver_names)
    else
        throw(ArgumentError("solver_names must be a Vector of Strings or nothing"))
    end
end

function validate_var_data_dims(var_data)
    # All matrices must have the same number of rows (dimension of the variable)
    n_entries = size(var_data[1], 1)
    n_entries >= 1 ||
        throw(ArgumentError("var_data must have at least one entry (size(var_data[1], 1) > 0)"))
    for (i, d) in enumerate(var_data)
        size(d, 1) == n_entries || throw(DimensionMismatch(
            "Variable dimension of solver $(i): $(size(d, 1)); mismatches with variable dimension of solver 1: $(n_entries)"))
    end
    return n_entries
end

function validate_var_data_dims(var_data, n_frames::Int)
    # All arrays must have the same length in the first dimension (dimension of the variable)
    # 3D arrays must match the number of frames.
    # (Matrices have no time dimension and are constant across frames.)
    n_entries = validate_var_data_dims(var_data)
    for (i, d) in enumerate(var_data)
        if ndims(d) == 3
            size(d, 3) == n_frames || throw(DimensionMismatch(
                "Number of frames in data of solver $(i): $(size(d, 3)); does not equal length(time_steps) = $(n_frames)"))
        end
    end
    return n_entries
end

# Resolve `x` into one Vector per solver. `x` may be a single shared Vector (broadcast to
# every solver) or a Vector of per-solver Vectors. Validates that each `x` Vector's length
# matches the number of instances in that solver's data array.
function resolve_x_vecs(x, var_data)
    n_solvers = length(var_data)
    if all(isa.(x, AbstractVector))
        # x is multiple vectors, one per solver
        x_vecs = collect(x)
        length(x_vecs) == n_solvers || throw(ArgumentError(
            "Number of x vectors ($(length(x_vecs))) must equal number of data arrays ($n_solvers)"))
        for (i, d) in enumerate(var_data)
            n_instances_i = size(d, 2)
            length(x_vecs[i]) == n_instances_i || throw(DimensionMismatch(
                "Length of x[$(i)] ($(length(x_vecs[i]))) must equal number of columns in data array $(i) ($n_instances_i)"))
        end
        return x_vecs
    elseif isa(x, AbstractVector)
        # x is a single vector shared across all solvers
        for (i, d) in enumerate(var_data)
            n_instances_i = size(d, 2)
            length(x) == n_instances_i || throw(DimensionMismatch(
                "Length of x ($(length(x))) must equal number of columns in data array $(i) ($n_instances_i)"))
        end
        return [x for _ in 1:n_solvers]
    else
        throw(ArgumentError("x must be either a single AbstractVector or multiple AbstractVectors (one per solver); got $(typeof(x))"))
    end
end

# Per-solver scatter color, cycling through `palette` if there are more solvers than palette
# entries. `palette` may be:
# - `nothing`: Makie's default categorical palette (wong_colors).
# - a `Symbol`: the name of a Makie/ColorSchemes palette (e.g. `:tab10`, `:viridis`).
# - a vector of colors (anything Makie accepts, e.g. `[:red, :blue]`).
function solver_palette(n_solvers::Int, palette=nothing)
    colors = resolve_palette_colors(palette, n_solvers)
    isempty(colors) && throw(ArgumentError("palette must contain at least one color"))
    return [colors[mod1(i, length(colors))] for i in 1:n_solvers]
end

resolve_palette_colors(::Nothing, ::Int) = Makie.wong_colors()
resolve_palette_colors(palette, ::Int) = palette

# Resolve a named palette into a vector of colors. `categorical_colors` samples continuous
# colormaps (e.g. `:viridis`) into `n_solvers` evenly spaced colors so distinct solvers stay
# visually separated, and returns categorical schemes' (e.g. `:tab10`) discrete swatches. It
# errors only when a categorical scheme has fewer swatches than `n_solvers`, in which case we
# fall back to the full swatch set for `solver_palette` to cycle through.
function resolve_palette_colors(palette::Symbol, n_solvers::Int)
    try
        return Makie.categorical_colors(palette, n_solvers)
    catch err
        err isa ErrorException || rethrow()
        return Makie.to_colormap(palette)
    end
end

# Per-row significance score for the variable: aggregate every solver's values at row `k`
# across all instances (and all frames, for 3D data) and reduce with `significance_fn`.
# Works for both static and animated input transparently via `entry_values` dispatch.
function compute_entry_scores(var_data, n_entries::Int, significance_fn)
    return [significance_fn(vcat([Vector(entry_values(d, k)) for d in var_data]...))
            for k in 1:n_entries]
end

# Min/max over the given entries of every solver's data (and over all frames for 3D data).
function data_extrema(var_data, entry_indices)
    ymin = Inf
    ymax = -Inf
    for k in entry_indices
        for d in var_data
            slice = entry_values(d, k)
            ymin = min(ymin, minimum(slice))
            ymax = max(ymax, maximum(slice))
        end
    end
    return ymin, ymax
end

# Auto y-axis limits with 5% padding, computed across the given entries of every solver's
# data. Used by animate_* to fix a single y-range across all frames so that the animation
# does not auto-rescale frame-by-frame.
# The padding is applied in the axis' transformed space, so that a nonlinear `yscale` gets
# visually even margins.
function compute_ylim_range(var_data, entry_indices, yscale)
    ymin, ymax = data_extrema(var_data, entry_indices)
    lo, hi = yscale(ymin), yscale(ymax)
    span = hi - lo
    pad = span > 0 ? 0.05 * span : 0.5 * max(abs(hi), 1.0)
    inverse = Makie.inverse_transform(yscale)
    return inverse(lo - pad), inverse(hi + pad)
end

# Apply user-supplied ylims, or compute & apply auto ylims with padding.
# Since the axes are linked, setting limits on one axis propagates to every panel.
function apply_fixed_ylims!(ax, ylims_user, var_data, entry_indices, yscale)
    if isnothing(ylims_user)
        lo, hi = compute_ylim_range(var_data, entry_indices, yscale)
        ylims!(ax, lo, hi)
    else
        ylims!(ax, ylims_user[1], ylims_user[2])
    end
end

# Largest number of decades a symlog axis is allowed to span on each side of zero. Bounds the
# linear region from below so that a single near-zero value cannot stretch the axis out.
const SYMLOG_MAX_DECADES = 8

# Half-width of the linear region of a symlog y-axis, derived from the data: the smallest
# nonzero magnitude present, floored at `SYMLOG_MAX_DECADES` below the largest magnitude.
# Returns `nothing` when every value is zero, where a symlog axis is not meaningful.
function symlog_linthresh(var_data, entry_indices)
    max_abs = 0.0
    min_nonzero_abs = Inf
    for k in entry_indices
        for d in var_data
            for value in entry_values(d, k)
                magnitude = abs(value)
                magnitude == 0 && continue
                max_abs = max(max_abs, magnitude)
                min_nonzero_abs = min(min_nonzero_abs, magnitude)
            end
        end
    end
    max_abs > 0 || return nothing
    return clamp(min_nonzero_abs, max_abs / 10.0^SYMLOG_MAX_DECADES, max_abs)
end

function resolve_yscale(symlog::Bool, var_data, entry_indices)
    symlog || return identity
    linthresh = symlog_linthresh(var_data, entry_indices)
    if isnothing(linthresh)
        @warn "symlog=true, but every displayed value is zero; falling back to a linear y-axis."
        return identity
    end
    return Makie.Symlog10(linthresh)
end

# Panel titles. Vector variant produces "[k]" or "var_name[k]"; graph variant produces
# "[i,j]" or "var_name[i,j]".
entry_label(var_name::AbstractString, idx::Int) =
    isempty(var_name) ? "[$idx]" : "$(var_name)[$idx]"
entry_label(var_name::AbstractString, i::Int, j::Int) =
    isempty(var_name) ? "[$i,$j]" : "$(var_name)[$i,$j]"

# Vector layout: arrange `n_plot` panels into a near-square grid (n_cols ≈ sqrt(n_plot)).
function vector_grid_layout(n_plot::Int)
    n_cols = ceil(Int, sqrt(n_plot))
    n_rows = ceil(Int, n_plot / n_cols)
    return n_rows, n_cols
end

# Compute dimension of the plot grid and the mapping (i, j) → grid cell.
function matrix_grid_layout(I_plot, J_plot)
    # (i, j) should be sorted in the resulting grid
    V_subgraph_sorted = sort(union(unique(I_plot), unique(J_plot)))
    index_map = Dict(c => idx for (idx, c) in enumerate(V_subgraph_sorted))
    n = length(V_subgraph_sorted)
    return n, (i, j) -> (index_map[i], index_map[j])
end

# Draw the vector-variable panel grid into `parent` (a Figure or GridLayout). Returns
# (axes, legend_handles). `frame_obs` is `nothing` for static plots and an Observable{Int}
# for animations; this is what selects between a plain Vector and a lifted Observable in
# `plot_y` for each 3D solver array.
function draw_vector_panels!(parent, var_data, x_vecs, x_label, var_name,
                             selected_indices, solver_colors, n_cols; frame_obs=nothing,
                             yscale=identity, alpha=1.0)
    legend_handles = []
    axes = Axis[]
    for (k, data_idx) in enumerate(selected_indices)
        grid_row = div(k - 1, n_cols) + 1
        grid_col = mod(k - 1, n_cols) + 1
        ax = Axis(parent[grid_row, grid_col];
                  title=entry_label(var_name, data_idx), xlabel=x_label, yscale=yscale)
        push!(axes, ax)
        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], plot_y(d, data_idx, frame_obs);
                         color=solver_colors[i], alpha=alpha)
            k == 1 && push!(legend_handles, p)
        end
    end
    return axes, legend_handles
end

# Same as `draw_vector_panels!`, but for a graph variable. `grid_pos` maps the original (I, J)
# to (row, col) cells of `gl` (a GridLayout). `selected_indices` maps the k-th plotted entry
# back to its row in each solver's data array.
function draw_matrix_panels!(gl, var_data, x_vecs, x_label, var_name,
                             I_plot, J_plot, selected_indices, grid_pos,
                             solver_colors; frame_obs=nothing, yscale=identity, alpha=1.0)
    legend_handles = []
    axes = Axis[]
    for k in eachindex(I_plot)
        gr, gc = grid_pos(I_plot[k], J_plot[k])
        ax = Axis(gl[gr, gc];
                  title=entry_label(var_name, I_plot[k], J_plot[k]), xlabel=x_label,
                  yscale=yscale)
        push!(axes, ax)
        coo_row = selected_indices[k]
        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], plot_y(d, coo_row, frame_obs);
                         color=solver_colors[i], alpha=alpha)
            k == 1 && push!(legend_handles, p)
        end
    end
    return axes, legend_handles
end
