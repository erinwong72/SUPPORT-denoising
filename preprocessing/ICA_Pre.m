% This is the Pre-processing portion of Run_PCA_ICA_RMmov_FanLab_function
% Save this as Run_PCA_ICA_RMmov_FanLab_Pre.m
%
% Inputs:
%   is_stim       - logical, whether to get stimulation protocol
%   use_ring_bkg  - logical (optional), background subtraction method:
%                   true  = circular ring-based subtraction (for crosstalk removal)
%                   false = standard corner box background subtraction (default)
%
% Outputs:
%   nCell, t, icsTime_all, icsTimeOrig_all, icsSpace_all, CellImgs, MaskMov

function [nCell, t, icsTime_all, icsTimeOrig_all, icsSpace_all, CellImgs, MaskMov] = ICA_Pre(session_path,is_stim, use_ring_bkg, use_support, support_dirname, slmoffFrames)

close all; dt = 1;%ms
% Set default for background subtraction method
if isempty(session_path)
    session_path = cd();
end
if nargin < 3 || isempty(use_ring_bkg)
    use_ring_bkg = 0;  % Default to standard corner box method for backward compatibility
end
if nargin < 5 %isempty(support_dirname)
    support_dirname = 'support';
end
if nargin < 6
    slmoffFrames = [];
end
% Get Stimulation protocol - what if there is no stimulation?
if is_stim
    get_stim_protocol(session_path);
end

% Load motion-corrected movie
DaqRate = 10000;
Info = textscan(fopen(fullfile(session_path, 'experimental_parameters.txt')),'%s');
nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
if use_support
    save_dir = fullfile(session_path, support_dirname);
    mov = loadtiff(fullfile(save_dir, "denoised.tiff"));
    % Info = textscan(fopen(fullfile(session_path, 'experimental_parameters.txt')),'%s');
    % nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
    % binPath = fullfile(session_path,'movReg.bin');
    % [movReg, nframes] = readBinMov(binPath, ncol, nrow);
    % 
    % imshow(movReg(:,:,10), [])
    % figure;
    % imshow(mov(:,:,10), [])
    
else
    save_dir = session_path;    
    binPath = fullfile(save_dir,'movReg.bin');
    [mov, nframes] = readBinMov(binPath, ncol, nrow);
end

nremove = 10/dt;
mov = double(mov(:,:,nremove+1:end));%Remove first 10 ms
nframes = size(mov, 3);
RefIm = mean(mov,3);%Avg image
t = (1:nframes)*dt;%Time vector

disp(nframes)
[Fmasks, roimask] = apply_mask_RMmov_BkgSel_FanLab_withpath(mov, session_path,'');
saveas(gca,fullfile(save_dir,'MaskTraces_RMmov.fig'));

Fmask2 = zeros(nframes,1); outrangecell = zeros(1);
for i = 1:length(roimask)
    if ~isnan(Fmasks(1,i))
        Fmask2 = [Fmask2, Fmasks(:,i)];
    else
        outrangecell = [0,i];
    end
end
Fmask2(:,1) = []; outrangecell(1) = []; roimask(:,outrangecell) = [];

% Background subtraction - choose method based on use_ring_bkg parameter
intensC = Fmask2(:,1:end-1);
bkg     = Fmask2(:,end);

if use_ring_bkg
    % Ring-based scattered-light / crosstalk subtraction (automask xtalk)
    imgSize = [ncol, nrow];
    mov2 = subtractRingXtalk(mov, roimask, imgSize, 'save_dir', save_dir);
else
    % Standard corner box background subtraction (original method)
    sbkg = bkg;
    mov2 = mov - repmat(reshape(sbkg,[1,1,nframes]),[ncol,nrow,1]);
end

intens = apply_clicky(roimask, mov2);

% Split into mask movies
figure(4); clf
nCell = size(intensC,2); MaskMov = cell(nCell); CellImgs = cell(nCell,1);
for i = 1:nCell
    x1 = roimask{i}(:,2);
    y1 = roimask{i}(:,1); edge = 5;
    X1 = ceil(min(x1))-edge; if X1<1, X1=1; end
    X2 = floor(max(x1))+edge; if X2>ncol, X2=ncol; end
    Y1 = ceil(min(y1))-edge; if Y1<1, Y1=1; end
    Y2 = floor(max(y1))+edge; if Y2>nrow, Y2=nrow; end
    MaskMov{i} = mov2(X1:X2,Y1:Y2,:);
    subplot(ceil(nCell/1.9),ceil(nCell/1.9),i);
    imshow(mean(MaskMov{i},3),[]); title(i);
end

smoothing = 100; alpha = 0.9; Bin = 2;
icsTime_all = cell(nCell,1); icsTimeOrig_all = cell(nCell,1); icsSpace_all = cell(nCell,1);

for i = 1:nCell
    smallmov = MaskMov{i};
    if mod(size(smallmov,1),2), smallmov = smallmov(1:end-1,:,:); end
    if mod(size(smallmov,2),2), smallmov = smallmov(:,1:end-1,:); end
    [nrow2, ncol2, nframe2] = size(smallmov);
    tmp = reshape(smallmov,Bin,nrow2/Bin,Bin,ncol2/Bin,nframe2);
    smovB = squeeze(mean(mean(tmp,1),3));
    smovBN = double(pblc(vm(smovB(:,:,1:end))));
    if exist('slmoffFrames','var') && ~isempty(slmoffFrames)
        ToUseFrames = setdiff(1:size(smovBN,3), slmoffFrames);
    else
        ToUseFrames = 1:size(smovBN,3);
    end
    smovBN2 = smovBN(:,:,ToUseFrames);
    [nrowB, ncolB, nframe2_use] = size(smovBN2);
    movHPF = smovBN2 - imfilter(smovBN2, ones(1,1,smoothing)/smoothing, 'replicate');

    %Remove large fluctuations (blood flow or other big fluctuations, better to keep)
    flucImg = mean(movHPF(:,:,1:end-1).*movHPF(:,:,2:end), 3);
    flucImgS = imfilter(flucImg, fspecial('gaussian', [5 5], 2), 'replicate');
    [~, idx] = sort(flucImgS(:), 'descend');
    T = round(length(idx)*0.03);
    mask = ones(size(flucImg)); mask(idx(1:T)) = 0;

    figure(100); clf;
    subplot(1,2,1); imshow2(flucImg, []);
    subplot(1,2,2); imshow(mask);
    saveas(gca,fullfile(save_dir, [num2str(i) 'flucImg.fig']))

    pause(2)
    movHPm = movHPF.*repmat(mask, [1 1 nframe2_use]);
    movVec = tovec(movHPm);
    covmat = movVec*movVec';
    [V, ~] = eig(covmat); V = V(:,end:-1:1);
    u = V(:,1:20); 
    
    Upic = toimg(u, nrowB, ncolB);
    figure(5); clf
    for j = 1:20
        subplot(4,5,j);
        imshow2(Upic(:,:,j), [])
    end
    saveas(gca,fullfile(save_dir, [num2str(i) 'PCAImg.fig']))
    
    v = movVec'*u;

    figure(6);clf
    stackplot(v)
    saveas(gca,fullfile(save_dir, [num2str(i) 'PCATrace.fig']))

    Movie = smovBN;
    vOrig = tovec(Movie - repmat(mean(Movie, 3),[1 1 size(Movie,3)]))'*u;

    % mixed spatio temporal ICA
    nEigUse = 15; nIcs = 10;
    uNorm = (u - mean(u))./std(u); vNorm = (v - mean(v))./std(v);
    [icsST, ~, sepmat] = sorted_ica([(1-alpha)*uNorm(:,1:nEigUse); alpha*vNorm(:,1:nEigUse)],nIcs);
    icsSpace = icsST(1:length(u),:);
    icsTime = icsST(end-length(v)+1:end,:);
    icsTimeOrig = vOrig(:,1:nEigUse)*sepmat';
    if exist('slmoffFrames','var') && ~isempty(slmoffFrames) && size(icsTime,1) ~= size(smovBN,3)
        icsTime_full = nan(size(smovBN,3), size(icsTime,2));
        icsTime_full(ToUseFrames,:) = icsTime;
        icsTime = icsTime_full;
    end

    icsTime_all{i} = icsTime;
    icsTimeOrig_all{i} = icsTimeOrig;
    icsSpace_all{i} = icsSpace;
    CellImgs{i} = mean(MaskMov{i},3);
end

if ~exist('slmoffFrames','var'); slmoffFrames = []; end
save(fullfile(save_dir,'ICA_PreResults.mat'),'icsTime_all','icsTimeOrig_all','icsSpace_all','nCell','t','CellImgs','MaskMov','nrowB','ncolB','slmoffFrames');
%Could probably delete some of these - ie nrowB,ncolB
end

