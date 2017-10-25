/**
    Authors: Henry Gouk
*/
module dopt.nnet.layers.datasource;

import dopt;

/**
    Creates a $(D Layer) object that simply wraps an $(D Operation).

    This is most commonly used for wrapping an $(D Operation) made with $(D dopt.core.ops.float32()).
*/
Layer dataSource(Operation var)
{
    return new Layer(null, var, var, null);
}