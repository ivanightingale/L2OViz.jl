"""Default significance: 1-norm (sum of absolute values) across problem instances."""
default_significance(values::AbstractVector) = sum(abs, values)

"""
    select_variable_entries(scores, vis_threshold) -> (selected_indices, filtered::Bool)

Return the indices of the `vis_threshold` highest-scoring entries, sorted ascending.
If `length(scores) ≤ vis_threshold`, returns all indices and `filtered = false`.
"""
function select_variable_entries(scores::Vector{<:Real}, vis_threshold::Int)
    @assert vis_threshold > 0 "vis_threshold must be positive"
    length(scores) <= vis_threshold && return collect(1:length(scores)), false
    return sort(partialsortperm(scores, 1:vis_threshold, rev=true)), true
end

"""
    select_matrix_entries(entry_scores, I, J, vis_threshold, symmetric)
        -> (I_plot, J_plot, nz_idx, sel_rows, sel_cols, filtered::Bool)

Determine which matrix entries to display, with optional thresholding.

At most `vis_threshold` rows and at most `vis_threshold` columns are selected. When `symmetric = false`, rows and columns are scored and selected independently. When `symmetric = true`, row and column significance are the same, and row-column pairs are selected together.
"""
function select_matrix_entries(entry_scores::Vector{<:Real},
                                I::Vector{Int}, J::Vector{Int},
                                vis_threshold::Int,
                                symmetric::Bool)
    @assert vis_threshold > 0 "vis_threshold must be positive"

    unique_rows = sort(unique(I))
    unique_cols = sort(unique(J))

    # Same early termination for both symmetric and non-symmetric
    length(unique_rows) <= vis_threshold && length(unique_cols) <= vis_threshold &&
        return I, J, collect(1:length(I)), unique_rows, unique_cols, false

    if symmetric
        # Score each column by the maximum of the scores of its entries. Since we assume I and J
        # do not contain both (i, j) and (j, i), we need to consider the columns of both T and T'
        col_scores = Dict{Int, Float64}()
        for k in 1:length(I)
            s = entry_scores[k]
            col_scores[J[k]] = max(get(col_scores, J[k], 0.0), s)  # max over the columns of T
            col_scores[I[k]] = max(get(col_scores, I[k], 0.0), s)  # max over the columns of T'
        end
        # sort columns of the original matrix (union of columns of T and T') by score
        sorted_cols = sort(union(unique_rows, unique_cols), by=c -> col_scores[c], rev=true)
        sel_indices = sort(sorted_cols[1:min(vis_threshold, end)])
        sel_set = Set(sel_indices)
        nz_idx = findall(k -> I[k] ∈ sel_set && J[k] ∈ sel_set, 1:length(I))
        return I[nz_idx], J[nz_idx], nz_idx, sel_indices, sel_indices, true

    else
        # Score rows and columns independently
        row_scores = Dict{Int, Float64}()
        col_scores = Dict{Int, Float64}()
        for k in 1:length(I)
            s = entry_scores[k]
            row_scores[I[k]] = max(get(row_scores, I[k], 0.0), s)
            col_scores[J[k]] = max(get(col_scores, J[k], 0.0), s)
        end

        sel_rows = sort(sort(unique_rows, by=r -> row_scores[r], rev=true)[1:min(vis_threshold, end)])
        sel_cols = sort(sort(unique_cols, by=c -> col_scores[c], rev=true)[1:min(vis_threshold, end)])
        sel_row_set, sel_col_set = Set(sel_rows), Set(sel_cols)

        nz_idx = findall(k -> I[k] ∈ sel_row_set && J[k] ∈ sel_col_set, 1:length(I))
        return I[nz_idx], J[nz_idx], nz_idx, sel_rows, sel_cols, true
    end
end
