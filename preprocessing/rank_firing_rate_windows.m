function rank_firing_rate_windows(root_dirs, cell_type, nv)
%RANK_FIRING_RATE_WINDOWS  Step 1 of manual window selection: rank candidate
% windows by firing rate ACROSS all recordings, producing a candidate list
% for review_firing_rate_windows.m to step through. Replaces "one max-rate
% window per recording" (firing_rate_audit_headless.m) with a global ranking
% where each recording can contribute several non-overlapping windows.
%
% For each session/cell:
%   - every window_len-frame window is scored by its spike rate (Hz);
%   - the best window is taken, then the next best that doesn't overlap it,
%     and so on, up to max_windows_per_recording (windows with too few spikes
%     are dropped);
%   - the recording's whole-trace average rate (avg_firing_rate_hz) is
%     recorded on every row alongside each window's own rate.
% All windows from all recordings are then sorted by window rate (rank 1 =
% highest). The number of windows you actually need is
%       n_windows_target = floor(target_frames / window_len)
% and you pick them by reviewing the list with review_firing_rate_windows.m;
% the ranked list is deliberately longer than that so rejected windows can be
% replaced.
%
% No movie is read (nframes from the movReg.bin file size, spikes from
% inter_spikeT_spikeW.mat), so this is cheap over many sessions.
%
%   rank_firing_rate_windows(root_dirs, cell_type, window_len=10000)
%   rank_firing_rate_windows(root_dirs, cell_type, window_len=10000, max_windows_per_recording=3)
%
%   root_dirs, cell_type, sel_sessions, anim_prefixes, discover_exclude,
%   save_str, use_cache, stim_thresh: same meaning as in
%   firing_rate_audit_headless.m (same cached session list is reused).
%
% Name-value options:
%   window_len      frames per window. Default 1000.
%   target_frames   total frames wanted in the dataset. Default 300000.
%   max_windows_per_recording  cap on windows taken from any one recording.
%                   Default 3.
%   min_window_spikes  windows need at least this many spikes. Default 1.
%   stim_mode       'window_avoid' (default; windows containing any stim
%                   frame are excluded), 'off' (stim ignored), or
%                   'session_stim_free' (recordings with any stim skipped).
%
% Outputs in SUPPORT-denoising/datasets/<cell_type>/<save_str>/window_selection/:
%   window_candidates.mat   `candidates` (struct array, one row per window,
%                           sorted by rank) and `params`
%   window_candidates.csv   same, as a table
% Existing review decisions (window_selection.mat) are not touched here, but
% re-ranking changes the list, so use a fresh save_str if you've already
% started reviewing.
arguments
    root_dirs cell
    cell_type {mustBeTextScalar}
    nv.window_len (1,1) double {mustBePositive, mustBeInteger} = 1000
    nv.target_frames (1,1) double = 300000
    nv.max_windows_per_recording (1,1) double {mustBePositive, mustBeInteger} = 3
    nv.min_window_spikes (1,1) double = 1
    nv.stim_mode {mustBeTextScalar} = "window_avoid"
    nv.sel_sessions cell = {}
    nv.invert_sel_sessions (1,1) logical = false
    nv.anim_prefixes cell = {'ipsp', 'fos', 'cck'}
    nv.discover_exclude cell = {}
    nv.save_str {mustBeTextScalar} = ""
    nv.use_cache (1,1) logical = true
    nv.stim_thresh (1,1) double = 0.1
end

stim_mode = char(nv.stim_mode);
if ~ismember(stim_mode, {'off', 'window_avoid', 'session_stim_free'})
    error('stim_mode must be one of: off, window_avoid, session_stim_free');
end

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
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing')); % needed by get_stim_protocol

%% paths
root_data = resolve_root_dirs(root_path, root_dirs);
path_cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));
saveStr = char(nv.save_str);
save_dir = fullfile(path_cell_type, saveStr);
out_dir = fullfile(save_dir, 'window_selection');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

%% sessions (discover, or load cache) -- same as firing_rate_audit_headless.m
sessions_mat = fullfile(path_cell_type, sprintf("total_sessions_%s.mat", saveStr));
if nv.use_cache && isfile(sessions_mat)
    load(sessions_mat, 'total_sessions');
    total_sessions = convert_struct_paths(total_sessions, root_path);
    fprintf('Loaded %d cached session(s) from %s\n', numel(total_sessions), sessions_mat);
else
    total_sessions = struct([]);
    for root_i = 1:numel(root_data)
        for p = 1:numel(nv.anim_prefixes)
            new_sessions = discover_sessions(root_data{root_i}, nv.anim_prefixes{p}, '', ...
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

%% rank windows
window_len = nv.window_len;
n_windows_target = floor(nv.target_frames / window_len);
n_sessions = numel(total_sessions);
fprintf('\n=== Ranking windows: %d session(s), window_len=%d, up to %d/recording, target %d window(s) (%d frames) ===\n', ...
    n_sessions, window_len, nv.max_windows_per_recording, n_windows_target, n_windows_target * window_len);

cand_template = struct('rank', NaN, 'hash_id', '', 'sess_id', '', 'session_name', '', 'anim_id', '', ...
    'session_path', '', 'cell_id', NaN, 'recording_type', '', 'nframes', NaN, ...
    'start', NaN, 'len', window_len, 'window_firing_rate_hz', NaN, 'window_spikes', NaN, ...
    'avg_firing_rate_hz', NaN, 'total_spikes', NaN, 'rank_in_recording', NaN, 'status', 'pending');
candidates = repmat(cand_template, 0, 1);

for si = 1:n_sessions
    path_to_sess = char(total_sessions(si).session_path);
    cell_id = total_sessions(si).cell_id;
    hash_id = total_sessions(si).cell_hash;
    sess_parts = strsplit(total_sessions(si).session_name, '_');
    sess_id = sess_parts{1};
    try
        fid = fopen(fullfile(path_to_sess, 'experimental_parameters.txt'), 'r');
        Info = textscan(fid, '%s');
        fclose(fid);
        ncol_a = str2double(Info{1}{6});
        nrow_a = str2double(Info{1}{3});
        finfo = dir(fullfile(path_to_sess, 'movReg.bin'));
        nframes = floor(finfo.bytes / (nrow_a * ncol_a * 2)); % uint16 -> 2 bytes/pixel

        if nframes < window_len
            fprintf('  %s_%s cell %d: only %d frames (< window_len), skipping\n', hash_id, sess_id, cell_id, nframes);
            continue
        end

        % stim detection, same heuristic as the audit/generation scripts
        matching_roots = root_data(cellfun(@(r) startsWith(path_to_sess, r), root_data));
        is_btsp = false;
        if ~isempty(matching_roots)
            [~, root_folder_name] = fileparts(matching_roots{1});
            is_btsp = contains(root_folder_name, 'BTSP', 'IgnoreCase', true);
        end
        is_stim_frame = false(1, nframes);
        try
            sp_protocol = get_stim_protocol(path_to_sess, is_btsp, 1);
            k = min(numel(sp_protocol.trace), nframes);
            is_stim_frame(1:k) = sp_protocol.trace(1:k) > nv.stim_thresh;
        catch
            % no stim protocol -- treat as unstimulated
        end
        recording_type = 'no_stim';
        if any(is_stim_frame); recording_type = 'stim'; end
        if strcmp(stim_mode, 'session_stim_free') && strcmp(recording_type, 'stim')
            fprintf('  %s_%s cell %d: contains stim (stim_mode=session_stim_free), skipping\n', hash_id, sess_id, cell_id);
            continue
        end

        S = load(fullfile(path_to_sess, 'inter_spikeT_spikeW.mat'), 'C', 'dt');
        spikeT = S.C(cell_id).spikeT;
        if iscell(spikeT)
            if isempty(spikeT); spikeT = []; else; spikeT = spikeT{1}; end
        end
        spike_frames = double(spikeT(:));
        spike_idx = round(spike_frames(spike_frames >= 1 & spike_frames <= nframes));
        total_spikes = numel(spike_idx);
        if total_spikes == 0
            fprintf('  %s_%s cell %d: NO SPIKES, skipping\n', hash_id, sess_id, cell_id);
            continue
        end
        dt_sec = S.dt; % seconds per frame (e.g. 0.001), same convention as the audit
        avg_rate = total_spikes / (nframes * dt_sec);

        % window spike counts for every start via cumulative sum
        cum_spikes = cumsum([0, accumarray(spike_idx(:), 1, [nframes, 1])']);
        last_start = nframes - window_len + 1;
        win_spikes = cum_spikes(window_len+1:nframes+1) - cum_spikes(1:last_start);
        score = win_spikes / (window_len * dt_sec);
        if strcmp(stim_mode, 'window_avoid')
            cum_stim = cumsum([0, is_stim_frame]);
            win_stim = cum_stim(window_len+1:nframes+1) - cum_stim(1:last_start);
            score(win_stim > 0) = -inf;
        end
        score(win_spikes < nv.min_window_spikes) = -inf;

        % greedy non-overlapping picks
        n_picked = 0;
        while n_picked < nv.max_windows_per_recording
            [best, bi] = max(score);
            if ~isfinite(best); break; end
            n_picked = n_picked + 1;
            c = cand_template;
            c.hash_id = hash_id; c.sess_id = sess_id; c.session_name = total_sessions(si).session_name;
            c.anim_id = total_sessions(si).anim_id; c.session_path = path_to_sess; c.cell_id = cell_id;
            c.recording_type = recording_type; c.nframes = nframes;
            c.start = bi; c.len = window_len; c.window_firing_rate_hz = best;
            c.window_spikes = win_spikes(bi); c.avg_firing_rate_hz = avg_rate;
            c.total_spikes = total_spikes; c.rank_in_recording = n_picked;
            candidates(end+1, 1) = c; %#ok<AGROW>
            % starts closer than window_len would overlap this window
            score(max(1, bi - window_len + 1):min(last_start, bi + window_len - 1)) = -inf;
        end
        if n_picked == 0
            fprintf('  %s_%s cell %d [%s]: avg %.3f Hz, no usable window\n', hash_id, sess_id, cell_id, recording_type, avg_rate);
        else
            fprintf('  %s_%s cell %d [%s]: avg %.3f Hz, %d window(s), best %.3f Hz\n', ...
                hash_id, sess_id, cell_id, recording_type, avg_rate, n_picked, candidates(end - n_picked + 1).window_firing_rate_hz);
        end
    catch ME
        fprintf('  could not evaluate %s cell %d (%s)\n', path_to_sess, cell_id, ME.message);
    end
end

if isempty(candidates)
    error('No usable windows found.');
end
[~, order] = sort([candidates.window_firing_rate_hz], 'descend');
candidates = candidates(order);
for i = 1:numel(candidates)
    candidates(i).rank = i;
end

params = struct('window_len', window_len, 'target_frames', nv.target_frames, ...
    'n_windows_target', n_windows_target, 'max_windows_per_recording', nv.max_windows_per_recording, ...
    'min_window_spikes', nv.min_window_spikes, 'stim_mode', stim_mode, 'stim_thresh', nv.stim_thresh, ...
    'cell_type', char(cell_type), 'save_str', saveStr); %#ok<NASGU>
save(fullfile(out_dir, 'window_candidates.mat'), 'candidates', 'params');
writetable(struct2table(candidates), fullfile(out_dir, 'window_candidates.csv'));
fprintf('\nRanked %d window(s) from %d recording(s); need %d. Saved to %s\n', ...
    numel(candidates), numel(unique(string({candidates.session_path}) + "|" + string([candidates.cell_id]))), ...
    n_windows_target, out_dir);
fprintf('Next: review_firing_rate_windows(''%s'')\n', out_dir);
end

function roots = resolve_root_dirs(root_path, root_dirs)
roots = root_dirs;
if ischar(roots); roots = {roots}; end
if isstring(roots); roots = cellstr(roots); end
for r = 1:numel(roots)
    if ~is_absolute_path(roots{r})
        roots{r} = fullfile(root_path, roots{r});
    end
end
end
