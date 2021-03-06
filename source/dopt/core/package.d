/**
    This package contains the framework for constructing and executing operation graphs.

    $(UL
        $(LI $(D dopt.core.ops) provides functions for constructing nodes in the operation graph.)
        $(LI $(D dopt.core.grads) provides functions for computing the derivatives of operations.)
        $(LI $(D dopt.core.cpu) contains a backend that executes operation graphs using the CPU.)
        $(LI $(D dopt.core.cuda) contains a backend that executes operation graphs using a CUDA enabled GPU.)
    )

    Authors: Henry Gouk
*/
module dopt.core;

public
{
    import dopt.core.cpu;
    import dopt.core.cuda;
    import dopt.core.grads;
    import dopt.core.ops;
    import dopt.core.types;
}

alias Evaluator = Buffer[] delegate(Operation[] ops, Buffer[Operation] args);
alias Compiler = Plan delegate(Operation[] ops);

__gshared Evaluator defaultEvaluator;
__gshared Compiler defaultCompiler;

shared static this()
{
    import std.functional : toDelegate;

    dopt.core.ops.initialize();
    dopt.core.grads.initialize();
    dopt.core.cpu.initialize();

    try
    {
        dopt.core.cuda.initialize();
        defaultEvaluator = toDelegate(&evaluateCUDA);
        defaultCompiler = (Operation[] ops) { return new CUDAPlan(ops); };
    }
    catch(Exception e)
    {
        defaultEvaluator = toDelegate(&evaluateCPU);
        defaultCompiler = (Operation[] ops) { return new CPUPlan(ops); };
    }
}

/**
    Evaluates a several nodes from the operation graph.

    Params:
        ops = The nodes of the operation graph that values should be computed for.
        args = A set of variable assignments.

    Returns:
        An array of $(D Buffer) objects, each containing the value of the corresponding element in $(D ops).
*/
Buffer[] evaluate(Operation[] ops, Buffer[Operation] args = null)
{
    return defaultEvaluator(ops, args);
}

/**
    Evaluates an operation graph with a single root node.

    This overload is here for convenience. Internally, the multi-output version of evaluate is called.

    Params:
        op = The root node of the operation graph.
        args = A set of variable assignments.

    Returns:
        A $(D Buffer) containing the result of the computation.
*/
Buffer evaluate(Operation op, Buffer[Operation] args = null)
{
    return evaluate([op], args)[0];
}

/**
    Compile an Operation graph into a reusable execution plan.

    This can be useful in the case where the function might need to be evaluated multiple times, as it will avoid
    repeating initialisation and optimisation procedures.

    Params:
        outputs = The output nodes of the Operation graph.
    
    Returns:
        A $(D Plan) that can be executed.
*/
Plan compile(Operation[] outputs)
{
    return defaultCompiler(outputs);
}

class Plan
{
    public
    {
        this(Operation[] outputs)
        {
            import std.array : array;

            mOutputs = outputs.array();
        }

        /**
            Executes the plan.

            Params:
                args = A set of variable assignments.
        */
        Buffer[] execute(Buffer[Operation] args = null)
        {
            auto rets = new Buffer[mOutputs.length];

            foreach(i, o; mOutputs)
            {
                rets[i] = Buffer(new ubyte[o.outputType.volume * o.outputType.elementType.sizeOf()]);
            }

            execute(args, rets);

            return rets;
        }

        ///
        void execute(Buffer[Operation] args, Buffer[] rets)
        {
            executeImpl(args, rets);
        }
    }

    protected
    {
        Operation[] mOutputs;

        abstract void executeImpl(Buffer[Operation] args, Buffer[] rets);
    }
}