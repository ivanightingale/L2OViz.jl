"""Default significance: 1-norm (sum of absolute values) across problem instances."""
default_significance(values::AbstractVector) = sum(abs, values)

"""
    select_variable_entries(scores, vis_threshold) -> (selected_indices, filtered::Bool)

Return the indices of the `vis_threshold` highest-scoring entries, sorted ascending.
If `length(scores) ≤ vis_threshold`, returns all indices and `filtered = false`.
"""
function select_variable_entries(scores::Vector{<:Real}, vis_threshold::Int)
    vis_threshold > 0 || throw(ArgumentError("vis_threshold must be positive"))
    length(scores) <= vis_threshold && return collect(1:length(scores)), false
    return sort(partialsortperm(scores, 1:vis_threshold, rev=true)), true
end

"""
    select_matrix_entries(entry_scores, I, J, vis_threshold)
        -> (I_plot, J_plot, nz_idx, sel_indices, filtered::Bool)

Determine which entries of a symmetric matrix to display, with optional thresholding.

The matrix is assumed symmetric and the COO coordinates should not contain repeated symmetry
pairs. If number of unique rows/columns exceeds `vis_threshold`, select an induced
submatrix with dimension `vis_threshold`.
"""
function select_matrix_entries(entry_scores::Vector{<:Real},
                                I::Vector{Int}, J::Vector{Int},
                                vis_threshold::Int)
    vis_threshold > 0 || throw(ArgumentError("vis_threshold must be positive"))

    # Since the COO is a half representation, both row and column index sets of the full
    # symmetric matrix are union(unique(I), unique(J)).
    unique_indices = sort(union(unique(I), unique(J)))

    # Early termination: no need to filter
    length(unique_indices) <= vis_threshold &&
        return I, J, collect(1:length(I)), unique_indices, false

    # Score each index by the maximum of the scores of its entries. Since we assume I and J
    # do not contain both (i, j) and (j, i), we need to aggregate the scores over both rows
    # and columns of the input matrix T, to effectively aggregate over columns of the full
    # symmetric matrix.
    col_scores = Dict{Int, Float64}()
    for k in 1:length(I)
        s = entry_scores[k]
        col_scores[I[k]] = max(get(col_scores, I[k], -Inf), s)  # max over the rows of T
        col_scores[J[k]] = max(get(col_scores, J[k], -Inf), s)  # max over the columns of T
    end
    # sort indices by score
    sorted_indices = sort(unique_indices, by=c -> col_scores[c], rev=true)
    sel_indices = sort(sorted_indices[1:min(vis_threshold, end)])
    sel_set = Set(sel_indices)
    nz_idx = findall(k -> I[k] ∈ sel_set && J[k] ∈ sel_set, 1:length(I))
    return I[nz_idx], J[nz_idx], nz_idx, sel_indices, true
end
