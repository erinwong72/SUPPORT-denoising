function firing_rate_audit_headless(root_dirs, cell_type, nv)
%FIRING_RATE_AUDIT_HEADLESS  Audit firing rates across candidate sessions,
% before generating anything or picking a min_firing_rate cutoff. Extracted
% out of dataset_generation_headless.m, which now assumes you've already run
% this (and psnr_audit_headless.m), picked your cutoffs, and no longer runs
% any audit itself.
%
% For each candidate session/cell, finds:
%   - max_firing_rate_hz: the max spike rate achievable in ANY
%     sel_nframes-length window across the whole recording, where
%     sel_nframes = ceil(target_frames/n_sessions), same as
%     dataset_generation_headless.m would use. For 'stim' recordings, windows
%     that overlap ANY stimulation are excluded first, so this reflects only
%     stim-free windows (NaN if none exist).
%   - avg_firing_rate_hz: the simple whole-recording average rate.
% Sessions are tagged 'stim'/'no_stim' and sessions with zero spikes are
% excluded entirely (a session that never fires can't pass any firing-rate
% filter and isn't worth generating a file for either way).
%
% No movie is read -- nframes comes from the movReg.bin file size and spikes
% from inter_spikeT_spikeW.mat -- so this is cheap even over many sessions.
%
% Automatically plots the results via plot_firing_rate_audit.m when done
% (distribution histograms/CDFs + a best-of-each-metric trace sanity check).
%
%   firing_rate_audit_headless(root_dirs, cell_type)
%   firing_rate_audit_headless(root_dirs, cell_type, target_frames=300000)
%
%   root_dirs   cellstr of parent folders to search for sessions, same as
%               dataset_generation_headless.m.
%   cell_type   dataset name. Reuses/creates
%               SUPPORT-denoising/datasets/<cell_type>/total_sessions_<save_str>.mat,
%               so running this against the same cell_type you'll later call
%               dataset_generation_headless.m with audits exactly the same
%               candidate session list.
%
% Name-value options (all optional):
%   window_len      frames. Window length to extract/audit (for
%                   max_firing_rate_hz). Default 0 = derive it from
%                   target_frames (below). Set this to use an exact length.
%   target_frames   total frames to sample across the whole dataset; when
%                   window_len=0, each session's window length is
%                   ceil(target_frames/n_sessions). Default 300000 -- match
%                   whatever you intend to pass dataset_generation_headless.m.
%   sel_sessions    cell array of structs restricting the audit to specific
%                   animal/day/FOV/cell combinations -- see
%                   filterSessionsBySelector.m. Default {} (every session found).
%   invert_sel_sessions  logical, default false. When true, audit everything
%                   EXCEPT what sel_sessions matches.
%   anim_prefixes   cellstr of animal-ID prefixes to discover under
%                   root_dirs. Default {'ipsp','fos','cck'}.
%   discover_exclude  cellstr of substrings; any folder containing one is
%                   skipped during discovery. Default {}.
%   save_str        char/string suffix for the cell_type dir/mat filenames,
%                   matching saveStr in dataset_generation.m. Default "".
%   use_cache       logical, default true: reuse an existing
%                   total_sessions_<save_str>.mat instead of rediscovering.
%   stim_thresh     double, matches get_stim_protocol default. Default 0.1.
%
% Outputs land in SUPPORT-denoising/datasets/<cell_type>/<save_str>/firing_rate_audit/:
%   firing_rate_audit.mat   struct array `audit_summary`, one row per cell:
%                            hash_id, sess_id, anim_id, session_path, cell_id,
%                            nframes, total_spikes, recording_type,
%                            has_stim_free_window, max_firing_rate_hz,
%                            avg_firing_rate_hz, best_window_start,
%                            best_window_len, sel_nframes, has_spikes
%   firing_rate_audit.csv   same, as a table, for a quick look outside MATLAB
%   firing_rate_distribution.png       histograms + ECDFs, split by
%                            recording_type, annotated with the window length
%   firing_rate_best_avg_trace.png     sanity check: trace for the highest
%                            avg_firing_rate_hz cell, whole recording shaded
%   firing_rate_best_max_trace.png     sanity check: trace for the highest
%                            max_firing_rate_hz cell, its best window shaded
arguments
    root_dirs cell
    cell_type {mustBeTextScalar}
    nv.window_len (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    nv.target_frames (1,1) double = 300000
    nv.sel_sessions cell = {}
    nv.invert_sel_sessions (1,1) logical = false
    nv.anim_prefixes cell = {'ipsp', 'fos', 'cck'}
    nv.discover_exclude cell = {}
    nv.save_str {mustBeTextScalar} = ""
    nv.use_cache (1,1) logical = true
    nv.stim_thresh (1,1) double = 0.1
end
rng(123);

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
safe_addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing')); % ReadBinWaveFormsV1.m etc., needed by get_stim_protocol

%% paths
path = struct();
path.root.data = resolve_root_dirs(root_path, root_dirs);
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));
saveStr = char(nv.save_str);
path.save_dir = fullfile(path.cell_type, saveStr);
stim_thresh = nv.stim_thresh;
if ~exist(path.save_dir, 'dir'); mkdir(path.save_dir); end

%% setup sessions structure (discover, or load cache) -- same as dataset_generation_headless.m
sessions_mat = fullfile(path.cell_type, sprintf("total_sessions_%s.mat", saveStr));
if nv.use_cache && isfile(sessions_mat)
    load(sessions_mat, 'total_sessions');
    total_sessions = convert_struct_paths(total_sessions, root_path);
    fprintf('Loaded %d cached session(s) from %s\n', numel(total_sessions), sessions_mat);
else
    total_sessions = struct([]);
    for root_i = 1:numel(path.root.data)
        for p = 1:numel(nv.anim_prefixes)
            new_sessions = discover_sessions(path.root.data{root_i}, nv.anim_prefixes{p}, '', ...
                struct(), nv.discover_exclude, true, true);
            total_sessions = [total_sessions, new_sessions]; %#ok<AGROW>
        end
    end
    if isempty(total_sessions)
        error('No recordings with inter_spikeT_spikeW.mat found under root_dirs');
    end
    keep_fields = {'anim_id','session_path','session_name','slice','FOV', ...
                   'cell_id','fov_num_cells','cell_hash'};
    total_sessions = rmfield(total_sessions, setdiff(fieldnames(total_sessions), keep_fields));
    total_sessions = convert_struct_paths(total_sessions, root_path);

    cell_keys = arrayfun(@(s) sprintf('%s|%s|%d', s.anim_id, ...
        extractAfter(s.session_path, [filesep s.anim_id filesep]), s.cell_id), ...
        total_sessions, 'UniformOutput', false);
    [~, unique_idx] = unique(cell_keys, 'stable');
    total_sessions = total_sessions(unique_idx);

    valid_paths = arrayfun(@(s) isfolder(s.session_path), total_sessions);
    total_sessions = total_sessions(valid_paths);
    save(sessions_mat, 'total_sessions');
    fprintf('Discovered %d session(s), cached to %s\n', numel(total_sessions), sessions_mat);
end

if ~isempty(nv.sel_sessions)
    total_sessions = filterSessionsBySelector(total_sessions, nv.sel_sessions, nv.invert_sel_sessions);
end

target_file = 'movReg.bin';
n_sessions = numel(total_sessions);
if nv.window_len > 0
    sel_nframes = nv.window_len;
else
    sel_nframes = ceil(nv.target_frames / n_sessions);
end

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

        % Determine whether this session has any stimulation at all, same
        % heuristic as dataset_generation*.m: the project folder name (not
        % the shared "DSI-BTSP" parent) contains "BTSP" or not.
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
writetable(struct2table(audit_summary), fullfile(audit_dir, 'firing_rate_audit.csv'));
fprintf('Firing-rate audit: %d/%d session(s) have spikes (see %s).\n', ...
    sum(keep_audit), n_sessions, audit_dir);

%% Plot the results (distribution + best-of-each-metric trace sanity check)
plot_firing_rate_audit(audit_dir);
end

function roots = resolve_root_dirs(root_path, root_dirs)
% Absolute paths pass through; relative ones resolve under the fanlab root.
roots = root_dirs;
if ischar(roots); roots = {roots}; end
if isstring(roots); roots = cellstr(roots); end
for r = 1:numel(roots)
    if ~is_absolute_path(roots{r})
        roots{r} = fullfile(root_path, roots{r});
    end
end
end
