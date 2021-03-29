@inline CI(a...) = CartesianIndex(a...)
@inline δ(a,d::Int) = CI(ntuple(i -> i==a ? 1 : 0, d))
@inline δ(a,I::CartesianIndex{N}) where {N} = δ(a,N)

@inline CR(a...) = CartesianIndices(a...)
@inline inside(M::NTuple{N,Int}) where {N} = CR(ntuple(i-> 2:M[i]-1,N))
@inline inside(a::Array; reverse::Bool=false) =
        reverse ? Iterators.reverse(inside(size(a))) : inside(size(a))
@inline inside_u(N::NTuple{n,T}) where {n,T} = CR(ntuple(i->2:N[i],n-1))
function inside_u(N::NTuple{n,Int},j::Int)::CartesianIndices{n} where n
    CartesianIndices(ntuple( i-> i==j ? (3:N[i]-1) : (2:N[i]), n))
end

import Base.mapreduce
@fastmath function mapreduce(f,op,R::CartesianIndices;init=0.)
    val = init
    @inbounds @simd for I ∈ R
        val = op(val,f(I))
    end
    val
end
L₂(a::Array{Float64}) = mapreduce(I->@inbounds(abs2(a[I])),+,inside(a))

macro inside(ex)
    @assert ex.head==:(=)
    a,I = Meta.parse.(split(string(ex.args[1]),union("[","]")))
    return quote
        @inbounds @simd for $I ∈ inside($a)
            $ex
        end
    end |> esc
end

function median(a,b,c)
    if a>b
        b>=c && return b
        a>c && return c
    else
        b<=c && return b
        a<c && return c
    end
    return a
end

"""
    apply(f, N...)

Apply a vector function f(i,x) to the faces of a uniform staggered grid.
"""
function apply(f,N...)
    # TODO be more clever with the type
    c = Array{Float64}(undef,N...)
    apply!(f,c)
    return c
end
function apply!(f,c)
    N = size(c)
    for b ∈ 1:N[end]
        @simd for I ∈ CR(N[1:end-1])
            x = collect(Float16, I.I) # location at cell center
            x[b] -= 0.5               # location at face
            @inbounds c[I,b] = f(b,x) # apply function to location
        end
    end
end

"""
    slice(N,s,dims) -> R

Return `CartesianIndices` slicing through an array of size `N`.
"""
function slice(N::NTuple{n,Int},s::Int,dims::Int,low::Int=1)::CartesianIndices{n} where n
    CartesianIndices(ntuple( i-> i==dims ? (s:s) : (low:N[i]), n))
end

function BC!(a::Array{T,m},A,f=1) where {T,m}
    n = m-1
    N = ntuple(i -> size(a,i), n)
    for j ∈ 1:n, i ∈ 1:n
        if i==j # Inline direction
            for s ∈ (1,2,N[j]); @simd for I ∈ slice(N,s,j)
                a[I,i] = f*A[i] # Dirichlet
            end; end
        else    # Perpendicular directions
            @simd for I ∈ slice(N,1,j)
                a[I,i] = a[I+δ(j,I),i] # Neumann
            end
            @simd for I ∈ slice(N,N[j],j)
                a[I,i] = a[I-δ(j,I),i] # Neumann
            end
        end
    end
end
function BC!(a::Array{T,n}) where {T,n}
    N = size(a)
    for j ∈ 1:n
        @simd for I ∈ slice(N,1,j)
            a[I] = a[I+δ(j,I)] # Neumann
        end
        @simd for I ∈ slice(N,N[j],j)
            a[I] = a[I-δ(j,I)] # Neumann
        end
    end
end

# function BC!(a::Array{T,4},A,f=1) where T
#     for k∈1:size(a,3), j∈1:size(a,2)
#         a[1,j,k,1] = a[2,j,k,1] = a[size(a,1),j,k,1] = f*A[1]
#         a[1,j,k,2] = a[2,j,k,2]; a[size(a,1),j,k,2] = a[size(a,1)-1,j,k,2]
#         a[1,j,k,3] = a[2,j,k,3]; a[size(a,1),j,k,3] = a[size(a,1)-1,j,k,3]
#     end
#     for k∈1:size(a,3), i∈1:size(a,1)
#         a[i,1,k,2] = a[i,2,k,2] = a[i,size(a,2),k,2] = f*A[2]
#         a[i,1,k,1] = a[i,2,k,1]; a[i,size(a,2),k,1] = a[i,size(a,2)-1,k,1]
#         a[i,1,k,3] = a[i,2,k,3]; a[i,size(a,2),k,3] = a[i,size(a,2)-1,k,3]
#     end
#     for j∈1:size(a,2), i∈1:size(a,1)
#         a[i,j,1,3] = a[i,j,2,3] = a[i,j,size(a,3),3] = f*A[3]
#         a[i,j,1,1] = a[i,j,2,1]; a[i,j,size(a,3),1] = a[i,j,size(a,3)-1,1]
#         a[i,j,1,2] = a[i,j,2,2]; a[i,j,size(a,3),2] = a[i,j,size(a,3)-1,2]
#     end
# end
# function BC!(a::Array{T,3},A,f=1) where T
#     for j∈1:size(a,2)
#         a[1,j,1] = a[2,j,1] = a[size(a,1),j,1] = f*A[1]
#         a[1,j,2] = a[2,j,2]; a[size(a,1),j,2] = a[size(a,1)-1,j,2]
#     end
#     for i∈1:size(a,1)
#         a[i,1,2] = a[i,2,2] = a[i,size(a,2),2] = f*A[2]
#         a[i,1,1] = a[i,2,1]; a[i,size(a,2),1] = a[i,size(a,2)-1,1]
#     end
# end
# function BC!(a::Array{T,3}) where T
#     for k∈1:size(a,3), j∈1:size(a,2)
#         a[1,j,k] = a[2,j,k]; a[size(a,1),j,k] = a[size(a,1)-1,j,k]
#     end
#     for k∈1:size(a,3), i∈1:size(a,1)
#         a[i,1,k] = a[i,2,k]; a[i,size(a,2),k] = a[i,size(a,2)-1,k]
#     end
#     for j∈1:size(a,2), i∈1:size(a,1)
#         a[i,j,1] = a[i,j,2]; a[i,j,size(a,3)] = a[i,j,size(a,3)-1]
#     end
# end
# function BC!(a::Array{T,2}) where T
#     for j∈1:size(a,2)
#         a[1,j] = a[2,j]; a[size(a,1),j] = a[size(a,1)-1,j]
#     end
#     for i∈1:size(a,1)
#         a[i,1] = a[i,2]; a[i,size(a,2)] = a[i,size(a,2)-1]
#     end
# end
