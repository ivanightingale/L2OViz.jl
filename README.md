# L2OViz.jl
L2OViz.jl visualizes the solutions to multiple instances of an optimization problem.
It supports visualizing the solutions of the same instances from multiple solvers for comparison.
It also has a special feature for visualizing (the most interesting rows and columns of) matrix variables in a 2D layout of subplots which correspond to coordinates in the matrix.
This can be useful when the variables correspond to a graph for example.



## Data Format Specifications
For each variable, the values should be stored in a `Matrix` where each row contains the values of the variable in each problem instance.
Each `Matrix` should have the same number of columns, `n_instances`.
For example,
```Julia
y_dim = 5
n_instances = 3
y = randn(y_dim, n_instances)
```
contains the data of a 5-dimensional variable for 3 instances of an optimization problem.

### Matrix variables
Matrix variable data should be provided in COO format.
Therefore, the values are still stored as a `Matrix` with `n_instances` columns, where each row contains the values of the matrix variable in each problem instance.
In other words, all the variables are treated as vector variables in L2OViz.jl.

Currently, it is assumed that the same matrix variable has the same dimensions and sparsity structure across all the problem instances. This shared sparsity structure should be provided in the form of `(I, J)`, separately from the matrix variable values.


## Visualization
By default, each entry of a variable is visualized as a scatter point subplot in order.
When matrix coordinates `(I, J)` are provided, the subplots are arranged into a grid layout, where the subplot at coordinate `(i, j)` visualizes the `(i, j)` entry of the variable as specified in `(I, J)`.

If the x axis is not provided, it will simply be the index of the problem instance in the data.
Otherwise, the shared x values for all the subplots should be provided as a `Vector` with length `n_instances`.
