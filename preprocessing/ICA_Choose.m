% This is the manual input portion of Run_PCA_ICA_RMmov_FanLab_function
% Save this as Run_PCA_ICA_RMmov_FanLab_Input.m

function ICA_Choose(session_path, use_support, support_dirname, use_template, use_auto, auto_skip_flagged, cell_subset)
% use_auto (optional, default false): when true, score_ica_components.m
% scores every IC per cell and auto-selects the top-scoring one (including
% sign/invert) when the score and margin over the runner-up are both high
% enough. Ambiguous cells still prompt as before, but the suggested IC is
% shown and pressing Enter accepts it. Every decision (auto or flagged) is
% appended to ICA_AutoSelect_Log.mat in save_dir for later review — see
% reviewFlaggedICA.m to list just the flagged cells across many sessions.
%
% auto_skip_flagged (optional, default false): only meaningful when
% use_auto is true. When true, ambiguous cells are never prompted — they're
% logged as flagged, their column in IntensOrig is left as NaN and
% ICAImgs{i} as a blank placeholder, and the loop moves straight to the
% next cell. Use this to let a whole batch run unattended (no windows pop
% up, nothing steals focus), then come back later with
% cell_subset = findSkippedICACells(save_dir, use_template) and re-run with
% use_auto=false to pick those interactively — previously-decided cells are
% reloaded from disk first, so only the requested subset is touched.
%
% cell_subset (optional, default [] = process every cell 1:nCell): restrict
% processing to these cell indices. Existing Masks_BestIcaTrace(.mat) /
% Masks_BestIcaImgs(.mat) results (if present and the same size) are loaded
% first so cells outside cell_subset keep their prior decisions.

AUTO_SCORE_THR = 0.55;
AUTO_MARGIN_THR = 0.10;

positions = {
    [0.0, 0.5, 0.5, 0.5]; % Top-left
    [0.5, 0.5, 0.5, 0.5]; % Top-right
    [0.0, 0.0, 0.5, 0.5]; % Bottom-left
    [0.5, 0.0, 0.5, 0.5]; % Bottom-right
    };
if nargin <3
    support_dirname = 'support';
end
if nargin < 5
    use_auto = false;
end
if nargin < 6
    auto_skip_flagged = false;
end
if nargin < 7
    cell_subset = [];
end
if use_support
    save_dir = fullfile(session_path, support_dirname);
else
    save_dir = session_path;
end
load(fullfile(save_dir, 'ICA_PreResults.mat'),'icsTime_all', 'icsTimeOrig_all', 'icsSpace_all', 'nCell', 't', 'CellImgs', 'MaskMov'); % loads icsTime_all, icsTimeOrig_all, icsSpace_all, nCell, t, CellImgs, MaskMov
h = openfig(fullfile(save_dir, 'MaskTraces_RMmov.fig'), 'new', 'invisible');%Raw Traces
set(h, 'Units', 'normalized', 'Position', positions{1});
setFigVisQuiet(h, 'on');

if use_template
    trace_file = fullfile(save_dir, 'Masks_BestIcaTrace_template.mat');
    imgs_file  = fullfile(save_dir, 'Masks_BestIcaImgs_template.mat');
else
    trace_file = fullfile(save_dir, 'Masks_BestIcaTrace.mat');
    imgs_file  = fullfile(save_dir, 'Masks_BestIcaImgs.mat');
end
IntensOrig = zeros(length(t), nCell);
ICAImgs = cell(nCell,1);
if isfile(trace_file) && isfile(imgs_file)
    prevTrace = load(trace_file, 'IntensOrig');
    prevImgs  = load(imgs_file, 'ICAImgs');
    if isequal(size(prevTrace.IntensOrig), [length(t), nCell]) && numel(prevImgs.ICAImgs) == nCell
        IntensOrig = prevTrace.IntensOrig;
        ICAImgs = prevImgs.ICAImgs;
    end
end

if isempty(cell_subset)
    cell_subset = 1:nCell;
end
for k = 1:nCell
    if isempty(ICAImgs{k}) % never-processed cell (fresh run, outside cell_subset, or resumed from an interrupted run)
        ICAImgs{k} = zeros(size(CellImgs{k}));
    end
end

%%
for i = cell_subset
    icsTime = icsTime_all{i};
    icsTimeOrig = icsTimeOrig_all{i};
    icsSpace = icsSpace_all{i};
    nrowB = floor(size(CellImgs{i,1}, 1)/2);
    ncolB = floor(size(CellImgs{i,1}, 2)/2);

    is_process = 1;
    while is_process
        nIcs = size(icsSpace,2);
        n_row = ceil((nIcs+1)/4);
        n_col = 4;

         %% Auto-scoring (computed first so we know whether this cell needs
         %% to be shown/prompted for at all before any figure is created)
         autoInvertIdx = []; % set below only when an auto pick needs inverting
         confident = false;
         skip_this_cell = false;
         if use_auto && ~use_template
             icScores = score_ica_components(icsSpace, icsTime, nrowB, ncolB, mean(MaskMov{i},3));
             allScores = [icScores.score];
             [sortedScores, sortIdx] = sort(allScores, 'descend');
             bestIdx = sortIdx(1);
             bestScore = sortedScores(1);
             if numel(sortedScores) > 1
                 margin = bestScore - sortedScores(2);
             else
                 margin = bestScore;
             end
             sgn = icScores(bestIdx).sign;
             confident = bestScore >= AUTO_SCORE_THR && margin >= AUTO_MARGIN_THR;
             logICASelection(save_dir, session_path, i, bestIdx, bestScore, margin, confident, sgn);
             skip_this_cell = ~confident && auto_skip_flagged;
         end
         % Visible only when a human actually needs to look at it — never
         % for a confident auto-pick, and never for a skipped/flagged cell
         % in unattended mode. Numbered figures can't take 'Visible' at
         % creation, so numberedFig keeps them hidden until after saveas.
         figVis = iff_str(confident || skip_this_cell, 'off', 'on');

         %% Figures — always built & saved to disk; shown only when needed
         h = numberedFig(7, positions{2});
         subplot(n_row,n_col,1);
         imshow(mean(MaskMov{i},3),[]);title('Template')
         for j = 1:nIcs
             subplot(n_row,n_col,j+1);
             imshow2(toimg(icsSpace(:,j), nrowB, ncolB), []);
             title(j)
         end
         suptitle(['Mask #' num2str(i)]);
         saveas(h,fullfile(save_dir, [num2str(i) 'ICAImg.fig']))
         setFigVisQuiet(h, figVis);

         h = numberedFig(8, positions{3});
         stackplot(icsTime(:,1:min(30, size(icsTime,2))));
         suptitle('High pass');
         setFigVisQuiet(h, figVis);

         h = numberedFig(9, positions{4});
         stackplot(icsTimeOrig(:,1:min(30, size(icsTimeOrig,2))));
         suptitle('Applied to Original movie');
         saveas(h,fullfile(save_dir, [num2str(i) 'ICATrace.fig']))
         setFigVisQuiet(h, figVis);

         %% Options
         if skip_this_cell
             fprintf('Cell #%d: FLAGGED for review — suggested IC #%d (score=%.2f, margin=%.2f) — SKIPPED, come back with findSkippedICACells\n', ...
                 i, bestIdx, bestScore, margin);
             IntensOrig(:,i) = NaN(length(t),1);
             ICAImgs{i} = zeros(size(CellImgs{i}));
             is_process = 0;
             is_new_mask = 0;
             continue
         end
         if use_template
             if ~is_new_mask; BestUpper = 'T'; else; BestUpper = num2str(11); end
         elseif use_auto
             if confident
                 fprintf('Cell #%d: auto-selected IC #%d (score=%.2f, margin=%.2f)%s\n', ...
                     i, bestIdx, bestScore, margin, iff_str(sgn==-1,' [inverted]',''));
                 if sgn == -1
                     BestUpper = 'I';
                     autoInvertIdx = bestIdx;
                 else
                     BestUpper = num2str(bestIdx);
                 end
             else
                 fprintf('Cell #%d: FLAGGED for review — suggested IC #%d (score=%.2f, margin=%.2f)\n', ...
                     i, bestIdx, bestScore, margin);
                 Best = input(['Choose best IC for cell #' num2str(i) ' [Enter = ' num2str(bestIdx) ...
                     ']: (C: crop, I: invert, P: Previous IC, T: template mask, R: redraw mask, M: merge recs) '], 's');
                 if isempty(strtrim(Best))
                     BestUpper = num2str(bestIdx);
                 else
                     BestUpper = upper(strtrim(Best));
                 end
             end
         else
            Best = input(['Choose best IC for cell #' num2str(i) ': (C: crop, I: invert, P: Previous IC, T: template mask, R: redraw mask, M: merge recs) '], 's');
            BestUpper = upper(strtrim(Best));
         end
         is_new_mask = 0;
        %BestUpper = makeICAFigs(icsSpace, icsTime, icsTimeOrig, MaskMov, i, save_dir, positions, nrowB, ncolB, struct('flag', false, 'rec_names', {}));
        if strcmp(BestUpper, 'C')
            %Get user input for time regions to remove.
            % all cells or option to remove time from just one cell?
            % Rerun ICApre with cropped time
            % Get back to this function
        elseif strcmp(BestUpper, 'I')
            % Invert logic here
            if ~isempty(autoInvertIdx)
                BestNum = autoInvertIdx;
            else
                Best = input(['Invert which IC for cell #' num2str(i) ':'],'s');
                BestNum = str2double(Best);
            end

            if ~isnan(BestNum) && BestNum >= 1 && BestNum <= nIcs && mod(BestNum,1)==0
                % Valid IC index
                IntensOrig(:,i) = -icsTimeOrig(:, BestNum);
                ICAImgs{i} = toimg(-icsSpace(:, BestNum), nrowB, ncolB);
                is_process = 0;
            else
                error('Invalid input. Enter C, I, or FOV #.');
            end
        elseif strcmp(BestUpper, 'T') 
            % Dimensions
            movie = MaskMov{i};
            ds_factor = 2;   % downsample factors rows and cols
            if mod(size(movie,1),ds_factor), movie = movie(1:end-1,:,:); end
            if mod(size(movie,2),ds_factor), movie = movie(:,1:end-1,:); end

            %Photobleaching correction - on movie

            %Define Mask
            mask = mean(movie,3); %Template Weights
            mask = (mask - min(mask(:))) / (max(mask(:)) - min(mask(:))); %Normalize
            thr = 0.4 * max(mask(:));%Set Threshold
            mask(mask < thr) = 0;       %Zero Threshold
            %figure(); imagesc(W);
            is_new_mask = 1;

        elseif strcmp(BestUpper, 'R')
            % Interactively redraw the cell ROI on its own template image,
            % then apply it the same way 'T' applies its auto-threshold mask.
            movie = MaskMov{i};
            ds_factor = 2;   % downsample factors rows and cols
            if mod(size(movie,1),ds_factor), movie = movie(1:end-1,:,:); end
            if mod(size(movie,2),ds_factor), movie = movie(:,1:end-1,:); end

            h_draw = figure; imshow(mean(movie,3), []);
            title(['Draw new ROI for cell #' num2str(i) ' — drag to draw, double-click to finish']);
            roiObj = drawfreehand('Closed', true);
            mask = double(createMask(roiObj));
            close(h_draw);
            is_new_mask = 1;

        elseif strcmp(BestUpper, 'P')
            % Dimensions
            movie = MaskMov{i};
            ds_factor = 2;   % downsample factors rows and cols
            if mod(size(movie,1),ds_factor), movie = movie(1:end-1,:,:); end
            if mod(size(movie,2),ds_factor), movie = movie(:,1:end-1,:); end

            %Get Previous Path
            parentPath = fileparts(session_path);

            parentDirs = dir(parentPath);
            parentDirs = parentDirs([parentDirs.isdir]);
            parentDirs = parentDirs(~ismember({parentDirs.name}, {'.','..','red','blue'}));

            parts = strsplit(session_path, filesep);
            currName = parts{end};
            idx = find(strcmp({parentDirs.name}, currName), 1);

            if ~isempty(idx) && idx > 1
                oneAbove = parentDirs(idx-1);
                oneAbove = fullfile(oneAbove.folder,oneAbove.name);
            else
                oneAbove = [];
                error('No previous mask found in ',oneAbove);
            end


            %Assume Previously choosen IC
            prev = load(fullfile(oneAbove,'Masks_BestIcaImgs.mat'),'ICAImgs');
            mask = prev.ICAImgs{i};
            is_new_mask = 1;

        elseif strcmp(BestUpper, 'M')
            % rerun ICA_Pre_multiple_rec with more recordings merged
            disp('rerunning ICA pre with more recordings merged - please wait...');
            concat_opts = struct('concat', true, 'mode', 'prompt', 'n_sessions', 2, 'save_name', '');
            ICAPre_opts = struct('session_path', session_path, 'use_support', use_support, 'support_dirname', support_dirname, 'concat_opts', concat_opts);
            concat_opts = ICA_Pre_multiple_rec(ICAPre_opts);
            save_name = sprintf('concat_%s_%d_%s', concat_opts.mode, concat_opts.n_sessions, concat_opts.save_name);
            ica_save_name = sprintf('ICA_PreResults_%s.mat', save_name);
            if isfile(fullfile(save_dir, ica_save_name))
                disp('Loading new ICA results...');
                load(fullfile(save_dir, ica_save_name)); % reload updated ICA results
                disp('Loading concatenated raw traces figure...');
                % allow for comparison between old and new, so hold previous figure
                hold on;
                h_concat = openfig(fullfile(save_dir, sprintf('MaskTraces_RMmov_%s.fig', save_name)), 'new', 'visible');%Raw Traces
                set(h_concat, 'Units', 'normalized', 'Position', positions{1});
                % reset outputs for this cell
                icsTime = icsTime_all{i};
                icsTimeOrig = icsTimeOrig_all{i};
                icsSpace = icsSpace_all{i};
                nrowB = floor(size(CellImgs{i,1}, 1)/2);
                ncolB = floor(size(CellImgs{i,1}, 2)/2);

                % re-display ICA figs for this cell using merged data
                merged = struct('flag', true, 'rec_names', strsplit(concat_opts.save_name, '_'));
                BestUpper = makeICAFigs(icsSpace, icsTime, icsTimeOrig, MaskMov, i, save_dir, positions, nrowB, ncolB, merged);
                is_process = 1; % continue processing for this cell
                % now have user select IC from new results

            else
                error('New ICA results file not found.');
            end
        else
            % Try to interpret as a number
            BestNum = str2double(BestUpper);

            if ~isnan(BestNum) && BestNum >= 1 && BestNum <= nIcs && mod(BestNum,1)==0
                % Valid IC index
                IntensOrig(:,i) = icsTimeOrig(:, BestNum);
                ICAImgs{i} = toimg(icsSpace(:, BestNum), nrowB, ncolB);
                is_process = 0;
            else
                error('Invalid input. Enter C, I, or FOV #.');
            end
        end

        if is_new_mask
          
            %Apply Mask to Movie
            [icsSpace_new,icsTimeOrig_new,icsTime_new] = applyMask2Movie(movie,mask,ds_factor);
            %[icsSpace_t, icsTime_t, icsTimeOrig_t] = trace_from_movie(movie, W);

            % Append as an extra component
            icsSpace    = [icsSpace, icsSpace_new];       % space: (nrowB*ncolB) x (nIcs+1)
            icsTimeOrig = [icsTimeOrig, icsTimeOrig_new]; % time (orig): T x (nIcs+1)
            icsTime     = [icsTime, icsTime_new];         % time (HP):   T x (nIcs+1)
        end

    end
    if use_template
        save(fullfile(save_dir, 'Masks_BestIcaTrace_template'),'IntensOrig');
        save(fullfile(save_dir, 'Masks_BestIcaImgs_template'),'ICAImgs','CellImgs');
    else
        save(fullfile(save_dir, 'Masks_BestIcaTrace'),'IntensOrig');
        save(fullfile(save_dir, 'Masks_BestIcaImgs'),'ICAImgs','CellImgs');
    end
    figure;
    for i = 1:nCell
        subplot(nCell+3,nCell*2,2*i-1); imshow(CellImgs{i},[]);
        subplot(nCell+3,nCell*2,2*i); imshow(ICAImgs{i},[]);
        subplot(nCell+3,nCell*2,i*nCell*2+1:(i+1)*nCell*2);
        plot(t/1000, IntensOrig(:,i), 'r'); ylabel('F'); hold on;
    end

    ai_data_path = fullfile(session_path, 'AI Data');
    try
        Bh = load(ai_data_path);
    catch ME
        % If MAT load fails (e.g., "not a binary mat-file"), try loading as ASCII
        if contains(ME.message, 'not a binary mat-file') || contains(ME.message, 'ASCII')
            try
                Bh = load(ai_data_path, '-ASCII');
            catch ME2
                error('Unable to load AI Data file as ASCII: %s\nError: %s', ai_data_path, ME2.message);
            end
        else
            % For other errors, try ASCII as fallback
            try
                Bh = load(ai_data_path, '-ASCII');
            catch ME2
                error('Unable to load AI Data file: %s\nOriginal error: %s\nASCII load error: %s', ...
                    ai_data_path, ME.message, ME2.message);
            end
        end
    end
    Bh2 = Bh(:,10+1:end); % Assumes dt = 1 ms and removal of first 10 ms
    DaqRate = 10000;
    tdaq = (1:size(Bh2,2)) / DaqRate;

    subplot(nCell+3,nCell*2,(nCell+1)*2*nCell+1:(nCell+2)*nCell*2);
    plot(tdaq, -75/75*64/0.75*(Bh2(1,:)-1.6497)/50 + 4, 'k'); hold on;
    plot(tdaq, Bh2(4,:)/5.2 + 3, 'color', [0.5,0.5,0.5]);
    plot(tdaq, Bh2(3,:)/3.2 + 2, 'r');
    plot(tdaq, Bh2(2,:)/5.2 + 1, 'c');
    %plot(tdaq, Bh2(5,:)/3.2 + 0, 'b');
    stim_protocol = get_stim_protocol(session_path);
    plot(tdaq, stim_protocol.WFAO(end-(size(Bh2,2)-1):end,1), 'b');% 10 ms offset Modified KS 11/4/25
    legend({'Velocity','TrialSynC','Reward','Lick','BlueStim'});
    xlabel('Time, sec'); ylabel('VR'); axis tight;
    if use_template
        saveas(gca, fullfile(save_dir, 'Fig_intens_ICA_template.fig'));
        saveas(gca, fullfile(save_dir, 'Fig_intens_ICA_template.png'));
    else
        saveas(gca, fullfile(save_dir, 'Fig_intens_ICA.fig'));
        saveas(gca, fullfile(save_dir, 'Fig_intens_ICA.png'));
    end
end

function BestUpper = makeICAFigs(icsSpace, icsTime, icsTimeOrig, MaskMov, i, save_dir, positions, nrowB, ncolB, merged)
% merged is a struct
% merged.flag = true/false
% merged.rec_names = ['Spon30', 'Spon30AO4',...] the names of the recordings that were merged
if isempty(merged)
    merged.flag = false;
    merged.rec_names = {};
end
if merged.flag
    suptitle_str = ['Mask #' num2str(i) ' (Merged: ' strjoin(merged.rec_names, ', ') ')'];
else
    suptitle_str = ['Mask #' num2str(i)];
end
nIcs = size(icsSpace,2);

%% Figures
h = figure(7); clf;
set(h, 'Units', 'normalized', 'Position', positions{2});
subplot(ceil(nIcs/3),ceil(nIcs/3),1);
imshow(mean(MaskMov{i},3),[]);title('Template')
for j = 1:size(icsSpace,2)
    subplot(ceil(nIcs/3),ceil(nIcs/3),j+1);
    imshow2(toimg(icsSpace(:,j), nrowB, ncolB), []);
    title(j)
end
suptitle(suptitle_str);
if merged.flag
    save_name = sprintf('ICAImg_%s_%d.fig', strjoin(merged.rec_names, '_'), i);
else
    save_name = sprintf('ICAImg_%d.fig', i);
end
saveas(gca,fullfile(save_dir, save_name))

h = figure(8); clf; set(h, 'Units', 'normalized', 'Position', positions{3});
stackplot(icsTime(:,1:min(30, size(icsTime,2))));
suptitle('High pass');

h = figure(9); clf; set(h, 'Units', 'normalized', 'Position', positions{4});
stackplot(icsTimeOrig(:,1:min(30, size(icsTimeOrig,2))));
if merged.flag
    suptitle('Applied to merged movie');
    save_name = sprintf('ICATrace_%s_%d.fig', strjoin(merged.rec_names, '_'), i);
else
    suptitle('Applied to Original movie');
    save_name = sprintf('ICATrace_%d.fig', i);
end
saveas(gca,fullfile(save_dir, save_name))

%% Options
if merged.flag
    prompt_str = ['Choose best IC for cell #' num2str(i) ' (Merged: ' strjoin(merged.rec_names, ', ') '): (C: crop, I: invert, P: Previous IC, T: template mask, R: redraw mask, U: undo merge) '];
else
    prompt_str = ['Choose best IC for cell #' num2str(i) ': (C: crop, I: invert, P: Previous IC, T: template mask, R: redraw mask, M: merge recs) '];
end
Best = input(prompt_str, 's');
BestUpper = upper(strtrim(Best));
end
end

function [icsSpace,icsTimeOrig,icsTime] =  applyMask2Movie(movie,mask,ds_factor)
            if nargin <3; ds_factor = 2;end
            [n_row, n_col,n_samp] = size(movie);

            %Bleaching Correction
            movie = double(pblc(vm(movie(:,:,1:end))));

            % Downsample - Reshape and average
            if isequal(size(mask), [n_row,n_col])
                mask_downsample = squeeze(mean(mean(reshape(mask, ds_factor, n_row/ds_factor, ds_factor, n_col/ds_factor),1), 3));    
            else
                movie = squeeze(mean(mean(reshape(movie, ds_factor, n_row/ds_factor, ds_factor, n_col/ds_factor,n_samp),1), 3));  
                mask_downsample = mask;
            end
            mask_ds_flat = reshape(mask_downsample, 1, [])';
            %figure(); hold on; plot((1:size(s,1))/1000,s);

            %Apply Mask
            mask_vec = reshape(mask, 1, []);               % 1x576
            M2   = reshape(movie, [], n_samp); % 576xT
            mask_mov = mask_vec * M2;                      % 1xT
            mask_mov = mask_mov(:);                       % Tx1
            mask_mov = (mask_mov-mean(mask_mov))/std(mask_mov)*60;%Z-score


            %smallmov = MaskMov{i};
            %if mod(size(smallmov,1),2), smallmov = smallmov(1:end-1,:,:); end
            %if mod(size(smallmov,2),2), smallmov = smallmov(:,1:end-1,:); end
            %[nrow2, ncol2, nframe2] = size(smallmov);
            %tmp = reshape(smallmov,Bin,nrow2/Bin,Bin,ncol2/Bin,nframe2);
            %smovB = squeeze(mean(mean(tmp,1),3));

            %not implemented yet - from ica pre
            %smovBN = double(pblc(vm(smovB(:,:,1:end))));
            %smovBN2 = smovBN(:,:,1:end);
            %[nrowB, ncolB, ~] = size(smovBN2);
            %movHPF = smovBN2 - imfilter(smovBN2, ones(1,1,smoothing)/smoothing, 'replicate');

            % High-pass the template trace - note distinct from ICA_pre implementation
            Fs = 1000;      % Hz (dt = 1 ms)
            Fc = 100;       % Hz cutoff
            [b,a] = butter(2, Fc/(Fs/2), 'high');
            mask_move_hp = filtfilt(b, a, mask_mov);
            mask_move_hp = mask_move_hp/(60/2);%Scaling

            % Return
            icsSpace    = mask_ds_flat;     % space: (nrowB*ncolB) x (nIcs+1)
            icsTimeOrig = mask_mov;         % time (orig): T x (nIcs+1)
            icsTime     = mask_move_hp;     % time (HP):   T x (nIcs+1)
end

function h = numberedFig(num, pos)
% Reuse figure NUM while keeping it hidden. MATLAB rejects
% figure(N, 'Visible', ...), and figure(N) would flash the window.
h = findall(0, 'Type', 'figure', 'Number', num);
if isempty(h)
    oldVis = get(0, 'DefaultFigureVisible');
    set(0, 'DefaultFigureVisible', 'off');
    h = figure(num);
    set(0, 'DefaultFigureVisible', oldVis);
end
set(h, 'Visible', 'off', 'Units', 'normalized', 'Position', pos);
set(0, 'CurrentFigure', h);
clf(h);
end

function setFigVisQuiet(h, figVis)
% Show/hide without yanking focus to the front. Visible='on' alone raises
% the window over other apps; toBack keeps it available behind them so you
% can multitask until you click into MATLAB.
if strcmp(figVis, 'off')
    set(h, 'Visible', 'off');
    return
end
set(h, 'Visible', 'on');
try
    warning('off', 'MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
    jf = get(h, 'JavaFrame');
    win = jf.fHG2Client.getWindow;
    win.toBack();
catch
    % JavaFrame gone on some newer MATLAB builds — Visible on is still fine
end
end

function out = iff_str(cond, a, b)
if cond; out = a; else; out = b; end
end

function logICASelection(save_dir, session_path, cellIdx, chosenIC, score, margin, confident, sgn)
% Appends one row per cell decision to ICA_AutoSelect_Log.mat in save_dir.
% Use reviewFlaggedICA.m to gather the Confident==false rows across sessions.
log_file = fullfile(save_dir, 'ICA_AutoSelect_Log.mat');
newRow = table(string(session_path), cellIdx, chosenIC, score, margin, confident, sgn, datetime('now'), ...
    'VariableNames', {'SessionPath','Cell','ChosenIC','Score','Margin','Confident','Sign','Timestamp'});
if isfile(log_file)
    s = load(log_file, 'autoLog');
    autoLog = [s.autoLog; newRow];
else
    autoLog = newRow;
end
save(log_file, 'autoLog');
end