# L2OViz.jl
L2OViz.jl visualizes the solutions to multiple instances of an optimization problem.
It supports visualizing the solutions of the same instances from multiple solvers for comparison.
It also has a special feature for visualizing (the most interesting rows and columns of) matrix variables in a 2D layout of subplots which correspond to coordinates in the matrix.
This can be useful when the variables correspond to a graph for example.



## Data Format Specifications
For each variable, the values should be stored in a `Matrix` where each row contains the values of the variable in each problem instance.
For example,
```Julia
y_dim = 5
n_instances = 3
y = randn(y_dim, n_instances)
```
contains the values of a 5-dimensional variable for 3 instances of an optimization problem.

`plot_variable` accepts a variable number of `Matrix` inputs, each corresponding to a solver.

### Matrix variables
Matrix variable data should be provided in COO format.
It is assumed that, across all the problem instances, the same matrix variable has the same dimensions and sparsity structure.
Therefore, the values are still stored as a `Matrix` with `n_instances` columns, and each column contains the nonzero values of the matrix variable in each problem instance.
In other words, all the variables are treated as vector variables in L2OViz.jl.

`plot_matrix_variable` accepts a variable number of `Matrix` inputs, each corresponding to a solver.


## Visualization
The values of each variable entry across all the problem instances are visualized in a scatter point subplot.
`plot_variable` simply places the subplots side-by-side.
`plot_matrix_variable` arranges the subplots into a grid layout, where the subplot at coordinate `(i, j)` visualizes the `(i, j)` entry of the variable as specified in `(I, J)`.

The data of Solver A and Solver B do not have to be for the same problem instances.
In this case, different `x` should be provided.


### Thresholding
When the dimension of the variable to visualize is too high, `vis_threshold` limits the number of entries that are visualized.
`significance_fn` is used to select the most interesting entries of the variable.
