module dopt.core.ops;

import std.array;
import std.exception;
import std.variant;

import dopt.core;

public
{
    import dopt.core.ops.math;
}

alias Verifier = bool delegate(const Operation);
alias Judge = TensorType delegate(const(Operation));

/**
Contains methods to perform procedures specific to the type of an operation
*/
struct OpDef
{
    /**
    A verifier is used to ensure that an Operation object correctly constructed.
    */
    Verifier verifier;

    /**
    A judge produces a TensorType object that specifies the type of the result of an operation of this type.
    */
    Judge judge;
}

/**
A node in the expression graph
*/
class Operation
{
    public
    {
        /**
        Returns a string identifying the type of this operation. This is the same string used when registering the
        operation with the registerOperation method.
        */
        @property string opType() const
        {
            return mOpType;
        }

        /**
        Returns a TensorType object that specifies the type of tensor obtained by evaluating this operation.
        */
        @property const(TensorType) outputType() const
        {
            return mOutputType;
        }

        /**
        Returns a list of operands for this operation.
        */
        @property const(Operation)[] deps() const
        {
            return mDeps;
        }

        /**
        Returns an associative array that maps strings to operation specific attributes.
        */
        @property const(Variant[string]) attributes() const
        {
            return mAttributes;
        }
    }

    private
    {
        string mOpType;
        string mModule;
        size_t mLine;
        const(Operation)[] mDeps;
        const(Variant[string]) mAttributes;
        const(TensorType) mOutputType;

        this(string opType, const(Operation)[] deps, const(Variant[string]) attribs, string mod, size_t line)
        {
            mOpType = opType;
            mDeps = deps.array;
            mAttributes = attribs.dup;
            mModule = mod;
            mLine = line;

            mOutputType = makeJudgement(this);
        }
    }
}

/**
Registers an operation definition with the given identifier.
*/
void registerOperation(string name, OpDef def)
{
    enforce((name in mOpDefs) is null, "There is already an operation registered with the name '" ~ name ~ "'");

    mOpDefs[name] = def;
}

/**
Returns a list of identifiers for operations that have been registered so far.
*/
string[] listAllOperations()
{
    return mOpDefs.keys.dup;
}

/**
Creates an operation of the given type, with the given dependencies and attributes.
*/
Operation createOperation(string opType, const(Operation)[] deps = [], const(Variant[string]) attribs = null,
    string mod = __MODULE__, size_t line = __LINE__)
{
    enforce(opType in mOpDefs,
        "Cannot create operation because there is no operation definition registered with the name '" ~ opType ~ "'");

    auto op = new Operation(opType, deps, attribs, mod, line);

    enforce(mOpDefs[opType].verifier(op), "Operation failed verification");

    return op;
}

private
{
    OpDef[string] mOpDefs;

    TensorType makeJudgement(const(Operation) op)
    {
        auto def = op.opType in mOpDefs;

        enforce(def !is null, "Cannot make judgement for unknown operation '" ~ op.opType() ~ "'");

        return def.judge(op);
    }
}