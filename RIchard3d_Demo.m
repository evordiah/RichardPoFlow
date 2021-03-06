function [] = RIchard3d_Demo()
% Richard3d solver demo funtion, Uisng Pircards iteration on Dirichlet and 
% homogeneous Neumann Boundary condition. The permeability field is
% heterogeneous.
%
% Input parameters:
%
% Output parameters:
%
% Examples:
%
% See also: 
% Author:   Wei Xing
% History:  26/07/2017  Document and modification
% 
% Log:
% Version1.0 initial filed

%% Setup
% Spatial setup
lengthZ=10;                 
deltaZ=1;
nZ=lengthZ/deltaZ+1;

lengthX=10;
deltaX=1;
nX=lengthX/deltaX+1;

lengthY=10;
deltaY=1;
nY=lengthY/deltaY+1;

% Temporal setup
lengthT=50;
deltaT=1;
nTime=lengthT/deltaT;

% Iteration solver setup
nMaxIteration=100;
maxIteError=1;

% Generate grid
[Z,X,Y] = ndgrid(0:deltaZ:lengthZ,0:deltaX:lengthX,0:deltaY:lengthY);


%% Define Boundary conditions
iBC=2;
switch iBC 
    case 1 % Unstable!!  
        % Option 1.  Dirichlet boundary conditions on all faces.
%        Make nodeIndex matrix. It indicate the sequence nodes are accessed and the type of node.  
        nodeIndex=zeros(nZ,nX,nY);
        nodeIndex(2:end-1,2:end-1,2:end-1)=reshape(uint32(1:(nZ-2)*(nX-2)*(nY-2)), (nZ-2),(nX-2),(nY-2));  
%       nodeIndex indicates the node type. 
%           -nodeIndex= 0:              node on Dirichlet boundary
%           -nodeIndex= integer:        free node
%           -nodeIndex= - integer:      node on Neumann boundary
%           -code only accepts homogeneous Neumann BC

        nodeInFieldIndex=find(nodeIndex);
    
        %%% 
        %initial state
%         H_init=zeros(nZ,nX,nY);
%         H_init(2:end-1,2:end-1,2:end-1)=-61.5;
        
        H_init=ones(nZ,nX,nY)*-21.5;
    
        %BC values
        bcFront=ones(nZ,nX)*-20.7;
        bcBack =ones(nZ,nX)*-21.7;
        
        bcLeft=ones(nZ,nY)*-20.7;
        bcRight=ones(nZ,nY)*-21.7;
        
        bcTop   =ones(nX,nY)*-20.7;
        bcBottom=ones(nX,nY)*-21.7;
    
  
        H_init(1:end,1,1:end)   =bcLeft;
        H_init(1:end,end,1:end) =bcRight;
        
        H_init(1:end,1:end,1)   =bcFront;
        H_init(1:end,1:end,end) =bcBack;
        
        H_init(1,1:end,1:end)   =bcTop;
        H_init(end,1:end,1:end) =bcBottom;
        
    case 2  %Recommended for Demo.
        % Option 2 Neumann BC on sides and Dirichlet conditions on Top and bottom
        nodeIndex=zeros(nZ,nX,nY);
        nodeIndex(2:end-1,1:end,1:end)=reshape(uint32(1:(nZ-2)*nX*nY), (nZ-2),nX,nY);  
%       nodeIndex indicates the node type. 
%           -nodeIndex= 0:              node on Dirichlet boundary
%           -nodeIndex= integer:        free node
%           -nodeIndex= minus integer:  node on Neumann boundary
%           -code only accepts homogeneous Neumann BC

        nodeInFieldIndex=find(nodeIndex);

        nodeIndex(:,:,1)=-nodeIndex(:,:,1);
        nodeIndex(:,:,end)=-nodeIndex(:,:,end);

        nodeIndex(:,1,2:end-1)=-nodeIndex(:,1,2:end-1);
        nodeIndex(:,end,2:end-1)=-nodeIndex(:,end,2:end-1);
        
        % Define initial condition
        H_init=ones(nZ,nX,nY)*-61.5;
        H_init(1,:,:)=ones(nX,nY)*-20.7;
        H_init(end,:,:)=ones(nX,nY)*-61.5;
        
end

    
%% Initilize mesh 
mesh.deltaZ=deltaZ;
mesh.nZ=nZ;
mesh.deltaX=deltaX;
mesh.nX=nX;
mesh.deltaY=deltaY;
mesh.nY=nY;

mesh.nodeIndex=nodeIndex;
mesh.nNode=length(nodeIndex(nodeIndex~=0));
% mesh.nodeInFieldIndex=nodeInFieldIndex;


%% Define for C and K non-linear function
theata_s=0.287;
theata_r=0.075;
alpha=1.611e6;
beta=3.96;

rho=1.175e6;
r=4.74;
% kFromhKs @(h) Ks.*rho./(rho+abs(h).^r);
% K = @(h) Ks.*rho./(rho+abs(h).^r);
K = @(h,Ks) Ks.*rho./(rho+abs(h).^r);

theata    = @(h)  alpha.*(theata_s-theata_r)/(alpha+abs(h).^beta)+theata_r;
theataDif = @(h) -alpha.*(theata_s-theata_r).*-1.*(alpha+abs(h).^beta).^(-2).*abs(h).^(beta-1);


%% Define Permeability field input 
iMethod=2;
switch iMethod
    case 1      %directly give mean and covariance to X. Not recommended for realistic case.
        
        scale=0.0094;        % overall magnitude of the permeability field. decide the changing speed.
        lengthScale=100;      %larger number means less stochastic (more correlation as one zooms in the 
                            %field) field. Thus gives smoother result.
        nKl=100;             %number of KL baisi/cofficients
        [nAllNode,nDimension]=size([Z(:),X(:),Y(:)]);
        % nKl=nAllNode;

        %calculate distance matrix
        distance = pdist([Z(:),X(:),Y(:)]);
        distanceMatrix = squareform(distance);

        %calculate covariance matrix
        covMatrix=exp(-distanceMatrix./lengthScale);    

        % KL decomposition on covariance matrix via SVD/eigen decomposition
        [klBasis,klEigenValue,~] = svds(covMatrix,nKl); 


        % Generate independent normal samples 
        seed=100;
        rng(seed);
        sample= randn(nKl,1);

        %make multivariate Gaussian distributions with samples. zero mean.
        %Covariance specified though KL basis.
        % Ks=klBasis*sqrt(klEigenValue)*sample;
        % Ks=reshape(Ks,nY,nX);
        % a log (multi) normal permeability field
        % Ks=exp(Ks);

        Ks =exp(klBasis*sqrt(klEigenValue)*sample).*scale;

        Ks=reshape(Ks,nZ,nX,nY);

        %Plot 
        bubbleScale=100;
        scatter3(X(:),Y(:),Z(:),Ks(:)*bubbleScale,Ks(:)*bubbleScale)

        
    case 2   %Derive mean and covariance of X by given Y. recommended for realistic case.
        
        lengthcale=4;
        muY=0.0094; 
        DeviationRatio=0.4;     %set DeviationRatio=10 to see dramatic results.
        nSample=1;
        nKL=100;
        
%         Ks=permeaField([Z(:),X(:),Y(:)],lengthcale,muY,DeviationRatio,nSample);
        Ks=permeaFieldApprox([Z(:),X(:),Y(:)],lengthcale,muY,DeviationRatio,nSample,nKL);
        Ks=reshape(Ks,nZ,nX,nY,nSample);   
        
        %Plot 
        bubbleScale=100;
        scatter3(X(:),Y(:),Z(:),Ks(:)*bubbleScale,Ks(:)*bubbleScale)
        
    case 3 %interpolation for high resolution permeability. used for fine grid where permeability generation may fail
        % WARMING: case 3 is wrong and not working now!!!
        
        lengthcale=4;
        muY=0.0094; 
        DeviationRatio=0.4;     %set DeviationRatio=10 to see dramatic results.
        nSample=1;
        nKL=10;
        
        [coarseZ,coarseX,coarseY] = ndgrid(0:deltaZ*2:lengthZ,0:deltaX*2:lengthX,0:deltaY*2:lengthY); %have to be just fine times
        
%         Ks=permeaField([Z(:),X(:),Y(:)],lengthcale,muY,DeviationRatio,nSample);
        Ks=permeaFieldApproxUpscale([coarseZ(:),coarseX(:),coarseY(:)],[Z(:),X(:),Y(:)],lengthcale,muY,DeviationRatio,nSample,nKL);
%         Ks=reshape(Ks,nZ,nX,nY,nSample);  
        Ks=reshape(Ks,nZ,nX,nY,[]); 
%         Ks=reshape(Ks,nZ,nX,nY);
        
        bubbleScale=100;
        scatter3(X(:),Y(:),Z(:),Ks(:)*bubbleScale,Ks(:)*bubbleScale)
        
end


%% MAIN
mesh.H=H_init;       %impose initial condition.
mesh.Ks=Ks;

tic
[hRecord,iteration1] = Richard3dPicardSolver(mesh,nTime,deltaT,nMaxIteration,maxIteError,theataDif,K);
toc

%% Plotting 
% H=mesh.H;

figure(1)
plot(iteration1)
title(sprintf('Iteration at each time step'))

% end time pressure
% figure(2)
% scatter3(X(:),Y(:),Z(:),abs(H(:)),abs(H(:)))
% title('end time pressure')

% figure(1)
% p = patch(isosurface(H,-60));
% isonormals(H,p)
% p.FaceColor = 'red';
% p.EdgeColor = 'none';
% daspect([1 1 1])
% view(3); 
% axis([nX,nY,nZ ])

% preasure head front surface propogation
figure(3)
for t=1:nTime
    clf
    Ht=abs(hRecord(:,:,:,t));
    p=patch(isosurface(Ht,40));
    p.FaceColor = 'red';
    p.EdgeColor = 'none';
    
    p=patch(isosurface(Ht,50));
    p.FaceColor = 'yellow';
    p.EdgeColor = 'none';  

    p=patch(isosurface(Ht,60));
    p.FaceColor = 'blue';
    p.EdgeColor = 'none';  
    
    view(-60,40)
    title(sprintf('pressure front propogation. t=%i',t))
    axis([1,nX,1,nY,1,nZ])
    
    camlight 
    lighting gouraud

    
    drawnow
    frame(t)=getframe;
end

xslice = [nX]; 
yslice = [nY]; 
zslice = [0:nZ/2:nZ];
figure(3)
slice(mesh.H,nX,1:5:nZ,1)


% preasure head propogation in square volume
figure(4)
for t=1:nTime
%     surf(X(:,:,sliceY),Z(:,:,sliceY),TheataRecord(:,:,sliceY,t))
%     shading interp;
%     slice(TheataRecord(:,:,:,t),nX,nY,0:nZ/4:nZ)
    slice(hRecord(:,:,:,t),nX-3,1:5:nZ,1)
    view(-60,40)
    title(sprintf('pressure. t=%i',t))
    drawnow
    frame(t)=getframe;
end

% preasure head propogation in sphere volume
figure(5)
for t=1:4:nTime
    hVector=(hRecord(:,:,:,t)+100)*10;    
%     scatter3(X(:),Y(:),Z(:),(hVector(:)),(Ks(:)*10000),'fill')
    scatter3(X(:),Y(:),Z(:),(hVector(:)),(hVector(:)),'fill')
%     shading interp;
    title(sprintf('pressure. t=%i',t))
    drawnow
    frame(t)=getframe;
    
end




