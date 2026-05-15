"""
    plot_variable(var_data::Matrix...; solver_names=nothing, x=nothing, xlabel=nothing,
                  var_name="", vis_threshold::Int=20, significance_fn=default_significance) -> Figure

Visualize each entry of a vector variable across multiple problem instances.

Pass one or more `(n_entries × n_instances)` matrices, one per solver. Series are overlaid on
each subplot with a shared legend. Solver names default to "Solver 1", "Solver 2", … when not
provided via `solver_names`.

Subplots are tiled into a roughly square grid. The x-axis defaults to instance indices with
label `"Instance"`; if custom `x` values are provided the label defaults to `"Unknown Parameter"`
unless `xlabel` is also given.

Only the top-`vis_threshold` most significant entries are visualized. `significance_fn`
(default: 1-norm) is applied to `vcat([d[k, :] for d in var_data]...)` to get the score of
each entry. Entry labels always reflect the original indices.
"""
function plot_variable(var_data::Matrix...; solver_names=nothing, x=nothing, xlabel=nothing,
                       var_name="", vis_threshold::Int=20, significance_fn=default_significance)
    @assert length(var_data) >= 1 "At least one data matrix must be provided"
    n_solvers = length(var_data)
    first_data = var_data[1]
    n_entries, n_instances = size(first_data)
    for (i, d) in enumerate(var_data)
        @assert size(d) == (n_entries, n_instances) "All data matrices must have size ($(n_entries), $(n_instances)); solver $(i) has size $(size(d))"
    end
    if isnothing(solver_names)
        solver_names = ["Solver $i" for i in 1:n_solvers]
    else
        @assert length(solver_names) == n_solvers "solver_names must have length $n_solvers"
    end

    if isnothing(x)
        x = collect(1:n_instances)
        x_label = "Instance"
    else
        @assert length(x) == n_instances "Length of x must equal number of instances ($n_instances)"
        x_label = isnothing(xlabel) ? "Unknown Parameter" : xlabel
    end

    # For each entry, combine values across all solvers and all instances for significance score
    scores = [significance_fn(vcat([d[k, :] for d in var_data]...)) for k in 1:n_entries]
    selected_indices, _ = select_variable_entries(scores, vis_threshold)

    n_plot = length(selected_indices)
    n_cols = ceil(Int, sqrt(n_plot))
    n_rows = ceil(Int, n_plot / n_cols)

    palette = Makie.wong_colors()
    solver_colors = [palette[mod1(i, length(palette))] for i in 1:n_solvers]

    fig = Figure(size=(320 * n_cols, 260 * n_rows + 60))

    legend_handles = []

    for (k, data_idx) in enumerate(selected_indices)
        grid_row = div(k - 1, n_cols) + 1
        grid_col = mod(k - 1, n_cols) + 1
        entry_label = isempty(var_name) ? "[$data_idx]" : "$(var_name)[$data_idx]"
        ax = Axis(fig[grid_row, grid_col]; title=entry_label, xlabel=x_label, ylabel="Value")

        for (i, d) in enumerate(var_data)
            p = scatter!(ax, x, d[data_idx, :]; color=solver_colors[i])
            if k == 1
                push!(legend_handles, p)
            end
        end
    end

    Legend(fig[n_rows + 1, 1:n_cols], legend_handles, solver_names;
           orientation=:horizontal, tellwidth=false)

    return fig
end
