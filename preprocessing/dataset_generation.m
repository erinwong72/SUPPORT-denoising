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
% path.root.data = {fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'BTSP_CB1pharm'), ...
%                   fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-DSI'), ...
%                   fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-DSI_CB1pharm'), ...
%                   fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-IPSP'), ...
%                   fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-IPSP_WT')};
path.root.data = {fullfile(root_path, 'Data and Analysis', 'DSI-BTSP', 'optoCCKBC-activation_BTSP')};
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', 'PC_no_stim_CCKBC_activation_BTSP');
custom_raw_roots = path.root.data;

% Optionally restrict dataset generation to specific animal/day/FOV/cell
% combinations. Leave path.sel_sessions = {} (default) to use every
% session/cell discovered under path.root.data.
%
% Each entry is a struct with any subset of the fields below; a field left
% empty/omitted matches ANY value for that field, so entries can be as broad
% or as specific as needed. Entries are OR'd together (a session is kept if
% it matches at least one entry).
%   anim_id   - char/string, matches total_sessions.anim_id
%   day       - char/string, matches the date folder name in session_path
%               (the path segment immediately after anim_id)
%   FOV       - numeric, matches total_sessions.FOV
%   cell_id   - numeric, matches total_sessions.cell_id
%
% Example:
% path.sel_sessions = {struct('anim_id','cck123','day','2025-01-13-VR-V_blue','FOV',2,'cell_id',3), ...
%                      struct('anim_id','cck456','FOV',1)}; % all cells in FOV1, any day, for cck456
path.sel_sessions = {};
% exclude = {'Expression', 'nobeh', 'CCKBC', 'cck-gevi', 'wkEC', 'check'};
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
% restrict to specific animal/day/FOV/cell combinations, if requested
if ~isempty(path.sel_sessions)
    sess_days = arrayfun(@(s) session_day(s.session_path, s.anim_id), total_sessions, 'UniformOutput', false);
    keep = false(1, numel(total_sessions));
    for sel_i = 1:numel(path.sel_sessions)
        sel = path.sel_sessions{sel_i};
        match = true(1, numel(total_sessions));
        if isfield(sel, 'anim_id') && ~isempty(sel.anim_id)
            match = match & strcmpi({total_sessions.anim_id}, sel.anim_id);
        end
        if isfield(sel, 'day') && ~isempty(sel.day)
            match = match & strcmpi(sess_days, sel.day);
        end
        if isfield(sel, 'FOV') && ~isempty(sel.FOV)
            match = match & ([total_sessions.FOV] == sel.FOV);
        end
        if isfield(sel, 'cell_id') && ~isempty(sel.cell_id)
            match = match & ([total_sessions.cell_id] == sel.cell_id);
        end
        keep = keep | match;
    end
    fprintf('Restricting to %d/%d sessions matching path.sel_sessions.\n', sum(keep), numel(total_sessions));
    total_sessions = total_sessions(keep);
    if isempty(total_sessions)
        error('path.sel_sessions matched no sessions in total_sessions.');
    end
end
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
%
% stim_mode controls how stimulation is handled when picking each session's
% sampled window:
%   'off'                - no stim filtering; sample anywhere in the session
%   'window_avoid'       - sample a sel_nframes window that avoids all stim
%                           periods within the session (falls back to 'off'
%                           if no such window exists)
%   'session_stim_free'  - only use sessions with NO stimulation anywhere;
%                           any session containing stim is skipped entirely
stim_mode = 'off'; % 'off' | 'window_avoid' | 'session_stim_free'
stim_thresh = 0.1; % matches get_stim_protocol default
% Minimum spike rate (Hz), computed from inter_spikeT_spikeW.mat spike times
% within the sampled window, required to accept that window. 0 = no filtering.
min_firing_rate = 0;

%% Audit firing rates before generating anything
% For each candidate session/cell, find the max spike rate achievable in ANY
% sel_nframes-length window across the whole recording (not just the window
% that ends up sampled), log it, and drop any session with zero spikes
% entirely (a session that never fires can never pass a firing-rate filter,
% and isn't worth generating a file for either way).
%
% Sessions are also tagged 'stim' or 'no_stim' (recorded in audit_summary for
% later plotting): for 'no_stim' recordings the max is taken over every
% window in the recording, same as before; for 'stim' recordings, windows
% that overlap ANY stimulation are excluded first, so the reported max
% reflects only stim-free windows (has_stim_free_window flags whether any
% such window exists at all).
run_firing_rate_audit = true; % set false to skip this pre-pass
audit_only = false; % set true to stop after the audit (no files generated)
if run_firing_rate_audit
    audit_dir = fullfile(path.save_dir, 'firing_rate_audit');
    if ~exist(audit_dir, 'dir'); mkdir(audit_dir); end
    audit_summary = struct('hash_id', {}, 'sess_id', {}, 'anim_id', {}, 'session_path', {}, ...
        'cell_id', {}, 'nframes', {}, 'total_spikes', {}, 'recording_type', {}, ...
        'has_stim_free_window', {}, 'max_firing_rate_hz', {}, 'avg_firing_rate_hz', {}, ...
        'best_window_start', {}, 'best_window_len', {}, 'sel_nframes', {}, 'has_spikes', {});
    fprintf('\n=== Auditing firing rates across %d session(s) (window length %d frames) ===\n', n_sessions, sel_nframes);
    keep_audit = false(1, n_sessions);
    for aud_i = 1:n_sessions
        path_to_sess = char(fullfile(total_sessions(aud_i).session_path));
        cell_id = total_sessions(aud_i).cell_id;
        hash_id = total_sessions(aud_i).cell_hash;
        sess_name = total_sessions(aud_i).session_name;
        sess_id_parts = strsplit(sess_name, '_');
        sess_id = sess_id_parts{1};

        nframes_sess = NaN; total_spikes = 0; max_rate = NaN; avg_rate = NaN; has_spikes = false;
        recording_type = 'no_stim'; has_stim_free_window = true;
        best_window_start = NaN; best_window_len = NaN;
        try
            fid = fopen(fullfile(path_to_sess, 'experimental_parameters.txt'), 'r');
            Info = textscan(fid, '%s');
            fclose(fid);
            ncol_a = str2double(Info{1}{6});
            nrow_a = str2double(Info{1}{3});
            % Frame count from file size (2 bytes/pixel, uint16), avoiding a
            % full read of the movie just to find its length.
            finfo = dir(fullfile(path_to_sess, target_file));
            nframes_sess = floor(finfo.bytes / (nrow_a * ncol_a * 2));

            % Determine whether this session has any stimulation at all,
            % exactly as the main generation loop does.
            matching_roots_aud = path.root.data(cellfun(@(r) startsWith(path_to_sess, r), path.root.data));
            if ~isempty(matching_roots_aud)
                [~, root_folder_name_aud] = fileparts(matching_roots_aud{1});
                is_btsp_aud = contains(root_folder_name_aud, 'BTSP', 'IgnoreCase', true);
            else
                is_btsp_aud = false;
            end
            is_stim_frame_aud = false(1, nframes_sess);
            try
                stim_protocol_aud = get_stim_protocol(path_to_sess, is_btsp_aud, 1);
                stim_trace_aud = stim_protocol_aud.trace;
                n_stim_aud = min(numel(stim_trace_aud), nframes_sess);
                is_stim_frame_aud(1:n_stim_aud) = stim_trace_aud(1:n_stim_aud) > stim_thresh;
            catch
                % no stim protocol found -- treat as unstimulated
            end
            if any(is_stim_frame_aud)
                recording_type = 'stim';
            end

            S = load(fullfile(path_to_sess, 'inter_spikeT_spikeW.mat'), 'C', 'dt');
            spikeT = S.C(cell_id).spikeT;
            if iscell(spikeT)
                if isempty(spikeT); spikeT = []; else; spikeT = spikeT{1}; end
            end
            spike_frames = double(spikeT(:));
            spike_frame_idx = round(spike_frames(spike_frames >= 1 & spike_frames <= nframes_sess));
            total_spikes = numel(spike_frame_idx);
            dt_sec = S.dt; % inter_spikeT_spikeW.mat's dt is already in seconds (e.g. 0.001 = 1ms/frame)
            if total_spikes > 0
                avg_rate = total_spikes / (nframes_sess * dt_sec); % average over the WHOLE recording
            end

            if total_spikes > 0 && nframes_sess >= sel_nframes
                spike_count_frame = accumarray(spike_frame_idx(:), 1, [nframes_sess, 1])';
                cum_spikes_aud = cumsum([0, spike_count_frame]);
                last_start_aud = nframes_sess - sel_nframes + 1;
                window_spike_count = cum_spikes_aud(sel_nframes+1:nframes_sess+1) - cum_spikes_aud(1:last_start_aud);
                if strcmp(recording_type, 'stim')
                    cum_stim_aud = cumsum([0, is_stim_frame_aud]);
                    window_stim_count_aud = cum_stim_aud(sel_nframes+1:nframes_sess+1) - cum_stim_aud(1:last_start_aud);
                    stim_free_mask = window_stim_count_aud == 0;
                    has_stim_free_window = any(stim_free_mask);
                    if has_stim_free_window
                        candidate_starts_aud = find(stim_free_mask);
                        [max_rate, bi] = max(window_spike_count(stim_free_mask) / (sel_nframes * dt_sec));
                        best_window_start = candidate_starts_aud(bi);
                        best_window_len = sel_nframes;
                    end
                else
                    [max_rate, best_window_start] = max(window_spike_count / (sel_nframes * dt_sec));
                    best_window_len = sel_nframes;
                end
                has_spikes = true;
            elseif total_spikes > 0
                % Recording shorter than sel_nframes: no window fits at all,
                % so there's no stim-free window either when stim is present.
                if strcmp(recording_type, 'stim')
                    has_stim_free_window = false;
                else
                    max_rate = total_spikes / (nframes_sess * dt_sec);
                    best_window_start = 1;
                    best_window_len = nframes_sess; % whole (short) recording, no sel_nframes window fits
                end
                has_spikes = true;
            end
        catch ME
            fprintf('Audit: could not evaluate %s cell %d (%s)\n', path_to_sess, cell_id, ME.message);
        end

        audit_summary(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, ... %#ok<SAGROW>
            'anim_id', total_sessions(aud_i).anim_id, 'session_path', path_to_sess, 'cell_id', cell_id, ...
            'nframes', nframes_sess, 'total_spikes', total_spikes, 'recording_type', recording_type, ...
            'has_stim_free_window', has_stim_free_window, 'max_firing_rate_hz', max_rate, ...
            'avg_firing_rate_hz', avg_rate, 'best_window_start', best_window_start, ...
            'best_window_len', best_window_len, 'sel_nframes', sel_nframes, 'has_spikes', has_spikes);
        if has_spikes
            if strcmp(recording_type, 'stim') && ~has_stim_free_window
                fprintf('  %s_%s cell %d [stim]: nframes=%d, total_spikes=%d, avg rate=%.3f Hz, NO stim-free %d-frame window exists\n', ...
                    hash_id, sess_id, cell_id, nframes_sess, total_spikes, avg_rate, sel_nframes);
            else
                fprintf('  %s_%s cell %d [%s]: nframes=%d, total_spikes=%d, avg rate=%.3f Hz, max rate over %d-frame windows=%.3f Hz\n', ...
                    hash_id, sess_id, cell_id, recording_type, nframes_sess, total_spikes, avg_rate, sel_nframes, max_rate);
            end
        else
            fprintf('  %s_%s cell %d [%s]: NO SPIKES -- excluding\n', hash_id, sess_id, cell_id, recording_type);
        end
        keep_audit(aud_i) = has_spikes;
    end
    save(fullfile(audit_dir, 'firing_rate_audit.mat'), 'audit_summary');
    fprintf('Audit: excluding %d/%d session(s) with no spikes (see %s).\n', ...
        sum(~keep_audit), n_sessions, audit_dir);
    total_sessions = total_sessions(keep_audit);
    n_sessions = length(total_sessions);
    if n_sessions == 0
        error('No sessions with spikes remain after firing-rate audit.');
    end
end

if audit_only
    fprintf('\naudit_only=true: stopping after the firing-rate audit, no files generated.\n');
    return;
end

%quality control!! (runs regardless of stim_mode)
qc_dir = fullfile(path.save_dir, 'stim_qc'); % per-session QC plots
if ~exist(qc_dir, 'dir'); mkdir(qc_dir); end
qc_summary = struct('hash_id', {}, 'sess_id', {}, 'had_stim_data', {}, 'had_trace_data', {}, ...
    'any_overlap', {}, 'starting_idx', {}, 'sel_nframes', {}, 'nframes', {}, ...
    'excluded', {}, 'firing_rate_hz', {});

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
        orig_nframes = nframes;
        cell_id = total_sessions(sess_i).cell_id;

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

        % Identify stimulated frames, if any. This is computed (and plotted)
        % for QC purposes regardless of stim_mode, but only *enforced* on
        % starting_idx selection when stim_mode is 'window_avoid' or
        % 'session_stim_free'.
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

        % 'session_stim_free' mode: skip the whole session (no dataset entry,
        % no QC plot, just a log entry) if it contains ANY stimulation, rather
        % than just avoiding stim within the sampled window.
        if strcmp(stim_mode, 'session_stim_free') && had_stim_data && any(is_stim_frame)
            fprintf('Skipping %s: contains stimulation (stim_mode=session_stim_free).\n', path_to_sess);
            qc_summary(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, ... %#ok<SAGROW>
                'had_stim_data', had_stim_data, 'had_trace_data', false, 'any_overlap', true, ...
                'starting_idx', NaN, 'sel_nframes', sel_nframes, 'nframes', nframes, ...
                'excluded', true, 'firing_rate_hz', NaN);
            continue;
        end

        % Load the raw (pre-denoising) fluorescence trace and spike times for
        % this cell. Spike times are used both for QC plotting and (if
        % min_firing_rate > 0) for filtering candidate windows below.
        raw_trace = [];
        spike_frames = [];
        had_trace_data = false;
        try
            trace_all = load(fullfile(path_to_sess, 'Masks_BestIcaTrace.mat'), 'IntensOrig').IntensOrig;
            raw_trace = double(trace_all(:, cell_id));
            % IntensOrig isn't guaranteed to be exactly nframes long (e.g. if
            % it was extracted from a differently-trimmed movie), so clip it
            % to whatever overlaps the current movie to keep x/y sizes matched.
            raw_trace = raw_trace(1:min(numel(raw_trace), nframes));
            had_trace_data = true;
        catch ME
            fprintf('No raw trace found for %s (%s); QC plot will omit the trace.\n', path_to_sess, ME.message);
        end
        had_spike_data = false;
        spike_dt_sec = NaN; % inter_spikeT_spikeW.mat's dt is already in seconds (e.g. 0.001 = 1ms/frame)
        try
            S = load(fullfile(path_to_sess, 'inter_spikeT_spikeW.mat'), 'C', 'dt');
            spikeT = S.C(cell_id).spikeT;
            if iscell(spikeT)
                if isempty(spikeT); spikeT = []; else; spikeT = spikeT{1}; end
            end
            spike_frames = double(spikeT(:));
            spike_dt_sec = S.dt;
            had_spike_data = true;
        catch ME
            fprintf('No spike times found for %s (%s); QC plot will omit spikes and firing-rate filtering is skipped.\n', path_to_sess, ME.message);
        end

        % Per-frame spike counts, used below to compute each candidate
        % window's firing rate via a cumulative-sum lookup (same trick as
        % the stim mask).
        spike_count_frame = zeros(1, nframes);
        if had_spike_data && ~isempty(spike_frames)
            spike_frame_idx = round(spike_frames(spike_frames >= 1 & spike_frames <= nframes));
            if ~isempty(spike_frame_idx)
                spike_count_frame = accumarray(spike_frame_idx(:), 1, [nframes, 1])';
            end
        end
        cum_spikes = cumsum([0, spike_count_frame]);

        % Candidate starting indices, before any firing-rate filtering.
        last_start = nframes - sel_nframes + 1;
        switch stim_mode
            case 'window_avoid'
                % A starting index is valid only if the whole
                % [start, start+sel_nframes-1] window falls entirely before the
                % next stim onset or after the previous stim offset (i.e.,
                % contains no stimulated frames at all)
                cum_stim = cumsum([0, is_stim_frame]);
                window_stim_count = cum_stim(sel_nframes+1:nframes+1) - cum_stim(1:last_start);
                candidate_starts = find(window_stim_count == 0);
                if isempty(candidate_starts)
                    fprintf('No stim-free window found for %s; sampling without stim restriction.\n', path_to_sess);
                    candidate_starts = 1:last_start;
                end
            otherwise
                % 'off', or 'session_stim_free' sessions that reached this point
                % (i.e. already confirmed to contain no stim at all)
                candidate_starts = 1:last_start;
        end

        % Optionally further restrict to windows meeting the minimum firing rate.
        if min_firing_rate > 0 && had_spike_data
            dt_sec = spike_dt_sec;
            window_spike_count = cum_spikes(candidate_starts + sel_nframes) - cum_spikes(candidate_starts);
            window_rate = window_spike_count / (sel_nframes * dt_sec);
            rate_ok = window_rate >= min_firing_rate;
            if any(rate_ok)
                candidate_starts = candidate_starts(rate_ok);
            else
                fprintf('No window meets min_firing_rate=%.3g Hz for %s; sampling without rate restriction.\n', ...
                    min_firing_rate, path_to_sess);
            end
        elseif min_firing_rate > 0
            fprintf('No spike data for %s; skipping firing-rate filtering for this session.\n', path_to_sess);
        end

        starting_idx = int16(candidate_starts(randi(numel(candidate_starts))));
        if had_spike_data
            win_spikes = cum_spikes(double(starting_idx)+sel_nframes) - cum_spikes(double(starting_idx));
            firing_rate_hz = win_spikes / (sel_nframes * spike_dt_sec);
        else
            firing_rate_hz = NaN;
        end

        % QC: plot the raw trace (with spikes) and/or stim mask, with the
        % stim regions and the sampled window both marked, and confirm
        % whether the sampled window overlaps any stimulation.
        window_range = double(starting_idx):double(starting_idx)+sel_nframes-1;
        any_overlap = any(is_stim_frame(window_range));
        fig = figure('Visible', 'off'); hold on;
        if had_trace_data
            y_lo = min(raw_trace); y_hi = max(raw_trace);
        else
            y_lo = -0.1; y_hi = 1.1;
        end
        pad = 0.05 * max(y_hi - y_lo, eps);
        y_lo = y_lo - pad; y_hi = y_hi + pad;

        stim_ranges = contiguous_true_ranges(is_stim_frame);
        h_stim = gobjects(0);
        for r = 1:size(stim_ranges, 1)
            h_stim(end+1) = patch([stim_ranges(r,1), stim_ranges(r,2), stim_ranges(r,2), stim_ranges(r,1)], ...
                [y_lo, y_lo, y_hi, y_hi], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none'); %#ok<AGROW>
        end
        h_window = patch([window_range(1), window_range(end), window_range(end), window_range(1)], ...
            [y_lo, y_lo, y_hi, y_hi], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');

        legend_handles = h_window; legend_labels = {'Sampled window'};
        if ~isempty(h_stim)
            legend_handles = [h_stim(1), legend_handles]; legend_labels = [{'Stim region'}, legend_labels];
        end

        if had_trace_data
            h_trace = plot(1:numel(raw_trace), raw_trace, 'k');
            legend_handles = [h_trace, legend_handles]; legend_labels = [{'Raw trace'}, legend_labels];
            if ~isempty(spike_frames)
                valid_sp = round(spike_frames(spike_frames >= 1 & spike_frames <= numel(raw_trace)));
                h_spike = plot(valid_sp, raw_trace(valid_sp), 'r.', 'MarkerSize', 10);
                legend_handles = [h_spike, legend_handles]; legend_labels = [{'Spikes'}, legend_labels];
            end
            ylabel('Raw fluorescence (a.u.)');
        else
            h_mask = stairs(1:orig_nframes, double(is_stim_frame) * (y_hi - pad) + pad, 'Color', [0.3 0.3 0.3]);
            legend_handles = [h_mask, legend_handles]; legend_labels = [{'Stim mask'}, legend_labels];
            ylabel('Stimulated (1) / Not (0)');
        end
        ylim([y_lo, y_hi]); xlim([1, orig_nframes]);
        xlabel('Frame');
        title_str = sprintf('%s\\_%s: window [%d-%d], stim data: %d, trace data: %d, overlap: %d, rate: %.2f Hz (min %.2f)', ...
            hash_id, sess_id, window_range(1), window_range(end), had_stim_data, had_trace_data, any_overlap, ...
            firing_rate_hz, min_firing_rate);
        title(title_str, 'Interpreter', 'none');
        legend(legend_handles, legend_labels, 'Location', 'best');
        saveas(fig, fullfile(qc_dir, sprintf('%s_%s_stimQC.png', hash_id, sess_id)));
        close(fig);

        qc_summary(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, ... %#ok<SAGROW>
            'had_stim_data', had_stim_data, 'had_trace_data', had_trace_data, 'any_overlap', any_overlap, ...
            'starting_idx', double(starting_idx), 'sel_nframes', sel_nframes, 'nframes', orig_nframes, ...
            'excluded', false, 'firing_rate_hz', firing_rate_hz);
        if any_overlap
            fprintf('WARNING: sampled window for %s overlaps stimulation frames!\n', path_to_sess);
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
if ~isempty(qc_summary)
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
function day = session_day(session_path, anim_id)
% Returns the date folder name in session_path, i.e. the path segment
% immediately following anim_id (root/anim_id/day/slice.../FOV.../sess_name).
rest = extractAfter(session_path, [filesep anim_id filesep]);
parts = strsplit(rest, filesep);
day = parts{1};
end

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

function ranges = contiguous_true_ranges(mask)
% Returns an Nx2 array of [start, end] frame indices for each contiguous
% run of true values in a logical row vector mask.
d = diff([0, mask(:)', 0]);
starts = find(d == 1);
ends = find(d == -1) - 1;
ranges = [starts(:), ends(:)];
end
