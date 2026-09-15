function []=Run_xtalk_PCA_ICA_RMmov_FanLab_function(dt)
% Fan Lab: extracting voltage signals from voltage imaging movies with crosstalk from surrounding stimulation 

% key: subtract crosstalk of scatterred light from surrounding stimulation,
% click the region in between of rings and cells to estimate the scattered light bkg, 
% ideally close to the cells for better estimation but not too close to avoid subtracting signals 

% steps: first, divided the movie into sub-movies comprising single cells and performed activity-based image segmentation separately in each
% sub-movie; second, stICA on high-pass filtered movie after removing subthreshold signals: correlations often arose between subthreshold voltages and out-of-focus background, 
% but spiking was not correlated with background, and the spatial footprint associated with spiking would be the same as for true subthreshold dynamics. 
% third, The spatial filters/footprints/masks from PCA/ICA were then applied to the original movies without high-pass filtering to extract fluorescence traces.

% Linlin Fan 2025-01-24

close all; dt =1;

%% Get Stimulation protocol
path1=cd; cd([path1 '\' 'matlab wvfm'])
path2=cd; tmp=dir; cd([path2 '\' tmp(3).name])
ReadBinWaveFormsV1 %Get AO wvfm

cd(path1)
clear path1 path2 tmp

%% load mov after remove motion
DaqRate = 10000; sz=get(0,'screensize');
Info=textscan(fopen('experimental_parameters.txt'),'%s');
nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
binName='movReg.bin'; [mov nframes] = readBinMov(binName, ncol, nrow); % changed row to col after motion correction :(
% binName='Sq_camera.bin'; [mov nframes] = readBinMov(binName, nrow, ncol);
nremove = 10/dt;
mov=double(mov(:,:,nremove+1:end));% remove much more in the beginning -- why? On uprite, delete 5. Here I delete 21
nframes = size(mov,3);
RefIm=mean(mov,3);

t = (1:nframes)*dt;
[Fmasks,roimask]=apply_mask_RMmov_BkgSel_FanLab(mov);
saveas(gca,'MaskTraces_RMmov.fig');
% in case some masks are out of the movie region
Fmask2 = zeros(nframes,1);outrangecell = zeros(1);
for i = 1:length(roimask);
    if ~isnan(Fmasks(1,i));
        Fmask2 = [Fmask2, Fmasks(:,i)];
    else
        outrangecell = [0,i];
    end
end
Fmask2(:,1)=[];outrangecell(1)=[]; roimask (:,outrangecell)=[];

%% Subtract background, always the last mask - background region
if ~isempty(outrangecell)
    if outrangecell(end) ~= size(Fmasks,2)
        intensC = Fmask2(:,1:end-1);
        bkg=Fmask2(:,end);
    end
else
    intensC = Fmask2(:,1:end-1);
    bkg=Fmask2(:,end);
end
nCell = size(intensC,2);
%% subtract crosstalk of scatterred light from ring blue light activation
[out, scaleImgs] = SeeResiduals(mov, bkg, 1);
figure(2); clf
subplot(1,2,1);imshow2(scaleImgs(:,:,1), []);
subplot(1,2,2);imshow2(scaleImgs(:,:,2), []);
% get the region in between of rings and cells to estimate the scattered light
[roi2, intens2] = clicky(mov, scaleImgs(:,:,2));% click the scatter region
saveas(gca,'ScatterLightTraces_RMmov.fig');
% input('click the scattered region') 
mov2 = mov - repmat(reshape(intens2,[1,1,nframes]),[ncol,nrow,1]); % subtract background-scattered light from movie
intens = apply_clicky(roimask, mov2);
% %% subtract background, always the last mask - background region
% sbkg = smooth(bkg,3000,'sgolay');
% mov2 = mov1 - repmat(reshape(sbkg,[1,1,nframes]),[ncol,nrow,1]); % subtract background from movie
% intens = apply_clicky(roimask, mov2);
% 
% % %% remove the bad frames
% % intensA = mean(intens,2);
% % figure(1);
% % intensS = intensA - smooth(intensA, 100);
% % plot(intensS(100:end));title('pick threshold to remove frames');pause(1)
% % Rem=input('Pick thres to remove frames   ');
% % badFrames = find(intensS < Rem);
% % intens(badFrames,:) = intens(badFrames-1,:);
%% split into mask movies
figure(4);clf
MaskMov=cell(nCell);
for i=1:nCell;
    x1=roimask{i}(:,2);
    y1=roimask{i}(:,1);edge = 5;
    X1=ceil(min(x1))-edge; if X1<1;X1=1;end
    X2=floor(max(x1))+edge;if X2>ncol;X2=ncol;end
    Y1=ceil(min(y1))-edge;if Y1<1;Y1=1;end
    Y2=floor(max(y1))+edge;if Y2>nrow;Y2=nrow;end
    MaskMov{i}=mov2(X1:X2,Y1:Y2,:);
    subplot(ceil(nCell/1.9),ceil(nCell/1.9),i)
    imshow(mean(MaskMov{i},3),[]);title(i)
end

%% Run PCA and ICA on each mask movies
smoothing=100; %for high pass filter
alpha = 0.9; %Aplha is the ratio between spatial and Temporal ICA (0 = only space, 0.99 = only time):
Bin=2; % further binning for analysis

for i=1:nCell
    smallmov=MaskMov{i};
    if mod(size(smallmov,1),2);smallmov=smallmov(1:end-1,:,:);end
    if mod(size(smallmov,2),2);smallmov=smallmov(:,1:end-1,:);end
    [nrow2, ncol2, nframe2]=size(smallmov);
    tmp=reshape(smallmov,Bin,nrow2/Bin,Bin,ncol2/Bin,nframe2);%Further bin the mov for analysis
    smovB=squeeze(mean(mean(tmp,1),3));clear tmp
    smovBN=double(pblc(vm(smovB(:,:,1:end))));%remove pbleach
    
%     %Choose part of the movie to analyze
%     xtalkFrames = [400:425, 2404:2429,  (400:425)+4000,  (2404:2429)+4000, (400:425)+8000,  (2404:2429)+8000]; % AOTF delay -- 4 frames; but why DMD turning off showed delay than turning on?  
%     ToUseFrames = setdiff( 1:size(smovBN,3),xtalkFrames );
%     
    smovBN2=smovBN(:,:,1:end); % Choose here the frames if you want to analyze part of the movie before applying to all
    [nrowB, ncolB, nframe2]=size(smovBN2);
    
    %High pass filter
    movHPF = smovBN2 - imfilter(smovBN2, ones(1,1,smoothing)/smoothing, 'replicate');
    
    %Remove large fluctuations (blood flow)
    flucImg = mean(movHPF(:,:,1:end-1).*movHPF(:,:,2:end), 3);
    flucImgS = imfilter(flucImg, fspecial('gaussian', [5 5], 2), 'replicate');
    [~, idx] = sort(flucImgS(:), 'descend');
    T=round(length(idx)*0.03);
    mask = ones(size(flucImg));
    mask(idx(1:T)) = 0;
    figure(100); clf;  %set(gcf,'position',[sz(3)/20, sz(4)/4 sz(3)/4, sz(4)/2])
    subplot(1,3,1);imshow2(flucImg, []);title('Fluctuations');
    subplot(1,3,2);imshow2(flucImgS, []);title('Fluctuations, filtered');
    subplot(1,3,3);imshow(mask);title('Mask');
    saveas(gca,[num2str(i) 'flucImg.fig'])
    
    pause(2)
    movHPm = movHPF.*repmat(mask, [1 1 nframe2]);
    
    %PCA
    movVec = tovec(movHPm);
    covmat = movVec*movVec';
    [V, D] = eig(covmat);
    V = V(:,end:-1:1);
    D = diag(D);
    D = D(end:-1:1);
    u = V(:,1:20);
    Upic = toimg(u, nrowB, ncolB);
    figure(5); clf
    for j = 1:20;
        subplot(4,5,j);
        imshow2(Upic(:,:,j), [])
    end;
    saveas(gca,[num2str(i) 'PCAImg.fig'])
    
    v = movVec'*u;
    figure(6);clf
    stackplot(v)
    saveas(gca,[num2str(i) 'PCATrace.fig'])
    
    Movie=smovBN;
    vOrig = tovec(Movie - repmat(mean(Movie, 3),[1 1 size(Movie,3)]))'*u;
    
    % mixed spatio temporal ICA
    nEigUse = 15; nIcs = 10;
    uNorm = (u - repmat(mean(u),[size(u,1) 1]))./repmat(std(u),[size(u,1) 1]);
    vNorm = (v - repmat(mean(v),[size(v,1) 1]))./repmat(std(v),[size(v,1) 1]);
    [icsST, mixmat, sepmat] = sorted_ica([(1-alpha)*u(:,1:nEigUse); alpha*v(:,1:nEigUse)],nIcs);
    icsSpace = icsST(1:length(u),:);
    icsTime = icsST(end-length(v)+1:end,:);
    icsTimeOrig = vOrig(:,1:nEigUse)*sepmat';
    
    figure(7); clf; %set(gcf,'position',[sz(3)/20, sz(4)/4 sz(3)/3, sz(4)/3])
    subplot(ceil(nIcs/3),ceil(nIcs/3),1);
    imshow(mean(MaskMov{i},3),[]);title('Template')
    for j = 1:size(icsSpace,2);
        subplot(ceil(nIcs/3),ceil(nIcs/3),j+1);
        imshow2(toimg(icsSpace(:,j), nrowB, ncolB), []);
        title(j)
    end;
    suptitle(['Mask #' num2str(i)])
    saveas(gca,[num2str(i) 'ICAImg.fig'])
    
    figure(8); clf;
    stackplot(icsTime(:,1:min(30, size(icsTime,2))));
    suptitle('High pass');
    
    figure(9); clf; set(gcf,'position',[sz(3)/2.5, sz(4)/10 sz(3)/1.8, sz(4)/1.2])
    stackplot(icsTimeOrig(:,1:min(30, size(icsTimeOrig,2))));
    suptitle('Applied to Original movie')
    saveas(gca,[num2str(i) 'ICATrace.fig'])
    %pause
    Best=input('Choose best IC:   ');
    IntensHP(:,i)=icsTime(:,Best);
    IntensOrig(:,i)=icsTimeOrig(:,Best);
    ICAImgs{i}=toimg(icsSpace(:,Best), nrowB, ncolB);
    
    CellImgs{i} = mean(MaskMov{i},3);
end
save('Masks_BestIcaTrace','IntensOrig');
save('Masks_BestIcaImgs','ICAImgs','CellImgs');

figure;
for i = 1: nCell
    subplot(nCell+3,nCell*2,2*i-1);imshow(CellImgs{i},[]);
    subplot(nCell+3,nCell*2,2*i);imshow(ICAImgs{i},[]);
    subplot(nCell+3,nCell*2,i*nCell*2+1:(i+1)*nCell*2);
    plot(t/1000,IntensOrig(:,i),'r');% xlabel('Time,sec');
    ylabel('F'); axis tight;
    hold on;
end
AOtoAOTFblue = WFAO(10*nremove+1:end,1)';% remove the 2
% AOtoPiezo = WFAO(10*nremove+1:end,2)';
t_blue = (1:length(AOtoAOTFblue))/DaqRate;
subplot(nCell+3,nCell*2,(nCell+1)*2*nCell+1:(nCell+2)*nCell*2);plot(t_blue,AOtoAOTFblue);hold on;
% plot(t_blue,AOtoPiezo);xlabel('Time,sec');
xlabel('Time,sec');ylabel('488');axis tight;

Bh = load('AI Data');% 1, pitch; 2, lick; 3, ValveTrig; 4, synC
Bh2 = Bh(:,10*nremove+1:end);% remove the first 10
tdaq = (1:size(Bh2,2))/10000;

hold on; subplot(nCell+3,nCell*2,(nCell+2)*nCell*2+1:(nCell+3)*nCell*2),
plot(tdaq,-75/75*64/0.75*(Bh2(1,:)- 1.6497)/50+4,'k');hold on; % plot the actual converted speed
% Bhtmp2 = -75/75*64/0.81*( Bhtmp(1, 10*10+1:end )- 1.6497 );% remove the first 10; pitch
plot(tdaq,Bh2(4,:)/5.2+3,'color',[0.5,0.5,0.5]); hold on;
plot(tdaq,Bh2(3,:)/3.2+2,'r'); hold on;
plot(tdaq,Bh2(2,:)/5.2+1,'cyan'); hold on;
plot(tdaq,Bh2(5,:)/3.2+0,'b'); hold on;
legend({'Velocity','TrialSynC','Reward','Lick','BlueStim'})
xlabel('Time,sec');ylabel('VR');axis tight;

saveas(gca,'Fig_intens_ICA.fig');
saveas(gca,['Fig_intens_ICA.png']);

% save(['Num_smp.mat'], 'Num_smpA');% intens: bkg subtracted; intensN: rem bleach
%% plot all for show
end