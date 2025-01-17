#given grid node compute closest point to the surface
module CPmap

using NearestNeighbors
using LinearAlgebra

#computes k closest points to gridpoint

function kClosestPoints(kdtree, gridpoint::Array{Float64,1}, surfdata::Array{Float64,2}, k)
    #kdtree = KDTree(surfdata)
    idxs, dists = knn(kdtree, gridpoint, 1, true);


    idxs, dists = knn(kdtree, surfdata[:,idxs[1]], k, true);

return idxs
end


function initializeCPM!(Qtree, NBlist::Array{Int64,1}, M::Int64, Q::Array{Float64,2}, ϵ::Float64, h::Float64,
                        x_range, y_range, z_range)
    CP=1000*ones(M+1,M+1,M+1)
    N=size(Q,2)

    linIdxs=LinearIndices(CP);

    #Qtree = KDTree(Q)


    idx=Array{Int64}(undef,1)


    w = Int64(ceil(ϵ/h))
    h=x_range[2]-x_range[1]

    #updating the ϵ neighborhood of each point in Q
    pointnum=1
    for I=1:N

        q0 = Q[:, I]

        i0=max(1, Int64(floor( (q0[1]-x_range[1])/ h ))-w)
        j0=max(1, Int64(floor( (q0[2]-y_range[1])/ h ))-w)
        k0=max(1, Int64(floor( (q0[3]-z_range[1])/ h ))-w)

        i1=min( length(x_range), i0+2*w)
        j1=min( length(y_range), j0+2*w)
        k1=min( length(z_range), k0+2*w)

        #need to optimize for grid ordering
        for k=k0:k1, j=j0:j1, i=i0:i1
            if CP[i,j,k]>=1000
                pointI = [x_range[i]; y_range[j]; z_range[k]]

                idx, dist = knn(Qtree, pointI, 1, true)

                #if dist[1]<tubewidth
                    CP[i,j,k]=dist[1]
                    NBlist[pointnum]=linIdxs[i,j,k]
                    pointnum+=1
                #else

                #    CP[i,j,k]=-1
                #end
            end
        end
    end
    return CP
end

#helper function to determine variables of interpolating surface
function sortvariables(index)
    if index==1
        z=1
        x=2
        y=3
        functionof="functionofyz"
    elseif index==2
        z=2
        x=1
        y=3
        functionof="functionofxz"
    else
        z=3
        x=1
        y=2
        functionof="functionofxy"
    end
    return x,y,z,functionof
end

#create "vandermonde" matrix
function formA(points::Array{Float64,2})
    A=[points[1,1]^2 points[1,1]*points[2,1] points[2,1]^2 points[1,1] points[2,1] 1.0;
       points[1,2]^2 points[1,2]*points[2,2] points[2,2]^2 points[1,2] points[2,2] 1.0;
       points[1,3]^2 points[1,3]*points[2,3] points[2,3]^2 points[1,3] points[2,3] 1.0;
       points[1,4]^2 points[1,4]*points[2,4] points[2,4]^2 points[1,4] points[2,4] 1.0;
       points[1,5]^2 points[1,5]*points[2,5] points[2,5]^2 points[1,5] points[2,5] 1.0;
       points[1,6]^2 points[1,6]*points[2,6] points[2,6]^2 points[1,6] points[2,6] 1.0]
end

#newton iterations
function newtonsiters(x0,y0,z0,F::Function,Fx::Function,Fy::Function,Fxy::Function,Fxx::Function, Fyy::Function,xinit,yinit)


   f, fx, fy, fxx, fxy, fyy = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
   J=zeros(2,2)

   x=[xinit, yinit]
   diff=[1.0, 1.0] #J\psi([xinit, yinit])

   psi=[0.0; 0.0]
   df=0.0

   for i=1:7

       if norm(diff)<1e-8
           break
       end

       f=F(x)
       fx=Fx(x)
       fy=Fy(x)
       fxx=Fxx(x)
       fxy=Fxy(x)
       fyy=Fyy(x)

       df=f-z0

       J[1,1]=1.0+fx^2+df*fxx
       J[1,2]=fx*fy+df*fxy
       J[2,1]=fx*fy+df*fxy
       J[2,2]=1.0+fy^2+df*fyy

       psi[1] = x[1]-x0+df*fx
       psi[2] = x[2]-y0+df*fy

       diff=J\psi
       x.-=diff

   end

   x

end

#find closest point to gridpoint on interpolating surface given surfdata
function CPonSinterp(kdtree, gridpoint::Array{Float64,1}, surfdata::Array{Float64,2},testpoints)

    #if test==1
        idxsCP=kClosestPoints(kdtree, gridpoint,surfdata,testpoints)
        idxs=idxsCP[testpoints-5:end] #leave out closest point to get a better spread of 6 points
    #else
        #idxsCP=kClosestPoints(kdtree, gridpoint,surfdata,6)
        #idxs=idxsCP[:] #leave out closest point to get a better spread of 6 points
    #end
    #idxs=idxsCP[:]

    xdiff=maximum(surfdata[1,idxs])-minimum(surfdata[1,idxs])
    ydiff=maximum(surfdata[2,idxs])-minimum(surfdata[2,idxs])
    zdiff=maximum(surfdata[3,idxs])-minimum(surfdata[3,idxs])

    diffvec=[xdiff,ydiff,zdiff]
    indices=sortperm(diffvec)

#determine what variables the surface is a function of
x,y,z,functionof=sortvariables(indices[1])
samples=surfdata[z,idxs]
points=surfdata[[x,y],idxs]
A=formA(points)
next=false;
#check if invertible
if abs(det(A))!=0
    coeffs=A\samples
else
    #try different variables
    x,y,z,functionof=sortvariables(indices[2])
    samples=surfdata[z,idxs]
    points=surfdata[[x,y],idxs]

    A=formA(points)
    if abs(det(A))!=0
        coeffs=A\samples
    else
        #try different variables
        x,y,z,functionof=sortvariables(indices[3])
        samples=surfdata[z,idxs]
        points=surfdata[[x,y],idxs]

        A=formA(points)
        if abs(det(A))!=0
            coeffs=A\samples
        else
            next=true;
        end
    end
end

if next
    if testpoints<10
        CPx,CPy,CPz=CPonSinterp(kdtree,gridpoint,surfdata, testpoints+1)
    else
        CPx= surfdata[1,idxsCP[1]]
        CPy= surfdata[2,idxsCP[1]]
        CPz= surfdata[3,idxsCP[1]]
    end
else

#interpolating surface definition and the derivatives
f=(x)->coeffs[1]*x[1]^2+coeffs[2]*x[1]*x[2]+coeffs[3]*x[2]^2+coeffs[4]*x[1]+coeffs[5]*x[2]+coeffs[6]
fx=(x)->2*coeffs[1]*x[1]+coeffs[2]*x[2]+coeffs[4]
fy=(x)->2*coeffs[3]*x[2]+coeffs[2]*x[1]+coeffs[5]
fxx=(x)->2*coeffs[1]
fyy=(x)->2*coeffs[3]
fxy=(x)->coeffs[2]


if functionof=="functionofxy"
    x0=gridpoint[1]
    y0=gridpoint[2]
    z0=gridpoint[3]

    xinit=surfdata[1,idxsCP[1]]
    yinit=surfdata[2,idxsCP[1]]


    x0y0=newtonsiters(x0,y0,z0,f,fx,fy,fxy,fxx,fyy,xinit,yinit)




    CPx=x0y0[1]
    CPy=x0y0[2]
    CPz=f(x0y0)

elseif functionof=="functionofxz"
    x0=gridpoint[1]
    y0=gridpoint[3]
    z0=gridpoint[2]

    xinit=surfdata[1,idxsCP[1]]
    yinit=surfdata[3,idxsCP[1]]

    x0y0=newtonsiters(x0,y0,z0,f,fx,fy,fxy,fxx,fyy,xinit,yinit)

    CPx=x0y0[1]
    CPy=f(x0y0)
    CPz=x0y0[2]


elseif functionof=="functionofyz"
    x0=gridpoint[2]
    y0=gridpoint[3]
    z0=gridpoint[1]

    xinit=surfdata[2,idxsCP[1]]
    yinit=surfdata[3,idxsCP[1]]

    x0y0=newtonsiters(x0,y0,z0,f,fx,fy,fxy,fxx,fyy,xinit,yinit)

    CPx=f(x0y0)
    CPy=x0y0[1]
    CPz=x0y0[2]

end
end
#origdist=norm(gridpoint-[surfdata[1,idxsCP[1]], surfdata[2,idxsCP[1]], surfdata[3,idxsCP[1]]])
#newdist=norm(gridpoint-[CPx, CPy ,CPz])

t=size(idxs)

currmin=1000
#start=1;
#if test==2
#    start=2;
#end

for q=1:t[1]

    tempmin=norm([CPx, CPy ,CPz]-
            [surfdata[1,idxs[q]], surfdata[2,idxs[q]], surfdata[3,idxs[q]]])
    if tempmin<currmin
        currmin=tempmin
    end
end

#firstdist=norm(gridpoint-[surfdata[1,idxsCP[1]], surfdata[2,idxsCP[1]], surfdata[3,idxsCP[1]]])
#firstmindist=norm(gridpoint-surfdata[1,idxsCP[1]], surfdata[2,idxsCP[1]], surfdata[3,idxsCP[1]]])

othermin=norm([surfdata[1,idxsCP[1]], surfdata[2,idxsCP[1]], surfdata[3,idxsCP[1]]]-
        [surfdata[1,idxs[1]], surfdata[2,idxs[1]], surfdata[3,idxs[1]]])

errordist=norm(surfdata[:,idxsCP[1]]-[CPx, CPy ,CPz])
if errordist>currmin || errordist>othermin
    if testpoints<10
        CPx,CPy,CPz= CPonSinterp(kdtree,gridpoint,surfdata, testpoints+1)
    else
        CPx= surfdata[1,idxsCP[1]]
        CPy= surfdata[2,idxsCP[1]]
        CPz= surfdata[3,idxsCP[1]]
    end
end



return CPx,CPy,CPz#,functionof
end


function compUVW(n1,n2,n3, Q,ϵ)

    kdtree = KDTree(Q)
    dx=1/(n1-1)
    dy=1/(n2-1)
    dz=1/(n3-1)
    h=1/(n1-1)
    ∞=1000.0
    U = ∞*ones(n1,n2,n3)
    V = ∞*ones(n1,n2,n3)
    W = ∞*ones(n1,n2,n3)
    NBlist=zeros(Int64,n1*n2*n3)
    N=size(Q,2)

    M=Int64(ceil(1.0/h))

    x_range=range(0.0, stop=1.0, length=M+1)
    y_range=range(0.0, stop=1.0, length=M+1)
    z_range=range(0.0, stop=1.0, length=M+1)
    CP=CPmap.initializeCPM!(kdtree, NBlist, M, Q, ϵ, h, x_range, y_range, z_range)
    w = Int64(ceil(ϵ/h))
    h=x_range[2]-x_range[1]

    #updating the ϵ neighborhood of each point in Q
    for I=1:N

        q0 = Q[:, I]

        i0=max(1, Int64(floor( (q0[1]-x_range[1])/ h ))+1-w)
        j0=max(1, Int64(floor( (q0[2]-y_range[1])/ h ))+1-w)
        k0=max(1, Int64(floor( (q0[3]-z_range[1])/ h ))+1-w)

        i1=min( length(x_range), i0+2*w+1)
        j1=min( length(y_range), j0+2*w+1)
        k1=min( length(z_range), k0+2*w+1)
        #CPx=0;
        #CPy=0;
        #CPz=0;
        #need to optimize for grid ordering
        for k=k0:k1, j=j0:j1, i=i0:i1
            if CP[i,j,k]<ϵ && U[i,j,k]>=1000
                gridpoint=[(i-1)*dx,(j-1)*dy,(k-1)*dz]

                #try

                 CPx,CPy,CPz=CPmap.CPonSinterp(kdtree,gridpoint,Q, 7)


                    U[i,j,k]=CPx
                    V[i,j,k]=CPy
                    W[i,j,k]=CPz


            end
        end
    end



return U,V,W,CP

end



function compUVWexactSphere(n1,n2,n3,radius)

    dx=1/(n1-1)
    dy=1/(n2-1)
    dz=1/(n3-1)
    h=1/(n1-1)
    #∞=1000.0
    U = zeros(n1,n2,n3)
    V = zeros(n1,n2,n3)
    W = zeros(n1,n2,n3)


    #updating the ϵ neighborhood of each point in Q
    for I in CartesianIndices(U)


                gridpoint=[(I[1]-1)*dx,(I[2]-1)*dy,(I[3]-1)*dz]


                ##uncomment the following for exact P_Gamma for the sphere.
                r=norm(gridpoint-[.5,.5,.5])
				t=radius/r
                CPx=t*(gridpoint[1]-.5)+.5;
				CPy=t*(gridpoint[2]-.5)+.5;
				CPz=t*(gridpoint[3]-.5)+.5;


                    U[I[1],I[2],I[3]]=CPx
                    V[I[1],I[2],I[3]]=CPy
                    W[I[1],I[2],I[3]]=CPz


    end



return U,V,W

end

end
