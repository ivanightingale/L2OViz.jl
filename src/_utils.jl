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
        throw(ArgumentError("x must be either a single AbstractVector or multiple AbstractVectors (one per solver)"))
    end
end

# Per-solver scatter color, cycling through Makie.wong_colors() if there are more solvers
# than palette entries.
function solver_palette(n_solvers::Int)
    palette = Makie.wong_colors()
    return [palette[mod1(i, length(palette))] for i in 1:n_solvers]
end

# Per-row significance score for the variable: aggregate every solver's values at row `k`
# across all instances (and all frames, for 3D data) and reduce with `significance_fn`.
# Works for both static and animated input transparently via `entry_values` dispatch.
function compute_entry_scores(var_data, n_entries::Int, significance_fn)
    return [significance_fn(vcat([Vector(entry_values(d, k)) for d in var_data]...))
            for k in 1:n_entries]
end

# Auto y-axis limits with 5% padding, computed across the given entries of every solver's
# data. Used by animate_* to fix a single y-range across all frames so that the animation
# does not auto-rescale frame-by-frame.
function compute_ylim_range(var_data, entry_indices)
    ymin = Inf
    ymax = -Inf
    for k in entry_indices
        for d in var_data
            slice = entry_values(d, k)
            ymin = min(ymin, minimum(slice))
            ymax = max(ymax, maximum(slice))
        end
    end
    span = ymax - ymin
    pad = span > 0 ? 0.05 * span : 0.5 * max(abs(ymax), 1.0)
    return ymin - pad, ymax + pad
end

# Apply user-supplied ylims, or compute & apply auto ylims with padding.
# Since the axes are linked, setting limits on one axis propagates to every panel.
function apply_fixed_ylims!(ax, ylims_user, var_data, entry_indices)
    if isnothing(ylims_user)
        lo, hi = compute_ylim_range(var_data, entry_indices)
        ylims!(ax, lo, hi)
    else
        ylims!(ax, ylims_user[1], ylims_user[2])
    end
end

# Panel titles. Vector variant produces "[k]" or "var_name[k]"; matrix variant produces
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

# Matrix layout: when entries were filtered, compress to a length(sel_indices) ×
# length(sel_indices) submatrix; otherwise keep the full effective_n_full × effective_n_full
# grid. `grid_pos(i, j)` maps original (i, j) → grid cell.
function matrix_grid_layout(sel_indices, filtered::Bool, effective_n_full::Int)
    if filtered
        index_map = Dict(c => idx for (idx, c) in enumerate(sel_indices))
        n = length(sel_indices)
        return n, n, (i, j) -> (index_map[i], index_map[j])
    else
        return effective_n_full, effective_n_full, (i, j) -> (i, j)
    end
end

# Draw the vector-variable panel grid into `parent` (a Figure or GridLayout). Returns
# (axes, legend_handles). `frame_obs` is `nothing` for static plots and an Observable{Int}
# for animations; this is what selects between a plain Vector and a lifted Observable in
# `plot_y` for each 3D solver array.
function draw_vector_panels!(parent, var_data, x_vecs, x_label, var_name,
                             selected_indices, solver_colors, n_cols; frame_obs=nothing)
    legend_handles = []
    axes = Axis[]
    for (k, data_idx) in enumerate(selected_indices)
        grid_row = div(k - 1, n_cols) + 1
        grid_col = mod(k - 1, n_cols) + 1
        ax = Axis(parent[grid_row, grid_col];
                  title=entry_label(var_name, data_idx), xlabel=x_label)
        push!(axes, ax)
        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], plot_y(d, data_idx, frame_obs);
                         color=solver_colors[i])
            k == 1 && push!(legend_handles, p)
        end
    end
    return axes, legend_handles
end

# Same as `draw_vector_panels!`, but for a COO-symmetric matrix variable. `grid_pos` maps
# the original (I, J) coordinates to (row, col) cells of `gl` (a GridLayout). `nz_idx`
# maps the k-th plotted entry back to its row in each solver's data array.
function draw_matrix_panels!(gl, var_data, x_vecs, x_label, var_name,
                             I_plot, J_plot, nz_idx, grid_pos,
                             solver_colors; frame_obs=nothing)
    legend_handles = []
    axes = Axis[]
    for k in eachindex(I_plot)
        gr, gc = grid_pos(I_plot[k], J_plot[k])
        ax = Axis(gl[gr, gc];
                  title=entry_label(var_name, I_plot[k], J_plot[k]), xlabel=x_label)
        push!(axes, ax)
        coo_row = nz_idx[k]
        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x_vecs[i], plot_y(d, coo_row, frame_obs);
                         color=solver_colors[i])
            k == 1 && push!(legend_handles, p)
        end
    end
    return axes, legend_handles
end
