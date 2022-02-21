# This file is a part of Julia. License is MIT: https://julialang.org/license

abstract type MethodTableView; end

"""
    struct InternalMethodTable <: MethodTableView

A struct representing the state of the internal method table at a
particular world age.
"""
struct InternalMethodTable <: MethodTableView
    world::UInt
end

"""
    struct OverlayMethodTable <: MethodTableView

Overlays the internal method table such that specific queries can be redirected to an
external table, e.g., to override existing method.
"""
struct OverlayMethodTable <: MethodTableView
    world::UInt
    mt::Core.MethodTable
end

"""
    findall(sig::Type, view::MethodTableView; limit=typemax(Int))

Find all methods in the given method table `view` that are applicable to the
given signature `sig`. If no applicable methods are found, an empty result is
returned. If the number of applicable methods exceeded the specified limit,
`missing` is returned.
"""
function findall(@nospecialize(sig::Type), table::InternalMethodTable; limit::Int=typemax(Int))
    _min_val = RefValue{UInt}(typemin(UInt))
    _max_val = RefValue{UInt}(typemax(UInt))
    _ambig = RefValue{Int32}(0)
    ms = _methods_by_ftype(sig, nothing, limit, table.world, false, _min_val, _max_val, _ambig)
    if ms === false
        return missing
    end
    return MethodLookupResult(ms::Vector{Any}, WorldRange(_min_val[], _max_val[]), _ambig[] != 0)
end

function findall(@nospecialize(sig::Type), table::OverlayMethodTable; limit::Int=typemax(Int))
    _min_val = RefValue{UInt}(typemin(UInt))
    _max_val = RefValue{UInt}(typemax(UInt))
    _ambig = RefValue{Int32}(0)
    ms = _methods_by_ftype(sig, table.mt, limit, table.world, false, _min_val, _max_val, _ambig)
    if ms === false
        return missing
    elseif isempty(ms)
        # fall back to the internal method table
        _min_val[] = typemin(UInt)
        _max_val[] = typemax(UInt)
        ms = _methods_by_ftype(sig, nothing, limit, table.world, false, _min_val, _max_val, _ambig)
        if ms === false
            return missing
        end
    end
    return MethodLookupResult(ms::Vector{Any}, WorldRange(_min_val[], _max_val[]), _ambig[] != 0)
end

"""
    findsup(sig::Type, view::MethodTableView)::Union{Tuple{MethodMatch, WorldRange}, Nothing}

Find the (unique) method `m` such that `sig <: m.sig`, while being more
specific than any other method with the same property. In other words, find
the method which is the least upper bound (supremum) under the specificity/subtype
relation of the queried `signature`. If `sig` is concrete, this is equivalent to
asking for the method that will be called given arguments whose types match the
given signature. This query is also used to implement `invoke`.

Such a method `m` need not exist. It is possible that no method is an
upper bound of `sig`, or it is possible that among the upper bounds, there
is no least element. In both cases `nothing` is returned.
"""
function findsup(@nospecialize(sig::Type), table::InternalMethodTable)
    min_valid = RefValue{UInt}(typemin(UInt))
    max_valid = RefValue{UInt}(typemax(UInt))
    result = ccall(:jl_gf_invoke_lookup_worlds, Any, (Any, UInt, Ptr{Csize_t}, Ptr{Csize_t}),
                   sig, table.world, min_valid, max_valid)::Union{MethodMatch, Nothing}
    result === nothing && return nothing
    (result.method, WorldRange(min_valid[], max_valid[]))
end

isoverlayed(::MethodTableView)     = error("unsatisfied MethodTableView interface")
isoverlayed(::InternalMethodTable) = false
isoverlayed(::OverlayMethodTable)  = true
