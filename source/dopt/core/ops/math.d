/**
    Contains common maths operations.

    Authors: Henry Gouk
*/
module dopt.core.ops.math;

import std.algorithm;
import std.conv;
import std.functional;
import std.range;

import dopt.core.ops;
import dopt.core.types;

package
{
    void initialize()
    {
        void registerPointwiseBinary(string opName)
        {
            bool verifier(Operation op)
            {
                return op.deps.length == 2 && op.deps[0].outputType == op.deps[1].outputType;
            }

            TensorType judge(Operation op)
            {
                return TensorType(op.deps[0].outputType);
            }

            registerOperation(opName, OpDef(&verifier, &judge));
        }

        void registerPointwiseUnary(string opName)
        {
            bool verifier(Operation op)
            {
                return true;
            }

            TensorType judge(Operation op)
            {
                return TensorType(op.deps[0].outputType);
            }

            registerOperation(opName, OpDef(&verifier, &judge));
        }

        foreach(opName; chain(arith, comp, binfunc))
        {
            registerPointwiseBinary(opName);
        }

        foreach(opName; unfunc)
        {
            registerPointwiseUnary(opName);
        }

        registerOperation("matmul", OpDef(toDelegate(&verifyMatmul), toDelegate(&judgeMatmul)));
        registerOperation("sum", OpDef(toDelegate(&verifySum), toDelegate(&judgeSum)));
        registerOperation("argmin", OpDef(toDelegate(&verifyArgmin), toDelegate(&judgeArgmin)));

        //maxElement and sum are both reduction operations
        registerOperation("maxElement", OpDef(toDelegate(&verifySum), toDelegate(&judgeSum)));
    }
}

private
{
    immutable string[] arith = ["add", "sub", "mul", "div"];
    immutable string[] comp = ["lt", "lte", "gt", "gte", "eq", "neq"];
    immutable string[] binfunc = ["max", "min", "pow"];
    immutable string[] unfunc = ["neg", "abs", "sgn", "exp", "log", "sqrt"];

    string createAllCtors()
    {
        string createOpCtor(string opName, size_t numDeps)
        {
            auto params = iota(0, numDeps)
                        .map!(x => "Operation p" ~ x.to!string)
                        .joiner(", ")
                        .to!string();

            auto args = iota(0, numDeps)
                    .map!(x => "p" ~ x.to!string)
                    .joiner(", ")
                    .to!string;

            return "
                    Operation " ~ opName ~ "(" ~ params ~ ", string mod = __MODULE__, size_t line = __LINE__)
                    {
                        return createOperation(\"" ~ opName ~ "\", [" ~ args ~ "], null, mod, line);
                    }
                ";
        }

        string binctors = chain(arith, comp, binfunc)
                         .map!(x => createOpCtor(x, 2))
                         .joiner("\n")
                         .to!string;

        auto unctors = unfunc
                      .map!(x => createOpCtor(x, 1))
                      .joiner("\n")
                      .to!string;

        return binctors ~ unctors;
    }

    bool verifyMatmul(Operation op)
    {
        return op.deps.length == 2
            && op.deps[0].outputType.rank == 2
            && op.deps[1].outputType.rank == 2
            && op.deps[0].outputType.elementType == op.deps[1].outputType.elementType
            && op.deps[0].outputType.shape[1] == op.deps[1].outputType.shape[0];
    }

    TensorType judgeMatmul(Operation op)
    {
        return TensorType(op.deps[0].outputType.elementType,
            [op.deps[0].outputType.shape[0], op.deps[1].outputType.shape[1]]);
    }

    bool verifySum(Operation op)
    {
        if(op.deps.length != 1)
        {
            return false;
        }

        if(("axes" in op.attributes) is null || op.attributes["axes"].peek!(size_t[]) is null)
        {
            return false;
        }

        auto axes = op.attributes["axes"].get!(size_t[]);

        return axes.all!(x => x < op.deps[0].rank) &&
               axes.map!(x => size_t(x)).array().sort().uniq().count() == axes.length;
    }

    TensorType judgeSum(Operation op)
    {
        auto t = op.deps[0].outputType;
        auto axes = op.attributes["axes"].get!(size_t[]);

        auto newShape = t
                       .shape
                       .zip(iota(0, t.shape.length))
                       .filter!(x => !axes.canFind(x[1]))
                       .map!(x => x[0])
                       .array();

        return TensorType(t.elementType, newShape);
    }

    bool verifyArgmin(Operation op)
    {
        return op.deps.length == 1
            && ("axis" in op.attributes)
            && (op.attributes["axis"].peek!size_t !is null)
            && (op.attributes["axis"].get!size_t < op.deps[0].rank);
    }

    TensorType judgeArgmin(Operation op)
    {
        auto shape = op.deps[0].shape.dup;
        shape[op.attributes["axis"].get!size_t] = 1;

        return TensorType(DataType.int32, shape);
    }
}

mixin(createAllCtors());

/**
    Computes the matrix multiplication between two rank-2 tensors.

    Params:
        lhs = The tensor on the left-hand side of the operation.
        rhs = The tensor on the right-hand side of the operation.

    Returns:
        The resulting operation.
*/
Operation matmul(Operation lhs, Operation rhs, string mod = __MODULE__, size_t line = __LINE__)
{
    return createOperation("matmul", [lhs, rhs], null, mod, line);
}

///
unittest
{
    import dopt.core.cpu : evaluate;
    
    auto a = float32([2, 1], [
        1.0f,
        2.0f
    ]);
    
    auto b = float32([1, 2], [
        3.0f, 4.0f
    ]);

    auto c = matmul(a, b);

    assert(c.evaluate().as!float == [
        3.0f, 4.0f,
        6.0f, 8.0f
    ]);
}

/**
    Computes a sum reduction along the specified axes.

    Params:
        op = The input to the reduction.
        axes = The axes the reduction should be performed along.

    Returns:
        The resulting operation.
*/
Operation sum(Operation op, size_t[] axes = [], string mod = __MODULE__, size_t line = __LINE__)
{
    import std.variant : Variant;

    if(op.rank == 0)
    {
        return op.reshape(op.shape);
    }

    if(axes.length == 0)
    {
        axes = iota(0, op.rank).array();
    }
    
    return createOperation("sum", [op], ["axes": Variant(axes)], mod, line);
}

///
unittest
{
    import dopt.core.cpu : evaluate;

    auto s1 = float32([2], [0.5, 1.5]).sum();
    auto s2 = float32([2, 2], [0, 1, 0, 5]).sum();
    auto s3 = float32([2, 2], [0, 1, 0, 5]).sum([0]);
    auto s4 = float32([2, 2], [0, 1, 0, 5]).sum([1]);

    assert(s1.evaluate().as!float == [2.0f]);
    assert(s2.evaluate().as!float == [6.0f]);
    assert(s3.evaluate().as!float == [0.0f, 6.0f]);
    assert(s4.evaluate().as!float == [1.0f, 5.0f]);
}

/**
    Performs an argmin over the specified dimension.

    Params:
        input = The operation to perform argmin on.
        axis = The diension the argmin should be performed over.
    
    Returns:
        The new argmin operation.
*/
Operation argmin(Operation input, size_t axis, string mod = __MODULE__, size_t line = __LINE__)
{
    import std.variant : Variant;

    return createOperation("argmin", [input], ["axis": Variant(axis)], mod, line);
}

unittest
{
    import dopt.core : evaluate;

    auto a = float32([5], [4.0f, 2.0f, 6.0f, 1.0f, 2.0f]).argmin(0);

    auto b = float32([2, 3], [
        5.0f, 1.0f, 3.0f,
        6.0f, 7.0f, 2.0f
    ]).argmin(1);

    import std.stdio;
    assert(a.evaluate().as!int == [3]);
    assert(b.evaluate().as!int == [1, 2]);
}

/**
    Computes a max reduction along the specified axes.

    Params:
        op = The input to the reduction.
        axes = The axes the reduction should be performed along.

    Returns:
        The resulting operation.
*/
Operation maxElement(Operation op, size_t[] axes = [], string mod = __MODULE__, size_t line = __LINE__)
{
    import std.variant : Variant;

    if(op.rank == 0)
    {
        return op.reshape(op.shape);
    }

    if(axes.length == 0)
    {
        axes = iota(0, op.rank).array();
    }
    
    return createOperation("maxElement", [op], ["axes": Variant(axes)], mod, line);
}