function [] = Richard1dMlPodUQ_Proto1()
% UQ for Richars equation with random input using mchaine learning & POD
%
% Richars equation 1D pod solver testing file.
% The function focus on fix Dirichlet BC.
% This function serves as a Demo for all Richard solver developed in this
% project.
% 
% Proto1: Created form Richard1dPodUQ_Proto3() & Richard1dMlUq_Proto1().
%         use clissification and local-global POD. No learning yet.
%
% Input parameters:
%
% Output parameters:
%
% See also: 
%
% Author:   Wei Xing
% History:  15/06/2017  file created
%
clear
close all
%% Solver Setup
% Spatial setup
lengthZ=100;
deltaZ=0.1;
nZ=lengthZ/deltaZ+1;

% Temporal setup
lengthT=200;
deltaT=1;
nTime=lengthT/deltaT;
% tStep=1:deltaT:lengthTime;


%Solver iteration setup
nMaxIteration=50;
maxIteError=1;

% update mesh structure
mesh.lengthZ=lengthZ;
mesh.deltaZ=deltaZ;
mesh.nZ=nZ;

%% initial conditions and boundary value (DBC)
h_init=ones(nZ,1)*-61.5; %value for all initial points
h_init(1,1)=-20.7;       %value for top DBC
h_init(end,1)=-61.5;     %value for bottom DBC
mesh.H=h_init;

mesh.dbcFlag=zeros(nZ,1);     %specify DBC location
mesh.dbcFlag(1)=1;
mesh.dbcFlag(end)=1;

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
        
%% Define and Decompose the permeability input field II
lengthScale=lengthZ*0.2; %larger number means less stochastic (more correlation as one zooms in the 
nKl=30;
nSample=20;

% KsMean=0.0094;
% KsVar= (KsMean*0.3)^2;

GaussianMean= log(0.0014);
GaussianVar = (GaussianMean*0.4)^2;       


[Z] = ndgrid(0:deltaZ:lengthZ);
%calculate distance matrix
distance = pdist(Z);
distanceMatrix = squareform(distance);

covMatrix=exp(-distanceMatrix./lengthScale);    %calculate correlation matrix 
covMatrix=GaussianVar*covMatrix;                %calculate covariance  matrix 

[klBasis,klEigenValue,~] = svds(covMatrix,nKl);  % KL decomposition on covariance matrix via SVD/eigen decomposition

% Make permeability field
% sample= randn( size(klBasis,2),1);               %Sampling from a normal distribution
sample= randn(nKl,nSample);                              %Sampling from a normal distribution
sample= lhsdesign(nSample,nKl)';                         %Sampling using latin hypercube

% sample(1:1,:)=0.5*ones(nSample,1);

Ks = (klBasis*sqrt(klEigenValue)*sample)+GaussianMean;  %Multivariate Gaussian
Ks = exp(Ks);                                          


%% FOM on K
% define non-linear term
h=waitbar(0,'FOM on Ks on progress');
for i=1:nSample
%     K = @(h) Ks(:,i).*rho./(rho+abs(h).^r);  %!CALL this function every time uisng new permeability field Ks
    mesh.Ks=Ks(:,i);
    tic
    [H,iteration1] = Richard1dPicardSolver(mesh,nTime,deltaT,nMaxIteration,maxIteError,theataDif,K);
    
    tCost1(i,1)=toc;  
    iTera1(i,1)=sum(iteration1);
    H_uq1(:,:,i)=H;
    
    waitbar(i/nSample)
end
close(h)

%% Clustering
nCluster=3;

H_uq1Vec=reshape(H_uq1,[],nSample);
label = kmeans(H_uq1Vec',nCluster);

%% local basis basend on Clusters
nPod=30;

h=waitbar(0,'Initilizing local ROMs');
for i=1:nCluster 
    
    index=find(label==i);
    
    % define snapshot
    iHSnapShot=reshape(H_uq1(:,:,index),nZ,length(index)*nTime);   %decide snapshot
    
    %POD basis
%     [V_uq(:,:,i),S,~]=svds(iHSnapShot,nPod);
    [V_uq,S,~]=svds(iHSnapShot,nPod);
    
    % DEIM nonlinear function 
    nDeimK=nPod;    %number of Deim basis for k term
    nDeimC=nPod;    %number of Deim basis for c term
    
    %k
%     for t=1:size(iHSnapShot,2)
%         kRecord(:,t)=K(iHSnapShot(:,t),Ks(:,i));
%     end
    for j=1:length(index)
        for t=1:nTime
            kRecord(:,t,j)=K(H_uq1(:,t,index(j)),Ks(:,index(j)));
        end  
    end
    kRecord=reshape(kRecord,nZ,[]);   %decide snapshot
    
    
    % [Vk,~,~]=svd(kRecord,'econ');
    [Vk,~,~]=svds(kRecord,nDeimK);

    [~,~,Pk] = DEIM(Vk);
    Pk=Pk(:,1:nDeimK);
    Vk=Vk(:,1:nDeimK);
%     VdK_uq(:,:,i)=Vk*inv(Pk'*Vk);  %DEIM basis
    VdK_uq=Vk*inv(Pk'*Vk);  %DEIM basis
    
    %c
    %     disp('DEIM decomposition for c...')
    cRecord=theataDif(iHSnapShot);
    % [Vc,~,~]=svd(cRecord,'econ');
    [Vc,~,~]=svds(cRecord,nDeimC);

    [~,~,Pc] = DEIM(Vc);
    Pc=Pc(:,1:nDeimC);
    Vc=Vc(:,1:nDeimC);
%     VdC_uq(:,:,i)=Vc*inv(Pc'*Vc);  %DEIM basis
    VdC_uq=Vc*inv(Pc'*Vc);  %DEIM basis
    
    romMesh{i}=picardAxbRomInit(mesh,V_uq,VdK_uq,Pk,VdC_uq,Pc);
    V_uqRecord(:,:,i)=V_uq;
    waitbar(i/nCluster)
end
close(h)


%% Deim POD
h=waitbar(0,'Deim pod on Ks on progress');
for i=1:nSample
    % Initilize ROM
    romMesh{label(i)}.Ks=Ks(:,i);
    
%     mesh.H=H_uq1(:,2,i); % use fom to start

%     romMesh{label(i)}.Zh=V_uqRecord(:,:,label(i))'*H_uq1(:,1,i);  %use FOM to start
    romMesh{label(i)}.Zh=V_uqRecord(:,:,label(i))'*h_init;
    
    tic
    [H_pod,iteration2] = Richard1dPicardPodSolver(romMesh{label(i)},nTime,deltaT,nMaxIteration,maxIteError,theataDif,K);
    
    tCost2(i,1)=toc;
    iTera2(i,2)=sum(iteration2);
    H_uq2(:,:,i)=H_pod;
    
    waitbar(i/nSample)
end
close(h)


sum(tCost1)
sum(tCost2)

%% UQ process
mu_H_uq1 =mean(H_uq1,3);
var_H_uq1=std(H_uq1,0,3);
mid_H_uq1=median(H_uq1,3);

mu_H_uq2 =mean(H_uq2,3);
var_H_uq2=std(H_uq2,0,3);
mid_H_uq2=median(H_uq2,3);


%% show basis
% v1=reshape(V_uq(:,1,:),nZ,nSample);
% figure(1)
% plot(v1)



%% plot
nZShow=100;
zShow=1:round(nZ/nZShow):nZ;
figure(2)
for t=1:1:nTime
    figure(3)
    plot(squeeze( H_uq1(zShow,t,:)),'-')
    hold on 
    plot(squeeze( H_uq2(zShow,t,:)),'--')
    hold off
    ylim([-80,20])
    
    title(sprintf('time=%i',t))
%     legend('All KL basis','Truncation KL basis')
    drawnow
%     frame(t)=getframe;    %comment to save cpu time and memory
end


figure(3)
nZShow=100;
zShow=1:round(nZ/nZShow):nZ;
figure(2)
for t=1:1:nTime
    figure(4)
    errorbar(zShow,mu_H_uq1(zShow,t),var_H_uq1(zShow,t),'-')
    hold on
    plot(zShow,mid_H_uq1(zShow,t),'-')
    
    errorbar(zShow,mu_H_uq2(zShow,t),var_H_uq2(zShow,t),'--')
    plot(zShow,mid_H_uq2(zShow,t),'--')
    hold off
    title(sprintf('Mean Variance and Median @t=%i',t))
%     legend('All KL basis','Truncation KL basis')
    drawnow
%     frame(t)=getframe;    %comment to save cpu time and memory
end










end