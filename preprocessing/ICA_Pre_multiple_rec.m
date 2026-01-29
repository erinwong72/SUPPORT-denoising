function [concat_opts, nCell, t, icsTime_all, icsTimeOrig_all, icsSpace_all, CellImgs, MaskMov] = ICA_Pre_multiple_rec(varargin)

optsDefault = struct( ...
    'session_path', cd(), ...
    'is_stim', true, ...
    'use_ring_bkg', false, ...
    'use_support', false, ...
    'support_dirname', 'support', ...
    'concat_opts', struct() ...
);

% If the first input is a struct, use it
if nargin >= 1 && isstruct(varargin{1})
    opts = varargin{1};
    % Fill in missing fields from defaults
    f = fieldnames(optsDefault);
    for i = 1:numel(f)
        if ~isfield(opts, f{i})
            opts.(f{i}) = optsDefault.(f{i});
        end
    end
else
    % Parse name-value pairs
    opts = optsDefault;
    if mod(nargin,2) ~= 0
        error('Name-value arguments must come in pairs.');
    end
    for k = 1:2:nargin
        name = varargin{k};
        value = varargin{k+1};
        if isfield(opts, name)
            opts.(name) = value;
        else
            error('Unknown option "%s"', name);
        end
    end
end

% Extract individual variables for convenience
session_path    = opts.session_path;
is_stim         = opts.is_stim;
use_ring_bkg    = opts.use_ring_bkg;
use_support     = opts.use_support;
support_dirname = opts.support_dirname;
concat_opts     = opts.concat_opts;

% if concat_opts is missing fields, fill in defaults
if ~isfield(concat_opts, 'concat')
    concat_opts.concat = false;
end
close all; dt = 1; % ms

% Get Stimulation protocol - what if there is no stimulation?
if is_stim
    get_stim_protocol(session_path);
end

if concat_opts.concat
    disp('Concatenating multiple recordings for ICA/PCA analysis...');
    if isempty(concat_opts.mode)
        concat_opts.mode = 'prompt';
    end
end

% Load motion-corrected movie
DaqRate = 10000;
Info = textscan(fopen(fullfile(session_path, 'experimental_parameters.txt')),'%s');
nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
if use_support
    save_dir = fullfile(session_path, support_dirname);
    if concat_opts.concat
        mov = [];
        FOV_path = fileparts(session_path);
        target_file = fullfile(support_dirname, 'denoised.tiff');
        [mov_list, current_idx, concat_opts] = autoSelectSessions(FOV_path, target_file, ...
                                                            session_path, concat_opts);
        % check for existing ICA_PreResults concatenated file
        if exist(fullfile(session_path, support_dirname, sprintf('ICA_PreResults_concat_%s.mat', concat_opts.save_name)), 'file')
            return; % skip processing if already done
        end
        frames_per_recording = zeros(1, length(mov_list));
        for i = 1:length(mov_list)
            mov_i = loadtiff(fullfile(mov_list{i}, support_dirname, "denoised.tiff"));
            mov = cat(3, mov, mov_i);
            frames_per_recording(i) = size(mov_i, 3);
        end
        
    else
        mov = loadtiff(fullfile(save_dir, 'denoised.tiff'));
    end

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
    if concat_opts.concat
        mov = [];
        FOV_path = fileparts(session_path);
        [mov_list, current_idx, concat_opts] = autoSelectSessions(FOV_path, 'movReg.bin', session_path, concat_opts);
        if exist(fullfile(session_path, sprintf('ICA_PreResults_concat_%s.mat', concat_opts.save_name)), 'file')
            return; % skip processing if already done
        end
        frames_per_recording = zeros(1, length(mov_list));
        for i = 1:length(mov_list)
            mov_i = readBinMov(fullfile(mov_list{i}, "movReg.bin"), ncol, nrow);
            mov = cat(3, mov, mov_i);
            frames_per_recording(i) = size(mov_i, 3);
        end
    else
        binPath = fullfile(save_dir,'movReg.bin');
        [mov, nframes] = readBinMov(binPath, ncol, nrow); 
    end
    
end

nremove = 10/dt;
mov = double(mov(:,:,nremove+1:end));%Remove first 10 ms
nframes = size(mov, 3);
RefIm = mean(mov,3);%Avg image
t = (1:nframes)*dt;%Time vector
if concat_opts.concat
    concat_opts.save_name = char(concat_opts.save_name);
    save_flag_concat = sprintf('concat_%s_%d_%s', concat_opts.mode, concat_opts.n_sessions, concat_opts.save_name);
    mask_title = sprintf('Auto-masked concatenated (%s, %d sessions, %s)', concat_opts.mode, concat_opts.n_sessions, concat_opts.save_name);
    mask_save_name = sprintf('MaskTraces_RMmov_%s.fig', save_flag_concat);
else; mask_save_name = 'MaskTraces_RMmov.fig'; mask_title = 'Auto-masked';
end
[Fmasks, roimask] = apply_mask_RMmov_BkgSel_FanLab_withpath(mov, session_path, mask_title);

saveas(gca,fullfile(save_dir, mask_save_name));

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
    % Circular ring-based background subtraction
    % Use the circular ring-based background subtraction strategy from
    % Run_xtalk_PCA_ICA_RMmov_FanLab_function_automask.m
    % Build a ring mask around all cell ROIs (exclude the last background ROI)
    imgSize   = [ncol, nrow];      % [width, height] for generateRingMaskFromROI
    ringWidth = 3;                 % ring width in pixels
    gap       = 4;                 % gap between ROI and ring
    ringMask  = generateRingMaskFromROI(roimask(1:end-1), imgSize, ringWidth, gap);
    
    % Compute per-frame mean ring intensity and subtract it from each frame
    mov2       = zeros(size(mov), 'like', mov);
    ringSignal = zeros(nframes,1);
    for t0 = 1:nframes
        frame = mov(:,:,t0);
        ringSignal(t0) = mean(frame(ringMask));
        mov2(:,:,t0)   = frame - ringSignal(t0);
    end
    
    % Optional diagnostic plot of ring mask and signal
    figure;
    subplot(1,2,1);
    imshow(ringMask);
    title('Ring Mask');
    subplot(1,2,2);
    plot(1:nframes, ringSignal);
    xlabel('Frame'); ylabel('Mean Ring Intensity');
    title('Ring Signal Over Time');
    saveas(gcf, fullfile(save_dir,'RingMaskAndSignal.fig'));
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
    smovBN2 = smovBN(:,:,1:end);
    [nrowB, ncolB, ~] = size(smovBN2);
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
    movHPm = movHPF.*repmat(mask, [1 1 nframe2]);
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

    if concat_opts.concat
        saveas(gca,fullfile(save_dir, [num2str(i) 'PCAImg_' save_flag_concat '.fig']))
    else
        saveas(gca,fullfile(save_dir, [num2str(i) 'PCAImg.fig']))
    end

    v = movVec'*u;

    figure(6);clf
    stackplot(v)

    if concat_opts.concat
        saveas(gca,fullfile(save_dir, [num2str(i) 'PCATrace_' save_flag_concat '.fig']))
    else
        saveas(gca,fullfile(save_dir, [num2str(i) 'PCATrace.fig']))
    end

    Movie = smovBN;
    vOrig = tovec(Movie - repmat(mean(Movie, 3),[1 1 size(Movie,3)]))'*u;

    % mixed spatio temporal ICA
    nEigUse = 15; nIcs = 10;
    uNorm = (u - mean(u))./std(u); vNorm = (v - mean(v))./std(v);
    [icsST, ~, sepmat] = sorted_ica([(1-alpha)*uNorm(:,1:nEigUse); alpha*vNorm(:,1:nEigUse)],nIcs);
    icsSpace = icsST(1:length(u),:);
    icsTime = icsST(end-length(v)+1:end,:);
    icsTimeOrig = vOrig(:,1:nEigUse)*sepmat';
    if concat_opts.concat
        cum_frames = [0, cumsum(frames_per_recording)]; % include 0 for easier indexing
        current_frame_idx = cum_frames(current_idx) + 1; % start index of current
        current_frame_idx_end = cum_frames(current_idx + 1); % end index of current
        curr_frames = current_frame_idx:current_frame_idx_end;
        % sanity check
        assert(numel(curr_frames) == frames_per_recording(current_idx))

        icsTime_curr = icsTime(curr_frames, :);
        icsTimeOrig_curr = icsTimeOrig(curr_frames, :);
        icsTime_all{i} = icsTime_curr;
        icsTimeOrig_all{i} = icsTimeOrig_curr;
        icsSpace_all{i} = icsSpace;
        CellImgs{i} = mean(MaskMov{i},3);
        if concat_opts.mode ~= "all" % will want to save the icsTime for all sessions in FOV in case of future use
            continue; % skip to next mask
        end
    end
    icsTime_all{i} = icsTime;
    icsTimeOrig_all{i} = icsTimeOrig;
    icsSpace_all{i} = icsSpace;
    CellImgs{i} = mean(MaskMov{i},3);
end
if concat_opts.concat; ica_save_name = sprintf('ICA_PreResults_%s.mat', save_flag_concat); else; ica_save_name = 'ICA_PreResults.mat'; end

save(fullfile(save_dir,ica_save_name),'icsTime_all','icsTimeOrig_all','icsSpace_all','nCell','t','CellImgs','MaskMov','nrowB','ncolB');
%Could probably delete some of these - ie nrowB,ncolB
end

% --- helper function to get list of recordings to concatenate ---
function [selected_dirs, current_idx, concat_opts] = autoSelectSessions( ...
        FOV_path, target_file, current_rec, concat_opts)
    % Automatically select sessions based on the specified mode
    dir_info = dir(FOV_path); 
    dir_names = {dir_info([dir_info.isdir]).name}; 
    dir_names = dir_names(~ismember(dir_names, {'.', '..'})); % Exclude . and .. 
    % only add directories if they contain the target file 
    valid_dirs = {};
    for i = 1:length(dir_names)
        if isfile(fullfile(FOV_path, dir_names{i}, target_file))
            valid_dirs{end+1} = fullfile(FOV_path, dir_names{i}); %#ok<AGROW>
        end
    end
    curr_idx = find(strcmp(valid_dirs, current_rec), 1); 
    n_total  = numel(valid_dirs);

    if isempty(curr_idx)
        error('Current recording not found.');
    end
    concat_opts.n_sessions = min(concat_opts.n_sessions, n_total);

    switch lower(concat_opts.mode)
        case 'all'
            % select all sessions
            start_idx = 1;
            end_idx   = n_total;
        case 'previous'
        % get n_sessions before current
            start_idx = max(1, curr_idx - concat_optsn_sessions + 1);
            end_idx   = curr_idx;

            % If this is the first recording, allow future
            if curr_idx == 1
                end_idx = min(n_total, concat_opts.n_sessions);
            end
        case 'center'
            % get sessions centered around current, accounting for whether current is at start or end
            half_n = floor(concat_opts.n_sessions / 2);
            start_idx = max(1, curr_idx - half_n);
            end_idx   = min(n_total, start_idx + concat_opts.n_sessions - 1);
            start_idx = max(1, end_idx - concat_opts.n_sessions + 1); % adjust start if at end    
        case 'spon'
            % get sessions without stimulation
            % check whether directory has subdirectory 'matlab wvfms'
            spon_dirs = {};
            for i = 1:length(valid_dirs)
                if ~isfolder(fullfile(valid_dirs{i}, 'matlab wvfm'))
                    spon_dirs{end+1} = valid_dirs{i}; %#ok<AGROW>
                end
            end
            valid_dirs = spon_dirs;
            n_total = numel(valid_dirs);
            curr_idx = find(strcmp(valid_dirs, current_rec), 1);
            if isempty(curr_idx)
                current_idx = 0; % current recording is with stimulation
            end
            concat_opts.n_sessions = min(concat_opts.n_sessions, n_total);
        case 'prompt'
            % interactive prompt asking user to select which sessions to concatenate with current
            fprintf('Available recordings:\n');
            for i = 1:n_total
                % display index and directory name, highlight current recording
                if i == curr_idx
                    fprintf('%d: %s (current)\n', i, valid_dirs{i});
                else
                    fprintf('%d: %s\n', i, valid_dirs{i});
                end
            end
            % display names of valid recordings with corresponding indices to user for selection
            selection = input('Enter indices of recordings to concatenate, including current (e.g., [1 3 5]): ');
            if ~isvector(selection) || any(selection < 1) || any(selection > n_total)
                error('Invalid selection.');
            end
            selected_dirs = valid_dirs(selection);   
            concat_opts.save_name = input('Enter a name identifier for this concatenation (e.g., "no_stim"): ', 's');
            current_idx = find(selection == curr_idx, 1);
            if isempty(current_idx)
                disp('Warning: Current recording not included in selection.');
                current_idx = 0;
            end
    end
    if strcmpi(concat_opts.mode, 'prompt')
        return; % already have selected_dirs from user input
    end
    selected_dirs = valid_dirs(start_idx:end_idx);
    if current_idx ~= 0
        current_idx = curr_idx - start_idx + 1;
    end
end
