using Test
using Logging

# Include directly to avoid loading CairoMakie in unit tests.
include("../src/select_entries.jl")

# Run `f` with warnings silenced. Deduplication intentionally warns about repeated
# coordinates; these tests verify the returned values, not the (expected) warning output.
suppress_warnings(f) = with_logger(f, NullLogger())

@testset "select_variable_entries" begin

    @testset "no filtering when length(scores) ≤ vis_threshold" begin
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices = select_variable_entries(scores, 5)
        @test indices == [1, 2, 3, 4, 5]
    end

    @testset "no filtering when length(scores) < vis_threshold" begin
        scores = [2.0, 7.0]
        indices = select_variable_entries(scores, 10)
        @test indices == [1, 2]
    end

    @testset "select top-k" begin
        # Scores: idx1=3, idx2=1, idx3=4, idx4=1, idx5=5 → top 3: idx5,idx3,idx1
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices = select_variable_entries(scores, 3)
        @test indices == [1, 3, 5]
    end

    @testset "vis_threshold=1 returns single highest-scoring index" begin
        scores = [3.0, 1.0, 4.0, 1.0, 5.0]
        indices = select_variable_entries(scores, 1)
        @test indices == [5]
    end

end  # select_variable_entries

@testset "select_variable_edges" begin

    @testset "no filtering when the number of unique indices is within threshold" begin
        # union(unique(I), unique(J)) = {1, 2, 3} of size 3 ≤ vis_threshold = 3
        I = [1, 1]
        J = [2, 3]
        scores = [5.0, 3.0]
        I_plot, J_plot, selected_indices = select_variable_edges(scores, I, J, 3)
        # All entries are displayed; selected_indices points into the original I/J.
        @test selected_indices == [1, 2]
        @test I_plot == I[selected_indices] == I
        @test J_plot == J[selected_indices] == J
    end

    @testset "filtering applies when the union of unique indices exceeds the threshold" begin
        # union(unique(I), unique(J)) = {1, 2, 3} of size 3 > vis_threshold = 2,
        # even though unique(I) and unique(J) are individually within the threshold.
        I = [1, 1]
        J = [2, 3]
        scores = [1.0, 5.0]
        I_plot, J_plot, selected_indices = select_variable_edges(scores, I, J, 2)
        # Entry (1, 3) scores highest, so rows/columns {1, 3} are selected and only entry
        # k = 2 survives.
        @test selected_indices == [2]
        @test I_plot == [1]
        @test J_plot == [3]
    end

    @testset "an entry survives only if both its endpoints are selected" begin
        # Entry (1, 4) has the highest score, so rows/columns {1, 4} are selected.
        I = [1, 2, 3]
        J = [4, 4, 4]
        scores = [10.0, 5.0, 3.0]
        I_plot, J_plot, selected_indices = select_variable_edges(scores, I, J, 2)
        # Only entry k = 1 has both endpoints in {1, 4}; (2, 4) and (3, 4) are dropped.
        @test selected_indices == [1]
        @test I_plot == [1]
        @test J_plot == [4]
    end

    @testset "repeated (i, j) collapses to the highest-scoring occurrence (unfiltered)" begin
        # union(unique(I), unique(J)) = {1, 2, 3} of size 3 ≤ vis_threshold = 5, so no
        # thresholding. Coordinate (1, 2) appears twice; the occurrence with the higher
        # score (k = 2, score 7.0) must be kept.
        I = [1, 1, 2]
        J = [2, 2, 3]
        scores = [3.0, 7.0, 1.0]
        I_plot, J_plot, selected_indices =
            suppress_warnings() do
                select_variable_edges(scores, I, J, 5)
            end
        # (1, 2) kept via its higher-scoring row k = 2, plus the unique (2, 3) at k = 3.
        @test selected_indices == [2, 3]
        @test I_plot == I[selected_indices] == [1, 2]
        @test J_plot == J[selected_indices] == [2, 3]
    end

    @testset "repeated (i, j) collapses to the highest-scoring occurrence (filtered)" begin
        # union(unique(I), unique(J)) = {1, 2, 4} of size 3 > vis_threshold = 2.
        # Indices 1 and 2 score highest (9.0), so {1, 2} is selected; among the selected
        # entries (1, 2) is repeated (k = 1 score 3.0, k = 2 score 9.0) and collapses to k = 2.
        I = [1, 1, 2]
        J = [2, 2, 4]
        scores = [3.0, 9.0, 1.0]
        I_plot, J_plot, selected_indices =
            suppress_warnings() do
                select_variable_edges(scores, I, J, 2)
            end
        @test selected_indices == [2]
        @test I_plot == [1]
        @test J_plot == [2]
    end

end  # select_variable_edges

@testset "dedup_edges_by_scores" begin

    @testset "no changes when there are no duplicates" begin
        I_plot = [1, 2, 3]
        J_plot = [2, 3, 4]
        selected_indices = [1, 2, 3]
        scores = [5.0, 6.0, 7.0]
        I_out, J_out, idx_out =
            dedup_edges_by_scores(I_plot, J_plot, selected_indices, scores)
        @test I_out == I_plot
        @test J_out == J_plot
        @test idx_out == selected_indices
    end

    @testset "keeps the highest-scoring occurrence among three duplicates" begin
        # The same coordinate (1, 2) appears three times; the row with the largest score
        # (the third, score 9.0) must survive.
        I_plot = [1, 1, 1]
        J_plot = [2, 2, 2]
        selected_indices = [1, 2, 3]
        scores = [5.0, 2.0, 9.0]
        I_out, J_out, idx_out =
            suppress_warnings() do
                dedup_edges_by_scores(I_plot, J_plot, selected_indices, scores)
            end
        @test I_out == [1]
        @test J_out == [2]
        @test idx_out == [3]
    end

    @testset "indexes the set of all edges" begin
        # The first plotted (1, 2) maps to score row 4 (8.0) and the second to row 2 (3.0), so
        # the first occurrence survives.
        I_plot = [1, 1]
        J_plot = [2, 2]
        selected_indices = [4, 2]
        scores = [0.0, 3.0, 0.0, 8.0]
        I_out, J_out, idx_out =
            suppress_warnings() do
                dedup_edges_by_scores(I_plot, J_plot, selected_indices, scores[selected_indices])
            end
        @test I_out == [1]
        @test J_out == [2]
        @test idx_out == [4]
    end

end  # dedup_edges_by_scores
