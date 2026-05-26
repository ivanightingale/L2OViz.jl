module L2OViz

using CairoMakie

include("select_entries.jl")
include("plot_variable.jl")
include("plot_matrix_variable.jl")
include("animate_variable.jl")
include("animate_matrix_variable.jl")

export plot_variable, plot_matrix_variable, animate_variable, animate_matrix_variable

end
