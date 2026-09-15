%% reset
clear; close all;
rng(123);
%% Setup
% Automatically detect OS: Windows uses Z:\, macOS/Linux use /Volumes/fanlab
if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end

tinkering = 1; % if editing in labmembers directory before pushing changes
%motion_corr = 'post-motion'; 
%dataset_type = 'train';
%% generating paths
if ~tinkering
    code_path = fullfile(root_path,'Computer Code');
else
    code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code'); % change to wherever you cloned support into
end
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));
%% set paths to data
% look through all of these parent folders for sessions
path.root.data = {fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'BTSP_CB1pharm'), ...
                  fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-DSI'), ...
                  fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-DSI_CB1pharm'), ...
                  fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-IPSP'), ...
                  fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-IPSP_WT')};
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', 'PC_no_stim');
custom_raw_roots = path.root.data;

% TODO add functionality to select specific animals/sessions
path.anim_ids = {};
path.sess_ids = {};
sel_FOVs = [];
sel_slices = [];
animal_type = '';
exclude = {'Expression', 'nobeh', 'CCKBC', 'cck-gevi', 'wkEC', 'check'};
min_spikes = 0; 
snr_min = 0;
saveStr = ''; %sprintf("minSNR_%d", snr_min);
path.save_dir = fullfile(path.cell_type, saveStr);
%% setup sessions structure
% if the total sessions struct already exists, load it
if ~exist(path.save_dir, 'dir')
    mkdir(path.save_dir); end
if exist(fullfile(path.cell_type, sprintf("total_sessions%s.mat", saveStr)), 'file')
    load(fullfile(path.cell_type, sprintf("total_sessions%s.mat", saveStr)), 'total_sessions');
    if ispc
        total_sessions = convert_struct_paths(total_sessions, 'Z:/');
    end
else
    total_sessions = struct([]);

    % skip any directories that contain the strings in exclude
    % skip_func = @(folder) any( ...
    %     cellfun(@(e) contains(folder, e, 'IgnoreCase', true), exclude) ...
    % );
    anim_prefixes = {'ipsp', 'fos', 'cck'};
    for root_i = 1:numel(path.root.data)
        for p = 1:numel(anim_prefixes)
            new_sessions = discover_sessions(path.root.data{root_i}, anim_prefixes{p}, '', ...
                                             struct(), exclude, true, true);
            total_sessions = [total_sessions, new_sessions]; %#ok<AGROW>
        end
    end
    if isempty(total_sessions)
        error('No recordings with inter_spikeT_spikeW.mat found under root paths');
    end
    keep_fields = {'anim_id','session_path','session_name','slice','FOV', ...
                   'cell_id','fov_num_cells','cell_hash'};
    total_sessions = rmfield(total_sessions, setdiff(fieldnames(total_sessions), keep_fields));
    total_sessions = convert_struct_paths(total_sessions, root_path);

    % keep cells with unique animal/date/slice/FOV/recording, even across project roots
    cell_keys = arrayfun(@(s) sprintf('%s|%s|%d', s.anim_id, ...
        extractAfter(s.session_path, [filesep s.anim_id filesep]), s.cell_id), ...
        total_sessions, 'UniformOutput', false);
    [~, unique_idx] = unique(cell_keys, 'stable');
    total_sessions = total_sessions(unique_idx);

    % % finding all analyzed data to filter for fr, snr, etc.
    % all_matching_files = fsfind(path.root.data, 'sessions\.mat', Depth=5, SkipFolderFcn=skip_func);
    % % get rid of duplicates
    % all_matching_files = unique(all_matching_files);
    % for file_i = 1:length(all_matching_files)
    %     sess_path = all_matching_files{file_i};
    %     loaded_sess = load(sess_path, 'sessions');
    %     % only keep certain fields
    %     keep_fields = {'anim_id','session_path','session_name','FOV','cell_id','fov_num_cells','cell_hash', 'fr', 'snr', 'nspikes'};
    %     sess_struct = loaded_sess.sessions;
    %     sess_struct = rmfield(sess_struct, setdiff(fieldnames(sess_struct), keep_fields));
    %     total_sessions = [total_sessions, sess_struct]; %#ok<AGROW>
    % end
    % remove_fields = {};%{'fr', 'snr', 'nspikes'};
    % total_sessions = curateSessions(total_sessions, min_spikes, snr_min, true, remove_fields);
    % total_sessions = convert_struct_paths(total_sessions, root_path);
    % make sure each session_path exists
    valid_paths = arrayfun(@(s) isfolder(s.session_path), total_sessions);
    total_sessions = total_sessions(valid_paths);
    % keep sessions with unique session_paths
    save(fullfile(path.cell_type, sprintf("total_sessions_%s.mat", saveStr)), 'total_sessions');
end
%% filter total sessions
% keep all the sessions
%nsessions = 350; %number of sessions to randomly keep
% if length(total_sessions) > nsessions
%     rand_indices = randperm(length(total_sessions), nsessions);
%     total_sessions = total_sessions(rand_indices);
% end
% 
% save(fullfile(path.cell_type, 'dataset_sessions.mat'), 'total_sessions');
% dataset_sessions = total_sessions;
% sessions = convert_struct_paths(dataset_sessions, root_path);
% nsessions = length(sessions);

%% Saving Samples of Masked Recordings
target_file = 'movReg.bin';
n_sessions = length(total_sessions);
%if contains(dataset_type, 'test'); sample = 0; else if contains(dataset_type, 'train'); sample = 1; else; sample = 0; end; end
sel_nframes = ceil(300000/n_sessions); % selecting enough to make a 300,000 frame dataset
% Stim-avoidance settings: get_stim_protocol's trace/frame alignment assumes
% a 1 kHz frame rate (10 kHz DAQ downsampled by 10, see ICA_Pre_diffpaths.m dt=1ms)
filter_stim = true; % set false to use the old unrestricted-random start selection
stim_thresh = 0.1; % matches get_stim_protocol default
%quality control!!
if filter_stim
    qc_dir = fullfile(path.save_dir, 'stim_qc'); % per-session plots verifying stim-free sampling
    if ~exist(qc_dir, 'dir'); mkdir(qc_dir); end
    qc_summary = struct('hash_id', {}, 'sess_id', {}, 'had_stim_data', {}, ...
        'any_overlap', {}, 'starting_idx', {}, 'sel_nframes', {}, 'nframes', {});
end

for sess_i = 1:n_sessions
    path_to_sess = char(fullfile(total_sessions(sess_i).session_path));
    try % sometimes path doesn't exist
        cd(path_to_sess);
    catch
        fprintf('Skipping missing session path: %s\n', path_to_sess);
        continue;
    end
    hash_id = total_sessions(sess_i).cell_hash;
    sess_name = total_sessions(sess_i).session_name;
    sess_id = strsplit(sess_name, '_');
    sess_id = sess_id{1};
    filename = hash_id + "_" + sess_id + ".tiff";
    file_path = fullfile(path.save_dir, filename);
    if ~isfile(file_path)
        target = fullfile(path_to_sess, target_file);
        fid = fopen(fullfile(path_to_sess,'experimental_parameters.txt'), 'r');
        Info = textscan(fid, '%s');
        fclose(fid);
        ncol = str2double(Info{1}{6});
        nrow = str2double(Info{1}{3});
        [mov, nframes] = readBinMov(target, nrow, ncol);

        if filter_stim
            orig_nframes = nframes;

            % Determine whether this session used location-specific (VR-synced)
            % stimulation by checking the project folder name in its path (e.g.
            % ".../DSI-BTSP/BTSP_CB1pharm/..." -> is_btsp=true, vs the
            % CCKBC-to-PC-DSI/IPSP folders which don't have "BTSP" in their own
            % name despite sharing the "DSI-BTSP" parent directory).
            matching_roots = path.root.data(cellfun(@(r) startsWith(path_to_sess, r), path.root.data));
            if ~isempty(matching_roots)
                [~, root_folder_name] = fileparts(matching_roots{1});
                is_btsp = contains(root_folder_name, 'BTSP', 'IgnoreCase', true);
            else
                is_btsp = false;
            end

            % Identify stimulated frames (if any) so we avoid sampling across them
            is_stim_frame = false(1, nframes);
            had_stim_data = false;
            try
                stim_protocol = get_stim_protocol(path_to_sess, is_btsp, 1); % is_ds=1 aligns trace to frame rate
                stim_trace = stim_protocol.trace;
                n_stim = min(numel(stim_trace), nframes);
                is_stim_frame(1:n_stim) = stim_trace(1:n_stim) > stim_thresh;
                had_stim_data = true;
            catch ME
                fprintf('No stim protocol found for %s (%s); treating as unstimulated.\n', path_to_sess, ME.message);
            end

            % A starting index is valid only if the whole [start, start+sel_nframes-1]
            % window falls entirely before the next stim onset or after the previous
            % stim offset (i.e., contains no stimulated frames at all)
            last_start = nframes - sel_nframes + 1;
            cum_stim = cumsum([0, is_stim_frame]);
            window_stim_count = cum_stim(sel_nframes+1:nframes+1) - cum_stim(1:last_start);
            valid_starts = find(window_stim_count == 0);

            if isempty(valid_starts)
                fprintf('No stim-free window found for %s; sampling without stim restriction.\n', path_to_sess);
                starting_idx = int16(rand * (nframes-sel_nframes));
            else
                starting_idx = int16(valid_starts(randi(numel(valid_starts))));
            end

            % QC: plot the stim mask alongside the sampled window and confirm no overlap
            window_range = double(starting_idx):double(starting_idx)+sel_nframes-1;
            any_overlap = any(is_stim_frame(window_range));
            fig = figure('Visible', 'off');
            stairs(1:orig_nframes, double(is_stim_frame), 'k'); hold on;
            patch([window_range(1), window_range(end), window_range(end), window_range(1)], ...
                  [0, 0, 1, 1], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
            ylim([-0.1, 1.1]); xlim([1, orig_nframes]);
            xlabel('Frame'); ylabel('Stimulated (1) / Not (0)');
            title_str = sprintf('%s\\_%s: window [%d-%d], stim data: %d, overlap: %d', ...
                hash_id, sess_id, window_range(1), window_range(end), had_stim_data, any_overlap);
            title(title_str, 'Interpreter', 'none');
            legend({'Stim mask', 'Sampled window'}, 'Location', 'best');
            saveas(fig, fullfile(qc_dir, sprintf('%s_%s_stimQC.png', hash_id, sess_id)));
            close(fig);

            qc_summary(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, ... %#ok<SAGROW>
                'had_stim_data', had_stim_data, 'any_overlap', any_overlap, ...
                'starting_idx', double(starting_idx), 'sel_nframes', sel_nframes, 'nframes', orig_nframes);
            if any_overlap
                fprintf('WARNING: sampled window for %s overlaps stimulation frames!\n', path_to_sess);
            end
        else
            % Old behavior: unrestricted random start, no stim filtering/QC
            starting_idx = int16(rand * (nframes-sel_nframes));
        end

        mov_part = double(mov(:, :, starting_idx:starting_idx+sel_nframes-1));
        nframes = size(mov_part, 3);
        [Fmasks, roimask] = apply_mask_RMmov_BkgSel_nodisp(mov_part, Info);
        Fmask2 = zeros(nframes,1); outrangecell = zeros(1);
        for i = 1:length(roimask)
            if ~isnan(Fmasks(1,i))
                Fmask2 = [Fmask2, Fmasks(:,i)];
            else
                outrangecell = [0,i];
            end
        end
        Fmask2(:,1) = []; outrangecell(1) = []; roimask(:,outrangecell) = [];
        
        % Background subtraction
        bkg = Fmask2(:,end);
        sbkg = bkg;
        mov2 = mov_part - repmat(reshape(sbkg,[1,1,nframes]),[nrow, ncol,1]);
        
        i = total_sessions(sess_i).cell_id;
        x1 = roimask{i}(:,2);
        y1 = roimask{i}(:,1); edge = 5;
        X1 = ceil(min(x1))-edge; if X1<1, X1=1; end
        X2 = floor(max(x1))+edge; if X2>nrow, X2=nrow; end
        Y1 = ceil(min(y1))-edge; if Y1<1, Y1=1; end
        Y2 = floor(max(y1))+edge; if Y2>ncol, Y2=ncol; end
        MaskMov = mov_part(X1:X2,Y1:Y2,:);
        options.big = true;
        saveastiff(MaskMov, char(file_path), options);
    else; fprintf('Skipping saved file: %s\n', file_path);
    end
end
if filter_stim && ~isempty(qc_summary)
    save(fullfile(qc_dir, 'stim_qc_summary.mat'), 'qc_summary');
    n_overlap = sum([qc_summary.any_overlap]);
    fprintf('Stim QC: %d/%d sampled windows overlap stimulation (see %s).\n', ...
        n_overlap, numel(qc_summary), qc_dir);
end
%save(fullfile(path.root.support, 'cck-gevi', 'sessions_modified.mat'), "sessions")
%sprintf("Max rows: %d, Max cols: %d", max_row, max_col)

%% visualize one of the saved tiffs
imshow(MaskMov(:, :, 10), []);
%% Functions
% copied from apply_mask_RMmov_BkgSel_FanLab.m
function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_nodisp(mov, info)
path = cd;
xoffset = str2num(info{1,1}{33,1})-288; yoffset = str2num(info{1,1}{30,1})-288;
cd('../'); load Masks; cd(path);%load EVmask; cd(path);
num_masks=length(pts_list);
ROI=cell(1,num_masks);
for i=1:num_masks
    x1=pts_list{i}(:,2)/2-xoffset; y1=pts_list{i}(:,1)/2-yoffset;
    ROImask{i}=[x1,y1];
end

xbk=[1;30;30;1;1]; ybk = [1;1;30;30;1] + 0;
ROImask{num_masks+1} = [xbk,ybk];

Fmasks=apply_clicky(ROImask,double(mov), 'no');
end
