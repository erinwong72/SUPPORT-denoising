function psnr_audit_headless(root_dirs, cell_type, nv)
%PSNR_AUDIT_HEADLESS  Audit PSNR across candidate sessions, before generating
% anything. Separate from the firing-rate audit in dataset_generation_headless.m
% (that one needs no movie/trace read; this one needs the raw trace to pick a
% noise window and compute PSNR, so it's its own script).
%
% Uses the same raw-trace PSNR definition as the rest of this codebase
% (compute_trace_metrics.m: 20*log10(peak of mean spike waveform / std of a
% spike- and stim-free noise window), the noise window picked the same way
% (auto_noise_window_fallback.m) and the same stim detection (load_stim_mask.m,
% "same recipe as dataset_generation.m"). All on the RAW trace (pre-SUPPORT),
% since this runs before any denoising model is applied.
%
%   psnr_audit_headless(root_dirs, cell_type)
%   psnr_audit_headless(root_dirs, cell_type, sel_sessions={...})
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
%   window_len      frames. Default 0 = compute PSNR over the whole recording
%                   (all spikes, noise window anywhere). When >0, PSNR is
%                   computed only within ONE window of this length -- the
%                   window with the most spikes (stim-free windows only, for
%                   'stim' recordings; the same best window the firing-rate
%                   audit picks) -- using just that window's trace, spikes and
%                   noise window, i.e. what would actually be extracted. Spike
%                   snippets need snippet_len frames either side inside the
%                   window, and the noise window needs noise_len frames, so
%                   window_len should comfortably exceed 2*snippet_len+1
%                   (default 1001) or few/no spikes will qualify; recordings
%                   shorter than window_len, or stim recordings with no
%                   stim-free window, get no PSNR (flagged). noise_start is
%                   always reported in whole-recording frame coordinates.
%   noise_len       frames; PSNR's noise window length. Default 500.
%   min_noise_len   frames; shortest window the picker will fall back to
%                   when the full noise_len isn't available spike/stim-free.
%                   Default 300.
%   shorten_step    frames; step size when shortening from noise_len down to
%                   min_noise_len. Default 100.
%   step            frames; candidate noise-window start spacing. Default 50.
%   spike_margin    frames to keep clear of any spike. Default 50.
%   stim_margin     frames to keep clear of stim/blue-light frames. Default 200.
%   min_windows     fewer valid noise-window candidates than this gets
%                   flagged in the audit row. Default 5.
%   snippet_len     frames; half-width of spike snippets for the mean spike
%                   waveform. Default 500.
%   flat_keep_frac  (0,1]. Of the spike/stim-free, low-linear-drift candidate
%                   noise windows, keep only this fraction with the flattest
%                   trace (std closest to the frame-to-frame noise level), so
%                   slow dips/bumps don't inflate noise_std and deflate PSNR.
%                   1 = off (old behaviour). Default 0.25. See
%                   auto_noise_window.m.
%
% Outputs land in SUPPORT-denoising/datasets/<cell_type>/<save_str>/psnr_audit/:
%   psnr_audit_summary.mat   struct array `psnr_summary`, one row per cell:
%                            hash_id, sess_id, anim_id, session_path, cell_id,
%                            recording_type ('stim'/'no_stim'), had_stim_data,
%                            nframes, total_spikes, has_valid_window,
%                            noise_start, noise_len_used, noise_std,
%                            spike_height, n_valid_spikes, psnr_db, flag
%   psnr_audit_summary.csv  same, as a table, for a quick look outside MATLAB
%   psnr_distribution.png   histogram + empirical CDF of psnr_db, split by
%                            recording_type, to help pick a cutoff; annotated
%                            with the noise-window length used
%   psnr_best_trace.png     sanity check: raw trace for the cell with the
%                            highest psnr_db, with its noise window (the
%                            region PSNR was actually computed from) shaded
%
% Sessions with zero spikes are excluded from the audit entirely (no spikes,
% no spike waveform, no PSNR -- same rule as the firing-rate audit).
arguments
    root_dirs cell
    cell_type {mustBeTextScalar}
    nv.sel_sessions cell = {}
    nv.invert_sel_sessions (1,1) logical = false
    nv.anim_prefixes cell = {'ipsp', 'fos', 'cck'}
    nv.discover_exclude cell = {}
    nv.save_str {mustBeTextScalar} = ""
    nv.use_cache (1,1) logical = true
    nv.stim_thresh (1,1) double = 0.1
    nv.window_len (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    nv.noise_len (1,1) double = 500
    nv.min_noise_len (1,1) double = 300
    nv.shorten_step (1,1) double = 100
    nv.step (1,1) double = 50
    nv.spike_margin (1,1) double = 50
    nv.stim_margin (1,1) double = 200
    nv.min_windows (1,1) double = 5
    nv.snippet_len (1,1) double = 500
    nv.flat_keep_frac (1,1) double {mustBeInRange(nv.flat_keep_frac, 0, 1, 'exclude-lower')} = 0.25
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
addpath(fullfile(code_path, 'SUPPORT-denoising', 'analysis'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing')); % ReadBinWaveFormsV1.m etc., needed by get_stim_protocol

%% paths
path = struct();
path.root.data = resolve_root_dirs(root_path, root_dirs);
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));
saveStr = char(nv.save_str);
path.save_dir = fullfile(path.cell_type, saveStr);
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
n_sessions = numel(total_sessions);

%% cfg for stim detection + noise-window picking (raw trace only: fallback_to_cleaned=false)
btsp_roots = path.root.data(cellfun(@(r) begins_with_btsp_folder(r), path.root.data));
cfg = struct();
cfg.btsp_roots = btsp_roots;
cfg.stim_thresh = nv.stim_thresh;
cfg.step = nv.step;
cfg.spike_margin = nv.spike_margin;
cfg.stim_margin = nv.stim_margin;
cfg.min_windows = nv.min_windows;
cfg.noise_len = nv.noise_len;
cfg.max_len = nv.noise_len;
cfg.min_noise_len = nv.min_noise_len;
cfg.shorten_step = nv.shorten_step;
cfg.flat_keep_frac = nv.flat_keep_frac;
cfg.fallback_to_cleaned = false;
cfg.models = {};

psnr_dir = fullfile(path.save_dir, 'psnr_audit');
if ~exist(psnr_dir, 'dir'); mkdir(psnr_dir); end
psnr_summary = struct('hash_id', {}, 'sess_id', {}, 'anim_id', {}, 'session_path', {}, 'cell_id', {}, ...
    'recording_type', {}, 'had_stim_data', {}, 'nframes', {}, 'total_spikes', {}, 'has_valid_window', {}, ...
    'noise_start', {}, 'noise_len_used', {}, 'noise_std', {}, 'spike_height', {}, 'n_valid_spikes', {}, ...
    'psnr_db', {}, 'flag', {}, 'window_start', {}, 'window_len', {}, 'window_spikes', {});

fprintf('\n=== Auditing PSNR across %d session(s) (window_len=%d [0=whole recording], noise_len=%d, snippet_len=%d) ===\n', ...
    n_sessions, nv.window_len, nv.noise_len, nv.snippet_len);
keep_audit = false(1, n_sessions);
for k = 1:n_sessions
    path_to_sess = char(fullfile(total_sessions(k).session_path));
    cell_id = total_sessions(k).cell_id;
    hash_id = total_sessions(k).cell_hash;
    sess_name = total_sessions(k).session_name;
    sess_id_parts = strsplit(sess_name, '_');
    sess_id = sess_id_parts{1};

    nframes_sess = NaN; total_spikes = 0; has_valid_window = false; noise_start = NaN; ...
        noise_len_used = NaN; noise_std = NaN; spike_height = NaN; n_valid_spikes = 0; ...
        psnr_db = NaN; flag = ""; window_start = NaN; window_len_used = NaN; window_spikes = NaN;
    recording_type = 'no_stim'; had_stim_data = false;
    try
        trace = double(load_model_trace(path_to_sess, 'raw', false, cell_id));
        trace = trace(:);
        nframes_sess = numel(trace);

        [sp, ~, ~] = load_spikes(path_to_sess, 'raw', false, cell_id); % dt not needed for PSNR
        total_spikes = numel(sp);

        [stim_mask, had_stim_data] = load_stim_mask(path_to_sess, nframes_sess, cfg);
        if had_stim_data && any(stim_mask)
            recording_type = 'stim';
        end

        % Restrict to one window_len-frame window if requested (best = most
        % spikes; stim-free only for 'stim' recordings). Otherwise whole recording.
        trace_w = trace; sp_w = sp; mask_w = stim_mask; w0 = 1; window_ok = true;
        if nv.window_len == 0
            window_start = 1; window_len_used = nframes_sess; window_spikes = total_spikes;
        end
        if nv.window_len > 0 && total_spikes > 0
            W = nv.window_len;
            if nframes_sess < W
                window_ok = false; flag = "recording_shorter_than_window";
            else
                sp_i = round(sp(sp >= 1 & sp <= nframes_sess));
                cum_sp = cumsum([0, accumarray(sp_i(:), 1, [nframes_sess, 1])']);
                last_w = nframes_sess - W + 1;
                wsp = cum_sp(W+1:nframes_sess+1) - cum_sp(1:last_w);
                if strcmp(recording_type, 'stim')
                    cum_st = cumsum([0, double(stim_mask(:))']);
                    wsp(cum_st(W+1:nframes_sess+1) - cum_st(1:last_w) > 0) = -inf;
                end
                [best_n, w0] = max(wsp);
                if ~isfinite(best_n)
                    window_ok = false; flag = "no_stim_free_window";
                else
                    trace_w = trace(w0:w0+W-1);
                    sp_w = sp(sp >= w0 & sp < w0 + W) - w0 + 1;
                    mask_w = stim_mask(w0:w0+W-1);
                    window_start = w0; window_len_used = W; window_spikes = numel(sp_w);
                end
            end
        end

        if total_spikes > 0 && window_ok
            get_trace = @(~) trace_w; % fallback_to_cleaned=false -> only 'raw' is ever requested
            [noise_start, info] = auto_noise_window_fallback(get_trace, sp_w, mask_w, cfg);
            flag = string(info.flag);
            if ~isnan(noise_start)
                opts_c = struct('snippet_len', nv.snippet_len, 'noise_len', info.len, ...
                    'alt_noise_lens', [], 'valid_len', info.valid_len);
                m = compute_trace_metrics(trace_w, sp_w, noise_start, opts_c);
                noise_start = noise_start + w0 - 1; % back to whole-recording coordinates
                has_valid_window = true;
                noise_len_used = info.len;
                noise_std = m.noise_std;
                spike_height = m.spike_height;
                n_valid_spikes = m.n_valid_spikes;
                psnr_db = m.psnr_db;
                if ~isreal(psnr_db)
                    % log10 of a negative spike_height/noise_std ratio (e.g. the
                    % mean spike waveform dips negative instead of peaking
                    % positive) goes complex; not a usable PSNR value.
                    psnr_db = NaN;
                    flag = strjoin([flag(strlength(flag) > 0), "non_real_psnr"], ';');
                elseif psnr_db < 0
                    % spike height below the noise std: shouldn't happen for a
                    % real spiking cell; see plot_psnr_negative_traces.m.
                    flag = strjoin([flag(strlength(flag) > 0), "negative_psnr"], ';');
                end
            end
        end
    catch ME
        fprintf('Audit: could not evaluate %s cell %d (%s)\n', path_to_sess, cell_id, ME.message);
    end

    psnr_summary(end+1) = struct('hash_id', hash_id, 'sess_id', sess_id, ... %#ok<SAGROW>
        'anim_id', total_sessions(k).anim_id, 'session_path', path_to_sess, 'cell_id', cell_id, ...
        'recording_type', recording_type, 'had_stim_data', had_stim_data, 'nframes', nframes_sess, ...
        'total_spikes', total_spikes, 'has_valid_window', has_valid_window, 'noise_start', noise_start, ...
        'noise_len_used', noise_len_used, 'noise_std', noise_std, 'spike_height', spike_height, ...
        'n_valid_spikes', n_valid_spikes, 'psnr_db', psnr_db, 'flag', char(flag), ...
        'window_start', window_start, 'window_len', window_len_used, 'window_spikes', window_spikes);

    if total_spikes == 0
        fprintf('  %s_%s cell %d [%s]: NO SPIKES -- excluding\n', hash_id, sess_id, cell_id, recording_type);
    elseif ~has_valid_window
        fprintf('  %s_%s cell %d [%s]: no valid noise window (%s)\n', hash_id, sess_id, cell_id, recording_type, flag);
    else
        fprintf('  %s_%s cell %d [%s]: PSNR=%.2f dB (noise_std=%.3g, spike_height=%.3g, n_spikes=%d)\n', ...
            hash_id, sess_id, cell_id, recording_type, psnr_db, noise_std, spike_height, n_valid_spikes);
    end
    keep_audit(k) = total_spikes > 0;
end

save(fullfile(psnr_dir, 'psnr_audit_summary.mat'), 'psnr_summary');
writetable(struct2table(psnr_summary), fullfile(psnr_dir, 'psnr_audit_summary.csv'));
fprintf('PSNR audit: excluded %d/%d session(s) with no spikes; %d/%d have a valid PSNR value (see %s).\n', ...
    sum(~keep_audit), n_sessions, sum(~isnan([psnr_summary.psnr_db])), n_sessions, psnr_dir);

%% Distribution plot: histogram + ECDF of PSNR, split by recording_type
plot_psnr_distribution(psnr_summary, nv.noise_len, nv.min_noise_len, fullfile(psnr_dir, 'psnr_distribution.png'));
fprintf('Saved %s\n', fullfile(psnr_dir, 'psnr_distribution.png'));

%% Example trace at each PSNR level (>=14 dB up to the max), to judge a cutoff by eye
try
    plot_psnr_cutoff_traces(psnr_dir);
catch ME
    fprintf('Could not make psnr_cutoff_traces.png (%s)\n', ME.message);
end

%% Traces for any recordings with negative PSNR (flagged 'negative_psnr' / 'non_real_psnr')
try
    plot_psnr_negative_traces(psnr_dir);
catch ME
    fprintf('Could not make psnr_negative_traces.png (%s)\n', ME.message);
end

%% Sanity check: trace for the cell with the highest PSNR, noise window shaded
% plot_best_psnr_trace(psnr_summary, cfg, fullfile(psnr_dir, 'psnr_best_trace.png'));
end

function tf = begins_with_btsp_folder(root)
% True if root's own folder name (not the full path) contains "BTSP" --
% matches the is_btsp heuristic used throughout dataset_generation*.m: the
% shared "DSI-BTSP" parent directory doesn't count, only the project folder.
[~, name] = fileparts(root);
tf = contains(name, 'BTSP', 'IgnoreCase', true);
end

function plot_psnr_distribution(psnr_summary, noise_len, min_noise_len, out_file)
vals = [psnr_summary.psnr_db];
types = string({psnr_summary.recording_type});
valid = isfinite(vals) & imag(vals) == 0;
vals = real(vals(valid)); types = types(valid);

groups = ["no_stim", "stim"];
colors = [0.20 0.55 0.35; 0.75 0.25 0.20]; % green=no_stim, red=stim (matches QC plot convention)

fig = figure('Color', 'w', 'Position', [100 100 900 400], 'Visible', 'off');
tl = tiledlayout(1, 2, 'TileSpacing', 'compact');

nexttile; hold on;
h = gobjects(1, numel(groups));
counts = zeros(1, numel(groups));
for gi = 1:numel(groups)
    v = vals(types == groups(gi));
    counts(gi) = numel(v);
    if isempty(v), continue; end
    h(gi) = histogram(v, 'Normalization', 'probability', 'FaceColor', colors(gi,:), ...
        'FaceAlpha', 0.5, 'EdgeColor', 'none');
end
xlabel('PSNR (dB)'); ylabel('Fraction of recordings'); grid on; box on;
valid_h = isgraphics(h);
if any(valid_h)
    idx = find(valid_h);
    labels = arrayfun(@(i) sprintf('%s (n=%d)', groups(i), counts(i)), idx, 'UniformOutput', false);
    legend(h(idx), labels, 'Location', 'best');
end
title('PSNR distribution');

nexttile; hold on;
for gi = 1:numel(groups)
    v = sort(vals(types == groups(gi)));
    if isempty(v), continue; end
    y = (1:numel(v)) / numel(v);
    stairs(v, y, 'Color', colors(gi,:), 'LineWidth', 2);
end
xlabel('PSNR (dB)'); ylabel('Cumulative fraction'); grid on; box on; ylim([0 1]);
title('PSNR CDF');

title(tl, sprintf('PSNR audit: n=%d recordings with a valid window (no\\_stim=%d, stim=%d); noise window target=%d frames (shortens to as low as %d)', ...
    numel(vals), nnz(types == "no_stim"), nnz(types == "stim"), noise_len, min_noise_len), 'Interpreter', 'tex');
exportgraphics(fig, out_file, 'Resolution', 150);
close(fig);
end

function plot_best_psnr_trace(psnr_summary, cfg, out_file)
% Re-loads the raw trace for the recording with the highest psnr_db (cheap: just
% one recording, not the whole audit) and plots it with the noise window used for
% that PSNR value shaded -- a sanity check that the window landed somewhere
% sensible (spike- and stim-free, representative noise level).
vals = [psnr_summary.psnr_db];
valid = isfinite(vals) & imag(vals) == 0;
if ~any(valid)
    fprintf('No finite psnr_db values; skipping %s.\n', out_file);
    return
end
idx_pool = find(valid);
[~, bi] = max(real(vals(idx_pool)));
row = psnr_summary(idx_pool(bi));

try
    trace = double(load_model_trace(row.session_path, 'raw', false, row.cell_id));
    trace = trace(:);
    [sp, ~, ~] = load_spikes(row.session_path, 'raw', false, row.cell_id);
catch ME
    fprintf('Could not load trace for best-PSNR recording %s_%s cell %d (%s); skipping %s.\n', ...
        row.hash_id, row.sess_id, row.cell_id, ME.message, out_file);
    return
end
n = numel(trace);
[stim_mask, ~] = load_stim_mask(row.session_path, n, cfg);

window_range = [row.noise_start, min(row.noise_start + row.noise_len_used - 1, n)];

fig = figure('Color', 'w', 'Position', [100 100 1100 350], 'Visible', 'off'); hold on;
y_lo = min(trace); y_hi = max(trace);
pad = 0.05 * max(y_hi - y_lo, eps);
y_lo = y_lo - pad; y_hi = y_hi + pad;

stim_ranges = contiguous_true_ranges(stim_mask);
h_stim = gobjects(0);
for r = 1:size(stim_ranges, 1)
    h_stim(end+1) = patch([stim_ranges(r,1), stim_ranges(r,2), stim_ranges(r,2), stim_ranges(r,1)], ...
        [y_lo, y_lo, y_hi, y_hi], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none'); %#ok<AGROW>
end
h_window = patch([window_range(1), window_range(2), window_range(2), window_range(1)], ...
    [y_lo, y_lo, y_hi, y_hi], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');

legend_handles = h_window; legend_labels = {'Noise window (sampled region)'};
if ~isempty(h_stim)
    legend_handles = [h_stim(1), legend_handles]; legend_labels = [{'Stim region'}, legend_labels];
end

h_trace = plot(1:n, trace, 'k');
legend_handles = [h_trace, legend_handles]; legend_labels = [{'Raw trace'}, legend_labels];
if ~isempty(sp)
    valid_sp = round(sp(sp >= 1 & sp <= n));
    h_spike = plot(valid_sp, trace(valid_sp), 'r.', 'MarkerSize', 8);
    legend_handles = [h_spike, legend_handles]; legend_labels = [{'Spikes'}, legend_labels];
end

ylim([y_lo, y_hi]); xlim([1, n]);
xlabel('Frame'); ylabel('Raw fluorescence (a.u.)');
title(sprintf('Best PSNR: %s\\_%s cell %d [%s] = %.2f dB, noise window [%d-%d] (%d frames)', ...
    row.hash_id, row.sess_id, row.cell_id, row.recording_type, real(row.psnr_db), ...
    window_range(1), window_range(2), diff(window_range)+1), 'Interpreter', 'none');
legend(legend_handles, legend_labels, 'Location', 'best');
exportgraphics(fig, out_file, 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', out_file);
end

function ranges = contiguous_true_ranges(mask)
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
