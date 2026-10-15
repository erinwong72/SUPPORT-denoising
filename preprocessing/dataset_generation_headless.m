function dataset_generation_headless(root_dirs, cell_type, nv)
%DATASET_GENERATION_HEADLESS  Unattended dataset generation, safe to call
% via `matlab -batch` over SSH. Headless equivalent of dataset_generation.m:
% same session discovery / sampling / masking logic, parameterized instead
% of edited by hand, and with the interactive `imshow` preview at the end
% dropped (there's no display to show it on).
%
% Run this ONLY after you've picked your stim_mode / min_firing_rate cutoffs
% from psnr_audit_headless.m and firing_rate_audit_headless.m -- this script
% no longer runs any audit itself (that used to live here; it's been pulled
% out into firing_rate_audit_headless.m, routed through the same
% run_headless_audit.sh launcher as the PSNR audit). Use sel_sessions here to
% restrict generation to whatever the audits said was worth keeping.
%
%   dataset_generation_headless(root_dirs, cell_type)
%   dataset_generation_headless(root_dirs, cell_type, stim_mode='window_avoid')
%
%   root_dirs   cellstr of parent folders to search for sessions (same
%               discover_sessions-based discovery as preprocessing_headless.m).
%               Absolute paths (e.g. /mnt/fanlab/... or Z:\...), or paths
%               relative to the fanlab root.
%               e.g. {'Data and Analysis/DSI-BTSP/optoCCKBC-activation_BTSP'}
%   cell_type   dataset name. Output goes to
%               SUPPORT-denoising/datasets/<cell_type>/, matching
%               path.cell_type in dataset_generation.m.
%
% Name-value options (all optional):
%   stim_mode       char/string, one of:
%                     'off'               - no stim filtering; sample
%                                            anywhere in the session (default)
%                     'window_avoid'      - sample a sel_nframes window that
%                                            avoids all stim periods within
%                                            the session (falls back to 'off'
%                                            if no such window exists)
%                     'session_stim_free' - only use sessions with NO
%                                            stimulation anywhere; sessions
%                                            containing any stim are skipped
%                                            entirely (not just avoided
%                                            within-window)
%                   Per-session QC plots to <cell_type>/stim_qc/ are saved
%                   regardless of stim_mode.
%   filter_stim     logical, deprecated alias for stim_mode: true maps to
%                   'window_avoid', false (default) to 'off'. Ignored if
%                   stim_mode is also given.
%   min_firing_rate double, Hz. Minimum spike rate (computed from
%                   inter_spikeT_spikeW.mat spike times) required within the
%                   sampled window; windows below threshold are rejected in
%                   favor of ones that pass, when any exist. Default 0 (no
%                   firing-rate filtering).
%   anim_prefixes   cellstr of animal-ID prefixes to discover under
%                   root_dirs. Default {'ipsp','fos','cck'}.
%   discover_exclude  cellstr of substrings; any folder containing one is
%                   skipped during discovery. Default {}.
%   stim_thresh     double. Matches get_stim_protocol default. Default 0.1.
%   save_str        char/string suffix appended to the cell_type dir and
%                   mat filenames, mirroring saveStr in
%                   dataset_generation.m (e.g. "minSNR_10"). Default "".
%   target_frames   total frames to sample across the whole dataset; each
%                   session's window length is ceil(target_frames/n_sessions).
%                   Default 300000.
%   use_cache       logical. When true (default) and
%                   total_sessions<save_str>.mat already exists under
%                   SUPPORT-denoising/datasets/<cell_type>/, load it instead
%                   of rediscovering sessions from root_dirs.
%   sel_sessions    cell array of structs restricting dataset generation to
%                   specific animal/day/FOV/cell combinations, matching
%                   path.sel_sessions in dataset_generation.m. Each struct
%                   may have any subset of anim_id/day/FOV/cell_id; an
%                   omitted/empty field matches any value for that field,
%                   and entries are OR'd together. "day" matches the date
%                   folder name in session_path (the segment immediately
%                   after anim_id). Default {} (use every session found).
%                   e.g.
%                   {struct('anim_id','cck-ipsp-btsp-w25','day','2026-03-15_VR_V_Blue_inhDSI','FOV',3,'cell_id',2), ...
%                    struct('anim_id','cck-ipsp-btsp-w27','day','2026-03-12_VR_V_Blue_inhDSI','FOV',6,'cell_id',1), ...
%                    struct('anim_id','cck-ipsp-btsp-w27','day','2026-03-12_VR_V_Blue_inhDSI','FOV',6,'cell_id',2)}
%                   See filterSessionsBySelector.m.
%   filtered_sessions_mat  char path. When sel_sessions is non-empty, the
%                   restricted session list is ALSO saved here (separate
%                   from total_sessions_<save_str>.mat, which always keeps
%                   the full discovered/cached set so a later call with
%                   different sel_sessions isn't filtering an
%                   already-filtered set). Point preprocessing_headless.m's
%                   sessions_cache_mat + use_cache=true at this file to
%                   reuse the restricted list without re-filtering.
%                   Default: total_sessions_<save_str>_filtered.mat under
%                   the cell_type dir (only written when sel_sessions is
%                   non-empty).
%
%   window_selection_file  char path to window_selection.mat written by
%                   review_firing_rate_windows.m. When given, ONLY the
%                   hand-accepted windows are generated (several per
%                   recording are possible, each window_len frames long), and
%                   stim_mode / min_firing_rate / sel_sessions / target_frames
%                   are ignored -- the selection already encodes them. Files
%                   are named <cell_hash>_<sess_id>_w<start>.tiff. A QC plot per
%                   recording (whole raw trace, spikes, stim regions, and the
%                   selected windows highlighted) is saved to stim_qc/ as
%                   <cell_hash>_<sess_id>_selectedwindows_QC.png.
%   qc_only         logical, default false. Requires window_selection_file.
%                   Makes only the QC plots + stim_qc_summary.mat for the
%                   selected windows: no movie is read and no tiffs are
%                   written (so it's quick). Re-run without qc_only to
%                   generate the tiffs.
%
% Outputs land in SUPPORT-denoising/datasets/<cell_type>/<save_str>/:
%   total_sessions_<save_str>.mat   discovered/cached session list
%   total_sessions_<save_str>_filtered.mat  sel_sessions-restricted list
%                                    (only when sel_sessions is non-empty)
%   <cell_hash>_<sess_id>.tiff      one masked-movie sample per cell
%   stim_qc/                        per-session QC plots (always saved)
arguments
    root_dirs cell
    cell_type {mustBeTextScalar}
    nv.filter_stim (1,1) logical = false
    nv.stim_mode {mustBeTextScalar} = ""
    nv.min_firing_rate (1,1) double = 0
    nv.anim_prefixes cell = {'ipsp', 'fos', 'cck'}
    nv.discover_exclude cell = {}
    nv.stim_thresh (1,1) double = 0.1
    nv.save_str {mustBeTextScalar} = ""
    nv.target_frames (1,1) double = 300000
    nv.use_cache (1,1) logical = true
    nv.sel_sessions cell = {}
    nv.filtered_sessions_mat {mustBeTextScalar} = ""
    nv.window_selection_file {mustBeTextScalar} = ""
    nv.qc_only (1,1) logical = false
end
rng(123);

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end

tinkering = 1;
if ~tinkering
    code_path = fullfile(root_path, 'Computer Code');
else
    code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
end
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
safe_addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));

%% paths
path = struct();
path.root.data = resolve_root_dirs(root_path, root_dirs);
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));
saveStr = char(nv.save_str);
path.save_dir = fullfile(path.cell_type, saveStr);
stim_thresh = nv.stim_thresh;
min_firing_rate = nv.min_firing_rate;
nv.window_selection_file = fullfile(path.save_dir, 'window_selection', nv.window_selection_file);

valid_stim_modes = {'off', 'window_avoid', 'session_stim_free'};
if strlength(string(nv.stim_mode)) > 0
    stim_mode = char(nv.stim_mode);
    if ~ismember(stim_mode, valid_stim_modes)
        error('stim_mode must be one of: %s', strjoin(valid_stim_modes, ', '));
    end
elseif nv.filter_stim
    stim_mode = 'window_avoid'; % back-compat: filter_stim=true
else
    stim_mode = 'off'; % back-compat: filter_stim=false (default)
end

if ~exist(path.save_dir, 'dir'); mkdir(path.save_dir); end

%% setup sessions structure (discover, or load cache)
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

    % keep cells with unique animal/date/slice/FOV/recording, even across project roots
    cell_keys = arrayfun(@(s) sprintf('%s|%s|%d', s.anim_id, ...
        extractAfter(s.session_path, [filesep s.anim_id filesep]), s.cell_id), ...
        total_sessions, 'UniformOutput', false);
    [~, unique_idx] = unique(cell_keys, 'stable');
    total_sessions = total_sessions(unique_idx);

    % make sure each session_path exists
    valid_paths = arrayfun(@(s) isfolder(s.session_path), total_sessions);
    total_sessions = total_sessions(valid_paths);
    save(sessions_mat, 'total_sessions');
    fprintf('Discovered %d session(s), cached to %s\n', numel(total_sessions), sessions_mat);
end

%% restrict to specific animal/day/FOV/cell combinations, if requested
if ~isempty(nv.sel_sessions)
    total_sessions = filterSessionsBySelector(total_sessions, nv.sel_sessions);

    filtered_mat = char(nv.filtered_sessions_mat);
    if isempty(filtered_mat)
        filtered_mat = fullfile(path.cell_type, sprintf("total_sessions_%s_filtered.mat", saveStr));
    end
    filtered_dir = fileparts(filtered_mat);
    if ~isempty(filtered_dir) && ~isfolder(filtered_dir); mkdir(filtered_dir); end
    save(filtered_mat, 'total_sessions');
    fprintf('Saved %d sel_sessions-filtered session(s) to %s\n', numel(total_sessions), filtered_mat);
end

%% hand-selected windows (review_firing_rate_windows.m), if requested
use_selection = strlength(string(nv.window_selection_file)) > 0;
if use_selection
    W = load(char(nv.window_selection_file), 'selected_windows');
    sel_windows = convert_struct_paths(W.selected_windows, root_path);
    if isempty(sel_windows); error('No accepted windows in %s', nv.window_selection_file); end
    sel_keys = string({sel_windows.session_path}) + "|" + string([sel_windows.cell_id]);
    [~, first_idx, sel_grp] = unique(sel_keys, 'stable');
    sel_rec_idx = accumarray(sel_grp(:), (1:numel(sel_windows))', [], @(v) {v});
    fi = sel_windows(first_idx);
    total_sessions = struct('anim_id', {fi.anim_id}, 'session_path', {fi.session_path}, ...
        'session_name', {fi.session_name}, 'cell_id', {fi.cell_id}, 'cell_hash', {fi.hash_id});
    fprintf('Using %d hand-selected window(s) across %d recording(s) from %s\n', ...
        numel(sel_windows), numel(total_sessions), nv.window_selection_file);
end

if nv.qc_only && ~use_selection
    error('qc_only currently needs window_selection_file (QC of the hand-selected windows).');
end

%% Saving samples of masked recordings
target_file = 'movReg.bin';
n_sessions = length(total_sessions);
sel_nframes = ceil(nv.target_frames / n_sessions);

% QC (runs regardless of stim_mode)
qc_dir = fullfile(path.save_dir, 'stim_qc');
if ~exist(qc_dir, 'dir'); mkdir(qc_dir); end
qc_summary = struct('hash_id', {}, 'sess_id', {}, 'had_stim_data', {}, 'had_trace_data', {}, ...
    'any_overlap', {}, 'starting_idx', {}, 'sel_nframes', {}, 'nframes', {}, ...
    'excluded', {}, 'firing_rate_hz', {});

fprintf('\n=== Headless dataset generation: cell_type=%s stim_mode=%s min_firing_rate=%.3g n_sessions=%d sel_nframes=%d ===\n', ...
    cell_type, stim_mode, min_firing_rate, n_sessions, sel_nframes);

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
    if use_selection
        wins_i = sel_windows(sel_rec_idx{sess_i});
        try
            qc_rows = qc_selected_windows(path_to_sess, total_sessions(sess_i), wins_i, qc_dir, ...
                path.root.data, stim_thresh, sess_i, n_sessions);
            qc_summary = [qc_summary(:); qc_rows(:)]';
        catch ME
            fprintf('  QC failed for %s_%s (%s)\n', hash_id, sess_id, ME.message);
        end
        if ~nv.qc_only
            save_selected_windows(path_to_sess, total_sessions(sess_i), wins_i, ...
                path.save_dir, target_file, sess_i, n_sessions);
        end
        continue
    end
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

        starting_idx = candidate_starts(randi(numel(candidate_starts))); % double: int16 saturates at 32767
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
        mov2 = mov_part - repmat(reshape(sbkg,[1,1,nframes]),[nrow, ncol,1]); %#ok<NASGU>

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
        fprintf('  [%d/%d] saved %s\n', sess_i, n_sessions, file_path);
    else
        fprintf('  [%d/%d] skipping saved file: %s\n', sess_i, n_sessions, file_path);
    end
end
if ~isempty(qc_summary)
    save(fullfile(qc_dir, 'stim_qc_summary.mat'), 'qc_summary');
    n_overlap = sum([qc_summary.any_overlap]);
    fprintf('Stim QC: %d/%d sampled windows overlap stimulation (see %s).\n', ...
        n_overlap, numel(qc_summary), qc_dir);
end
fprintf('\nHeadless dataset generation done: %s\n', path.save_dir);
end

function qc_rows = qc_selected_windows(path_to_sess, sess, wins, qc_dir, root_data, stim_thresh, sess_i, n_sessions)
% QC for the hand-selected windows of one recording, without reading the
% movie: whole raw trace + spikes + stim regions, with each selected window
% shaded green, plus a per-window stim-overlap check. One PNG per recording.
hash_id = sess.cell_hash;
parts = strsplit(sess.session_name, '_');
sess_id = parts{1};
cell_id = sess.cell_id;
nframes = double(wins(1).nframes);

matching_roots = root_data(cellfun(@(r) startsWith(path_to_sess, r), root_data));
is_btsp = false;
if ~isempty(matching_roots)
    [~, root_folder_name] = fileparts(matching_roots{1});
    is_btsp = contains(root_folder_name, 'BTSP', 'IgnoreCase', true);
end
is_stim_frame = false(1, nframes);
had_stim_data = false;
try
    stim_protocol = get_stim_protocol(path_to_sess, is_btsp, 1);
    stim_trace = stim_protocol.trace;
    n_stim = min(numel(stim_trace), nframes);
    is_stim_frame(1:n_stim) = stim_trace(1:n_stim) > stim_thresh;
    had_stim_data = true;
catch ME
    fprintf('  No stim protocol found for %s (%s); treating as unstimulated.\n', path_to_sess, ME.message);
end

raw_trace = []; had_trace_data = false;
try
    trace_all = load(fullfile(path_to_sess, 'Masks_BestIcaTrace.mat'), 'IntensOrig').IntensOrig;
    raw_trace = double(trace_all(:, cell_id));
    raw_trace = raw_trace(1:min(numel(raw_trace), nframes));
    had_trace_data = true;
catch ME
    fprintf('  No raw trace found for %s (%s); QC plot will omit the trace.\n', path_to_sess, ME.message);
end
spike_frames = [];
try
    S = load(fullfile(path_to_sess, 'inter_spikeT_spikeW.mat'), 'C');
    spikeT = S.C(cell_id).spikeT;
    if iscell(spikeT)
        if isempty(spikeT); spikeT = []; else; spikeT = spikeT{1}; end
    end
    spike_frames = double(spikeT(:));
catch ME
    fprintf('  No spike times found for %s (%s); QC plot will omit spikes.\n', path_to_sess, ME.message);
end

if had_trace_data
    y_lo = min(raw_trace); y_hi = max(raw_trace);
else
    y_lo = -0.1; y_hi = 1.1;
end
pad = 0.05 * max(y_hi - y_lo, eps);
y_lo = y_lo - pad; y_hi = y_hi + pad;

% top: whole trace (two rows tall); below: one zoomed row per selected window
n_win = numel(wins);
fig = figure('Visible', 'off', 'Position', [60 60 1400 330 + 170 * n_win]);
tl = tiledlayout(fig, n_win + 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax_full = nexttile(tl, 1, [2 1]); hold(ax_full, 'on');
stim_ranges = contiguous_true_ranges(is_stim_frame);
h_stim = gobjects(0);
for r = 1:size(stim_ranges, 1)
    h_stim(end+1) = patch([stim_ranges(r,1), stim_ranges(r,2), stim_ranges(r,2), stim_ranges(r,1)], ...
        [y_lo, y_lo, y_hi, y_hi], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none'); %#ok<AGROW>
end
h_win = gobjects(0);
qc_rows = struct('hash_id', {}, 'sess_id', {}, 'had_stim_data', {}, 'had_trace_data', {}, ...
    'any_overlap', {}, 'starting_idx', {}, 'sel_nframes', {}, 'nframes', {}, ...
    'excluded', {}, 'firing_rate_hz', {});
n_overlap = 0;
for w = 1:numel(wins)
    s0 = double(wins(w).start); s1 = min(nframes, s0 + double(wins(w).len) - 1);
    h_win(end+1) = patch([s0 s1 s1 s0], [y_lo y_lo y_hi y_hi], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none'); %#ok<AGROW>
    text((s0 + s1) / 2, y_hi - 0.03 * (y_hi - y_lo), sprintf('%.2f Hz', wins(w).window_firing_rate_hz), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 8);
    overlap = any(is_stim_frame(s0:s1));
    n_overlap = n_overlap + overlap;
    if overlap
        fprintf('  WARNING: selected window %d-%d of %s_%s overlaps stimulation frames!\n', s0, s1, hash_id, sess_id);
    end
    qc_rows(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, 'had_stim_data', had_stim_data, ... %#ok<AGROW>
        'had_trace_data', had_trace_data, 'any_overlap', overlap, 'starting_idx', s0, ...
        'sel_nframes', double(wins(w).len), 'nframes', nframes, 'excluded', false, ...
        'firing_rate_hz', wins(w).window_firing_rate_hz);
end
legend_handles = h_win(1); legend_labels = {'Selected window'};
if ~isempty(h_stim)
    legend_handles = [h_stim(1), legend_handles]; legend_labels = [{'Stim region'}, legend_labels];
end
if had_trace_data
    h_trace = plot(1:numel(raw_trace), raw_trace, 'k');
    legend_handles = [h_trace, legend_handles]; legend_labels = [{'Raw trace'}, legend_labels];
    sp = round(spike_frames(spike_frames >= 1 & spike_frames <= numel(raw_trace)));
    if ~isempty(sp)
        h_spike = plot(sp, raw_trace(sp), 'r.', 'MarkerSize', 10);
        legend_handles = [h_spike, legend_handles]; legend_labels = [{'Spikes'}, legend_labels];
    end
    ylabel('Raw fluorescence (a.u.)');
else
    h_mask = stairs(1:nframes, double(is_stim_frame) * (y_hi - pad) + pad, 'Color', [0.3 0.3 0.3]);
    legend_handles = [h_mask, legend_handles]; legend_labels = [{'Stim mask'}, legend_labels];
    ylabel('Stimulated (1) / Not (0)');
end
ylim([y_lo, y_hi]); xlim([1, nframes]); xlabel('Frame');
title(sprintf('%s_%s cell %d: %d selected window(s), stim data: %d, trace data: %d, windows overlapping stim: %d', ...
    hash_id, sess_id, cell_id, numel(wins), had_stim_data, had_trace_data, n_overlap), 'Interpreter', 'none');
legend(legend_handles, legend_labels, 'Location', 'best');

% zoomed view of each selected window
for w = 1:n_win
    s0 = double(wins(w).start); s1 = min(nframes, s0 + double(wins(w).len) - 1);
    ax = nexttile(tl); hold(ax, 'on');
    x = s0:s1;
    if had_trace_data
        n_ok = min(s1, numel(raw_trace)) - s0 + 1;
        seg = raw_trace(s0:s0 + n_ok - 1); x = x(1:n_ok);
    else
        seg = double(is_stim_frame(x));
    end
    zlo = min(seg); zhi = max(seg); zpad = 0.05 * max(zhi - zlo, eps);
    zlo = zlo - zpad; zhi = zhi + zpad;
    in_win = stim_ranges(stim_ranges(:,2) >= s0 & stim_ranges(:,1) <= s1, :);
    for r = 1:size(in_win, 1)
        a0 = max(in_win(r,1), s0); a1 = min(in_win(r,2), s1);
        patch(ax, [a0 a1 a1 a0], [zlo zlo zhi zhi], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    end
    plot(ax, x, seg, 'k');
    if had_trace_data
        sp_w = sp(sp >= s0 & sp <= s0 + n_ok - 1);
        plot(ax, sp_w, raw_trace(sp_w), 'r.', 'MarkerSize', 10);
    else
        sp_w = [];
    end
    ylim(ax, [zlo zhi]); xlim(ax, [s0 s1]); box(ax, 'on');
    title(ax, sprintf('window %d: frames %d-%d, %.2f Hz, %d spikes%s', w, s0, s1, ...
        wins(w).window_firing_rate_hz, numel(sp_w), ternary_str(qc_rows(w).any_overlap, '  -- OVERLAPS STIM', '')), ...
        'Interpreter', 'none', 'FontSize', 9);
    if had_trace_data; ylabel(ax, 'F'); end
end
xlabel(tl, 'Frame');
out_png = fullfile(qc_dir, sprintf('%s_%s_selectedwindows_QC.png', hash_id, sess_id));
saveas(fig, out_png);
close(fig);
fprintf('  [%d/%d] QC %s (%d window(s), %d overlapping stim)\n', sess_i, n_sessions, out_png, numel(wins), n_overlap);
end

function out = ternary_str(cond, a, b)
if cond; out = a; else; out = b; end
end

function save_selected_windows(path_to_sess, sess, wins, save_dir, target_file, sess_i, n_sessions)
% Generate one masked-movie tiff per hand-accepted window of this recording,
% reading the movie once. Same masking/cropping as the random-window path.
hash_id = sess.cell_hash;
parts = strsplit(sess.session_name, '_');
sess_id = parts{1};
files = strings(1, numel(wins));
for w = 1:numel(wins)
    files(w) = fullfile(save_dir, sprintf('%s_%s_w%d.tiff', hash_id, sess_id, wins(w).start));
end
todo = find(~isfile(files));
if isempty(todo)
    fprintf('  [%d/%d] all %d window file(s) for %s_%s already exist, skipping\n', sess_i, n_sessions, numel(wins), hash_id, sess_id);
    return
end
fid = fopen(fullfile(path_to_sess, 'experimental_parameters.txt'), 'r');
Info = textscan(fid, '%s');
fclose(fid);
ncol = str2double(Info{1}{6});
nrow = str2double(Info{1}{3});
[mov, nframes] = readBinMov(fullfile(path_to_sess, target_file), nrow, ncol);
cell_id = sess.cell_id;
for w = todo
    s0 = double(wins(w).start);
    s1 = s0 + double(wins(w).len) - 1;
    if s1 > nframes
        fprintf('  WARNING: window %d-%d exceeds %d frames in %s, skipping\n', s0, s1, nframes, path_to_sess);
        continue
    end
    mov_part = double(mov(:, :, s0:s1));
    nf = size(mov_part, 3);
    [Fmasks, roimask] = apply_mask_RMmov_BkgSel_nodisp(mov_part, Info);
    outrangecell = zeros(1);
    for k = 1:length(roimask)
        if isnan(Fmasks(1, k)); outrangecell = [0, k]; end
    end
    outrangecell(1) = []; roimask(:, outrangecell) = [];
    x1 = roimask{cell_id}(:, 2);
    y1 = roimask{cell_id}(:, 1); edge = 5;
    X1 = ceil(min(x1)) - edge; if X1 < 1, X1 = 1; end
    X2 = floor(max(x1)) + edge; if X2 > nrow, X2 = nrow; end
    Y1 = ceil(min(y1)) - edge; if Y1 < 1, Y1 = 1; end
    Y2 = floor(max(y1)) + edge; if Y2 > ncol, Y2 = ncol; end
    MaskMov = mov_part(X1:X2, Y1:Y2, :);
    options.big = true;
    saveastiff(MaskMov, char(files(w)), options);
    fprintf('  [%d/%d] saved %s (%d frames, %.2f Hz)\n', sess_i, n_sessions, files(w), nf, wins(w).window_firing_rate_hz);
end
end

function ranges = contiguous_true_ranges(mask)
% Returns an Nx2 array of [start, end] frame indices for each contiguous
% run of true values in a logical row vector mask.
d = diff([0, mask(:)', 0]);
starts = find(d == 1);
ends = find(d == -1) - 1;
ranges = [starts(:), ends(:)];
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

function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_nodisp(mov, info)
% copied from apply_mask_RMmov_BkgSel_FanLab.m
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
