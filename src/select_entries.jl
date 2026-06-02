"""Default significance: 1-norm (sum of absolute values) across problem instances."""
default_significance(values::AbstractVector) = sum(abs, values)

"""
    select_variable_entries(scores, vis_threshold) -> selected_indices

Return the indices of the `vis_threshold` highest-scoring entries, sorted ascending.
If `length(scores) ≤ vis_threshold`, returns all indices.
"""
function select_variable_entries(scores::Vector{<:Real}, vis_threshold::Int)
    vis_threshold > 0 || throw(ArgumentError("vis_threshold must be positive"))
    length(scores) <= vis_threshold && return collect(1:length(scores))
    return sort(partialsortperm(scores, 1:vis_threshold, rev=true))
end

"""
    dedup_edges_by_scores(I_plot, J_plot, selected_indices, entry_scores)
        -> (I_plot, J_plot, selected_indices)

Collapse repeated vertex pair `(i, j)` in `I_plot`, `J_plot`, keeping only the occurrence
with the highest `entry_scores` value and emitting a warning for each colliding coordinate.
"""
function dedup_edges_by_scores(I_plot::Vector{Int}, J_plot::Vector{Int},
                                selected_indices::Vector{Int}, entry_scores::Vector{<:Real})
    # For each ordered coordinate pair, remember the index of its highest-scoring occurrence so far
    best_idx_for_pair = Dict{Tuple{Int, Int}, Int}()
    # Coordinates seen more than once; warned about after the scan.
    duplicate_pairs = Set{Tuple{Int, Int}}()
    for k in eachindex(I_plot)
        pair = (I_plot[k], J_plot[k])
        previous_position = get(best_idx_for_pair, pair, 0)
        if previous_position == 0
            # no duplicate seen so far
            best_idx_for_pair[pair] = k
        else
            push!(duplicate_pairs, pair)
            # keep the higher-scoring occurrence
            if entry_scores[k] > entry_scores[previous_position]
                best_idx_for_pair[pair] = k
            end
        end
    end

    isempty(duplicate_pairs) && return I_plot, J_plot, selected_indices

    for pair in collect(duplicate_pairs)
        @warn "$pair is repeated in the selected coordinates; keeping only the highest-scoring occurrence. Suggest using flat visualization."
    end

    # Keep one index per pair, preserving the original relative ordering of the entries.
    kept_indices = sort(collect(values(best_idx_for_pair)))
    return I_plot[kept_indices], J_plot[kept_indices], selected_indices[kept_indices]
end

"""
    select_variable_edges(entry_scores, I, J, vis_threshold)
        -> (I_plot, J_plot, selected_indices)

Determine which entries of a symmetric matrix to display, with optional thresholding.

`I`, `J` should not contain both `(i, j)` and `(j, i)`. If number of unique rows/columns
exceeds `vis_threshold`, select an induced subgraph on the `vis_threshold` highest-scoring
vertices.

Returns the coordinates `I_plot`, `J_plot` of the entries to display, together with
`selected_indices`, their positions in the original `I`/`J` (so `I_plot == I[selected_indices]`
and each entry's data is row `selected_indices[k]` of every solver's `var_data`). Both are
needed downstream: `(I_plot[k], J_plot[k])` places panel `k` on the grid, while
`selected_indices[k]` locates its data.

If the entries selected for display contain repeated exact `(i, j)` coordinates (which can
happen when the variable encodes a multi-edge graph), only the highest-scoring occurrence of
each coordinate is kept and a warning is emitted per colliding coordinate (see
`dedup_edges_by_scores`).
"""
function select_variable_edges(entry_scores::Vector{<:Real},
                                I::Vector{Int}, J::Vector{Int},
                                vis_threshold::Int)
    vis_threshold > 0 || throw(ArgumentError("vis_threshold must be positive"))
    all(I .>= 1) || throw(ArgumentError("All I indices must be >= 1"))
    all(J .>= 1) || throw(ArgumentError("All J indices must be >= 1"))

    # Set of vertices with at least one edge
    V = union(unique(I), unique(J))

    if length(V) <= vis_threshold
        # No need to filter. Collapse any repeated edges.
        I_plot, J_plot, selected_indices =
            dedup_edges_by_scores(I, J, collect(1:length(I)), entry_scores)
        return I_plot, J_plot, selected_indices
    end

    # Score each vertex by the maximum of the scores of its edges
    v_score = Dict{Int, Float64}()
    for k in 1:length(I)
        s = entry_scores[k]
        # max over all edges connected to k
        v_score[I[k]] = max(get(v_score, I[k], -Inf), s)
        v_score[J[k]] = max(get(v_score, J[k], -Inf), s)
    end
    V_sorted = sort(V, by=c -> v_score[c], rev=true)
    V_subgraph = Set(V_sorted[1:min(vis_threshold, end)])
    # Keep the edges whose endpoints are in the set of selected vertices.
    # These indices point into the original I/J.
    selected_indices = findall(
        k -> I[k] ∈ V_subgraph && J[k] ∈ V_subgraph,
        1:length(I)
    )
    isempty(selected_indices) && throw(ArgumentError("No entries selected for display; consider increasing vis_threshold"))
    # Collapse any duplicate (i, j) coordinates among the selected entries.
    I_plot, J_plot, selected_indices = dedup_edges_by_scores(
        I[selected_indices], J[selected_indices],
        selected_indices, entry_scores[selected_indices]
    )
    return I_plot, J_plot, selected_indices
end
