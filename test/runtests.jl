using Test

# Include directly to avoid loading CairoMakie in unit tests.
include("../src/select_entries.jl")

@testset "select_variable_entries" begin

    @testset "no filtering when length(scores) ≤ vis_threshold" begin
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices, filtered = select_variable_entries(scores, 5)
        @test indices == [1, 2, 3, 4, 5]
        @test filtered == false
    end

    @testset "no filtering when length(scores) < vis_threshold" begin
        scores = [2.0, 7.0]
        indices, filtered = select_variable_entries(scores, 10)
        @test indices == [1, 2]
        @test filtered == false
    end

    @testset "select top-k" begin
        # Scores: idx1=3, idx2=1, idx3=4, idx4=1, idx5=5 → top 3: idx5,idx3,idx1
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices, filtered = select_variable_entries(scores, 3)
        @test indices == [1, 3, 5]
        @test filtered == true
    end

    @testset "vis_threshold=1 returns single highest-scoring index" begin
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices, filtered = select_variable_entries(scores, 1)
        @test indices == [5]
        @test filtered == true
    end

end  # select_variable_entries

@testset "select_matrix_entries" begin

    @testset "non-symmetric: no filtering when both dims within threshold" begin
        # 2 unique rows, 2 unique cols, vis_threshold=3 → no filtering
        I = [1, 1, 2]
        J = [1, 2, 2]
        scores = [5.0, 3.0, 1.0]
        I_plot, J_plot, nz_idx, sel_rows, sel_cols, filtered =
            select_matrix_entries(scores, I, J, 3, false)
        @test filtered == false
        @test nz_idx == [1, 2, 3]
        @test sel_rows == [1, 2]
        @test sel_cols == [1, 2]
    end

    @testset "non-symmetric: rows and cols scored independently" begin
        # 3x3 layout, vis_threshold=2
        # Rows: 1→max(1,2)=2, 2→5, 3→3  → top 2: rows [2,3]
        # Cols: 1→1, 2→2, 3→max(5,3)=5  → top 2: cols [2,3]
        I = [1, 1, 2, 3]
        J = [1, 2, 3, 3]
        scores = [1.0, 2.0, 5.0, 3.0]
        I_plot, J_plot, orig_idx, sel_rows, sel_cols, filtered =
            select_matrix_entries(scores, I, J, 2, false)
        @test filtered == true
        @test sel_rows == [2, 3]
        @test sel_cols == [2, 3]
        # Only entry (2,3) and (3,3) survive the row/col filter
        @test orig_idx == [3, 4]
        @test I_plot == [2, 3]
        @test J_plot == [3, 3]
    end

    @testset "symmetric: no filtering when both dims within threshold" begin
        # 1 unique row, 2 unique cols → both ≤ vis_threshold=3
        I = [1, 1]
        J = [2, 3]
        scores = [5.0, 3.0]
        I_plot, J_plot, nz_idx, sel_rows, sel_cols, filtered =
            select_matrix_entries(scores, I, J, 3, true)
        @test filtered == false
        @test nz_idx == [1, 2]
        @test I_plot == I
        @test J_plot == J
    end

    @testset "symmetric: select an index in I that is not in J" begin
        # Entry (1,4) has the highest score → both 1 and 4 should be selected with vis_threshold=2.
        I = [1, 2, 3]
        J = [4, 4, 4]
        scores = [10.0, 5.0, 3.0]
        I_plot, J_plot, nz_idx, sel_rows, sel_cols, filtered =
            select_matrix_entries(scores, I, J, 2, true)
        @test filtered == true
        # Index 1 gets score 10 (via the T' column: col_scores[I[1]] = max(..., 10))
        # Index 4 gets score 10 (via col_scores[J[1]] = 10)
        # They tie for first, so both are selected.
        @test sel_rows == [1, 4]
        @test sel_cols == [1, 4]
        # Only entry k=1 has both I[k]=1 ∈ {1,4} and J[k]=4 ∈ {1,4}
        @test nz_idx == [1]
        @test I_plot == [1]
        @test J_plot == [4]
    end

end  # select_matrix_entries
