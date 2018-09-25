using LogDensityProblems
using LogDensityProblems: Value, ValueGradient
using Test

using Distributions
import ForwardDiff
using Parameters: @unpack
using DocStringExtensions: SIGNATURES
using TransformVariables

"""
    a ≅ b

Compare fields and types (strictly), for unit testing.
"""
≅(::Any, ::Any) = false
≅(a::Value{T}, b::Value{T}) where {T} = a.value == b.value
≅(a::ValueGradient{T,V}, b::ValueGradient{T,V}) where {T,V} =
    a.value == b.value && (a.value == -Inf || a.gradient == b.gradient)

@testset "Value constructor" begin
    @test eltype(Value(1.0)) ≡ Float64
    @test_throws ArgumentError Value(Inf)
    @test_throws ArgumentError Value(NaN)
    @test isfinite(Value(1.0))
    @test !isinf(Value(1.0))
    @test !isfinite(Value(-Inf))
    @test isinf(Value(-Inf))
    @test_throws MethodError Value(:something)
end

@testset "ValueGradient constructor" begin
    @test eltype(ValueGradient(1.0, [2.0])) ≡ Float64
    @test_throws ArgumentError ValueGradient(Inf, [1.0])
    @test_throws ArgumentError ValueGradient(2.0, [Inf])
    @test !isfinite(ValueGradient(-Inf, [12.0]))
    @test isinf(ValueGradient(-Inf, [12.0]))
    @test isfinite(ValueGradient(1.0, [12.0]))
    @test !isinf(ValueGradient(1.0, [12.0]))
    @test ValueGradient(1, [2.0]) ≅ ValueGradient(1.0, [2.0]) # conversion
end

@testset "transformed Bayesian problem" begin
    t = as((y = asℝ₊, ))
    d = LogNormal(1.0, 2.0)
    logposterior = ((x, ), ) -> logpdf(d, x)

    # a Bayesian problem
    p = TransformedLogDensity(t, logposterior)
    @test dimension(p) == 1
    @test p.transformation ≡ t
    @test p.logposterior ≡ logposterior

    # gradient of a problem
    ∇p = ForwardDiffLogDensity(p)
    @test dimension(∇p) == 1
    @test ∇p.transformation ≡ t
    @test ∇p.logposterior ≡ logposterior

    for _ in 1:100
        x = randn(dimension(t))
        θ, lj = transform_and_logjac(t, x)
        px = logdensity(Value, p, x)
        @test logpdf(d, θ.y) + lj ≈ (px::Value).value
        @test (logdensity(Value, ∇p, x)::Value).value ≈ px.value
        ∇px = logdensity(ValueGradient, ∇p, x)
        @test (∇px::ValueGradient).value ≈ px.value
        @test ∇px.gradient ≈ [ForwardDiff.derivative(x -> logpdf(d, exp(x)) + x, x[1])]
    end
end

@testset "-∞ log densities" begin
    t = as(Array, 2)
    validx = x -> all(x .> 0)
    p = TransformedLogDensity(t, x -> validx(x) ?  sum(abs2, x)/2 : -Inf)
    ∇p = ForwardDiffLogDensity(p)

    @test dimension(p) == dimension(∇p) == dimension(t)
    @test p.transformation ≡ ∇p.transformation ≡ t

    for _ in 1:100
        x = randn(dimension(t))
        px = logdensity(Value, ∇p, x)
        ∇px = logdensity(ValueGradient, ∇p, x)
        @test px isa Value
        @test ∇px isa ValueGradient
        @test px.value ≈ ∇px.value
        if validx(x)
            @test isfinite(px)
            @test isfinite(∇px)
            @test ∇px.value ≈ sum(abs2, x)/2
            @test ∇px.gradient ≈ x
        else
            @test isinf(px)
            @test isinf(∇px)
        end
    end
end

@testset "benchmark ForwardDiff problems" begin
    ℓ = TransformedLogDensity(as(Array, 20), x -> -sum(abs2, x))
    b = LogDensityProblems.benchmark_ForwardDiff_chunks(ℓ)
    @test b isa Vector{Pair{Int,Float64}}
    @test length(b) ≤ 20
end

@testset "stresstest" begin
    f = x -> all(x .< 0) ? NaN : -sum(abs2, x)
    ℓ = TransformedLogDensity(as(Array, 2), f)
    failures = LogDensityProblems.stresstest(ℓ; N = 1000)
    @test 230 ≤ length(failures) ≤ 270
    @test all(x -> all(x .< 0), failures)
end

# also make the docs
include("../docs/make.jl")
