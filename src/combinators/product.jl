export ProductMeasure

using MappedArrays
using Base: @propagate_inbounds
import Base
using FillArrays

abstract type AbstractProductMeasure <: AbstractMeasure end

struct ProductMeasure{F,S,I} <: AbstractProductMeasure
    f::Kernel{F,S}
    pars::I
end

# TODO: Test for equality without traversal, probably by first converting to a
# canonical form
function Base.:(==)(a::ProductMeasure, b::ProductMeasure)
    all(zip(a.pars, b.pars)) do (aᵢ, bᵢ)
        a.f(aᵢ) == b.f(bᵢ)
    end
end

Base.size(μ::ProductMeasure) = size(marginals(μ))

Base.length(m::ProductMeasure{T}) where {T} = length(marginals(μ))

basemeasure(d::ProductMeasure) = productmeasure(basekernel(d.f), d.pars)

# TODO: Do we need these methods?
# basemeasure(d::ProductMeasure) = ProductMeasure(basemeasure ∘ d.f, d.pars)
# basemeasure(d::ProductMeasure{typeof(identity)}) = ProductMeasure(identity, map(basemeasure, d.pars))
# basemeasure(d::ProductMeasure{typeof(identity), <:FillArrays.Fill}) = ProductMeasure(identity, map(basemeasure, d.pars))

export marginals

function marginals(d::ProductMeasure{F,S,I}) where {F,S,I}
    _marginals(d, isiterable(I))
end

function _marginals(d::ProductMeasure, ::Iterable)
    return (d.f(i) for i in d.pars)
end

function _marginals(d::ProductMeasure{F,S,I}, ::NonIterable) where {F,S,I}
    error("Type $I is not iterable. Add an `iterate` or `marginals` method to fix.")
end

testvalue(d::ProductMeasure) = map(testvalue, marginals(d))

function Pretty.tile(μ::ProductMeasure{F,S,NamedTuple{N,T}}) where {F,S,N,T}
    result = Pretty.literal("Product(")
    result *= Pretty.pair_layout(μ.f, μ.pars; sep = ", ")
    result *= Pretty.literal(")")
end

function Base.rand(rng::AbstractRNG, ::Type{T}, d::ProductMeasure) where {T}
    _rand(rng, T, d, marginals(d))
end

function _rand(rng::AbstractRNG, ::Type{T}, d::ProductMeasure, mar) where {T}
    (rand(rng, T, m) for m in mar)
end

###############################################################################
# I <: Tuple

struct TupleProductMeasure{T} <: AbstractProductMeasure
    pars::T
end

export ⊗
⊗(μs::AbstractMeasure...) = productmeasure(μs)

marginals(d::TupleProductMeasure{T}) where {F,T<:Tuple} = d.pars

function Pretty.tile(μ::TupleProductMeasure{T}) where {F,T<:Tuple}
    mar = marginals(μ)
    Pretty.list_layout(Pretty.Layout[Pretty.tile.(mar)...]; sep = " ⊗ ")
end

@inline function logdensity(d::TupleProductMeasure, x::Tuple) where {T<:Tuple}
    mapreduce(logdensity, +, d.pars, x)
end

function Base.rand(rng::AbstractRNG, ::Type{T}, d::TupleProductMeasure) where {T}
    rand.(d.pars)
end

###############################################################################
# I <: AbstractArray

marginals(d::ProductMeasure{F,S,A}) where {F,S,A<:AbstractArray} = mappedarray(d.f, d.pars)

function marginals(d::ProductMeasure{<:Returns,S,A}) where {F,S,A<:AbstractArray}
    Fill(d.f.f.value, size(d.pars))
    # mappedarray(d.f.f, d.pars)
end

function logdensity(d::ProductMeasure, x)
    mapreduce(logdensity, +, marginals(d), x)
end

function logdensity(d::ProductMeasure{<:Returns}, x)
    sum(x -> logdensity(d.f.f.value, x), x)
end

function Pretty.tile(d::ProductMeasure{F,S,A}) where {F,S,A}
    result = Pretty.literal("For(")
    result *= Pretty.pair_layout(Pretty.tile(d.f), Pretty.tile(d.pars); sep = ", ")
    result *= Pretty.literal(")")
end

###############################################################################
# I <: CartesianIndices

function Pretty.tile(d::ProductMeasure{F,S,I}) where {F,S,I<:CartesianIndices}
    result = Pretty.literal("For(")
    result *= Pretty.pair_layout(Pretty.tile(d.f), Pretty.tile(size(d.pars)); sep = ", ")
    result *= Pretty.literal(")")
end

# function Base.rand(rng::AbstractRNG, ::Type{T}, d::ProductMeasure{F,S,I}) where {T,F,I<:CartesianIndices}

# end

###############################################################################
# I <: Base.Generator

export rand!
using Random: rand!, GLOBAL_RNG, AbstractRNG

function logdensity(d::ProductMeasure{F,S,I}, x) where {F,S,I<:Base.Generator}
    sum((logdensity(dj, xj) for (dj, xj) in zip(marginals(d), x)))
end

@propagate_inbounds function Random.rand!(
    rng::AbstractRNG,
    d::ProductMeasure,
    x::AbstractArray
)
    # TODO: Generalize this
    T = Float64
    for (j, m) in zip(eachindex(x), marginals(d))
        @inbounds x[j] = rand(rng, T, m)
    end
    return x
end

export rand!
using Random: rand!, GLOBAL_RNG, AbstractRNG

function _rand(rng::AbstractRNG, ::Type{T}, d::ProductMeasure, mar::AbstractArray) where {T}
    elT = typeof(rand(rng, T, first(mar)))

    sz = size(mar)
    x = Array{elT,length(sz)}(undef, sz)
    rand!(rng, d, x)
end

# TODO: 
# function Base.rand(rng::AbstractRNG, d::ProductMeasure)
#     return rand(rng, sampletype(d), d)
# end

# function Base.rand(T::Type, d::ProductMeasure)
#     return rand(Random.GLOBAL_RNG, T, d)
# end

# function Base.rand(d::ProductMeasure)
#     T = sampletype(d)
#     return rand(Random.GLOBAL_RNG, T, d)
# end

function sampletype(d::ProductMeasure{A}) where {T,N,A<:AbstractArray{T,N}}
    S = @inbounds sampletype(marginals(d)[1])
    Array{S,N}
end

function sampletype(d::ProductMeasure{<:Tuple})
    Tuple{sampletype.(marginals(d))...}
end

# function logdensity(μ::ProductMeasure{Aμ}, x::Ax) where {Aμ <: MappedArray, Ax <: AbstractArray}
#     μ.data
# end

function ConstructionBase.constructorof(::Type{P}) where {F,S,I,P<:ProductMeasure{F,S,I}}
    p -> productmeasure(d.f, p)
end

# function Accessors.set(d::ProductMeasure{N}, ::typeof(params), p) where {N}
#     setproperties(d, NamedTuple{N}(p...))
# end

# function Accessors.set(d::ProductMeasure{F,T}, ::typeof(params), p::Tuple) where {F, T<:Tuple}
#     set.(marginals(d), params, p)
# end

# function logdensity(μ::ProductMeasure, ν::ProductMeasure, x)
#     sum(zip(marginals(μ), marginals(ν), x)) do μ_ν_x
#         logdensity(μ_ν_x...)
#     end
# end

function kernelfactor(μ::ProductMeasure{F,S,<:Fill}) where {F,S}
    k = kernel(first(marginals(μ)))
    (p -> k.f(p)^size(μ), k.ops)
end

function kernelfactor(μ::ProductMeasure{F,S,A}) where {F,S,A<:AbstractArray}
    (p -> set.(marginals(μ), params, p), μ.pars)
end
