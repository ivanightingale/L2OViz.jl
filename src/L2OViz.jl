module L2OViz

using CairoMakie

include("select_entries.jl")
include("_utils.jl")
include("plot_variable.jl")
include("plot_graph_variable.jl")
include("animate_variable.jl")
include("animate_graph_variable.jl")

export plot_variable, plot_graph_variable, animate_variable, animate_graph_variable

end
