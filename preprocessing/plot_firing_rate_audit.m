function plot_firing_rate_audit(audit_path)
%PLOT_FIRING_RATE_AUDIT  Histogram + empirical CDF of firing_rate_audit.mat's
% rates, split by recording_type (stim/no_stim), to help pick a
% min_firing_rate cutoff. Standalone: just needs the .mat file already
% produced by dataset_generation.m / dataset_generation_headless.m's
% firing-rate audit -- doesn't rerun the audit itself.
%
%   plot_firing_rate_audit()                              % looks in pwd
%   plot_firing_rate_audit('firing_rate_audit.mat')
%   plot_firing_rate_audit('.../datasets/mydata/firing_rate_audit')  % dir ok too
%
% Plots both avg_firing_rate_hz (whole-recording average) and
% max_firing_rate_hz (best sel_nframes window, excluding stim windows for
% 'stim' recordings) side by side, each as a histogram + ECDF, annotated with
% the window length (sel_nframes) used for max_firing_rate_hz.
%
% Sanity check: also re-loads the raw trace for whichever cell has the
% highest avg_firing_rate_hz, and whichever has the highest
% max_firing_rate_hz, and saves a trace plot for each with the sampled
% region shaded (the whole recording for the avg metric; the specific
% best_window_start:best_window_start+best_window_len-1 window for the max
% metric), spikes marked, and any stim regions shaded too. This needs the
% raw data reachable from this machine (session_path is translated via
% convert_struct_paths, same as dataset_generation_headless.m).
%
% Saves next to the .mat file:
%   firing_rate_distribution.png
%   firing_rate_best_avg_trace.png
%   firing_rate_best_max_trace.png
arguments
    audit_path {mustBeTextScalar} = 'firing_rate_audit.mat'
end
audit_path = char(audit_path);
if isfolder(audit_path)
    audit_path = fullfile(audit_path, 'firing_rate_audit.mat');
end
assert(isfile(audit_path), 'firing_rate_audit.mat not found: %s', audit_path);

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'analysis'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));

S = load(audit_path, 'audit_summary');
audit_summary = convert_struct_paths(S.audit_summary, root_path);
out_dir = fileparts(audit_path);
if isempty(out_dir); out_dir = pwd; end

groups = ["no_stim", "stim"];
colors = [0.20 0.55 0.35; 0.75 0.25 0.20]; % green=no_stim, red=stim (matches the PSNR audit's convention)
metrics = {'avg_firing_rate_hz', 'Average firing rate (Hz)'; ...
           'max_firing_rate_hz', 'Max firing rate over window (Hz)'};

types = string({audit_summary.recording_type});
sel_nframes_vals = [audit_summary.sel_nframes];
sel_nframes_vals = sel_nframes_vals(isfinite(sel_nframes_vals));
if isempty(sel_nframes_vals)
    sel_nframes_report = NaN;
else
    sel_nframes_report = mode(sel_nframes_vals);
end

%% Distribution plot
fig = figure('Color', 'w', 'Position', [100 100 900 700], 'Visible', 'off');
tl = tiledlayout(2, 2, 'TileSpacing', 'compact');
for mi = 1:size(metrics, 1)
    field = metrics{mi, 1};
    label = metrics{mi, 2};
    vals = [audit_summary.(field)];
    valid = isfinite(vals) & imag(vals) == 0;
    vals_v = real(vals(valid)); types_v = types(valid);

    nexttile; hold on;
    h = gobjects(1, numel(groups));
    counts = zeros(1, numel(groups));
    for gi = 1:numel(groups)
        v = vals_v(types_v == groups(gi));
        counts(gi) = numel(v);
        if isempty(v), continue; end
        h(gi) = histogram(v, 'Normalization', 'probability', 'FaceColor', colors(gi,:), ...
            'FaceAlpha', 0.5, 'EdgeColor', 'none');
    end
    xlabel(label); ylabel('Fraction of cells'); grid on; box on;
    valid_h = isgraphics(h);
    if any(valid_h)
        idx = find(valid_h);
        labels = arrayfun(@(i) sprintf('%s (n=%d)', groups(i), counts(i)), idx, 'UniformOutput', false);
        legend(h(idx), labels, 'Location', 'best');
    end
    title([label ': distribution']);

    nexttile; hold on;
    for gi = 1:numel(groups)
        v = sort(vals_v(types_v == groups(gi)));
        if isempty(v), continue; end
        y = (1:numel(v)) / numel(v);
        stairs(v, y, 'Color', colors(gi,:), 'LineWidth', 2);
    end
    xlabel(label); ylabel('Cumulative fraction'); grid on; box on; ylim([0 1]);
    title([label ': CDF']);
end
title(tl, sprintf('Firing-rate audit: n=%d cells (no\\_stim=%d, stim=%d); max\\_firing\\_rate\\_hz window length = %d frames', ...
    numel(audit_summary), nnz(types == "no_stim"), nnz(types == "stim"), sel_nframes_report), 'Interpreter', 'tex');
dist_file = fullfile(out_dir, 'firing_rate_distribution.png');
exportgraphics(fig, dist_file, 'Resolution', 150);
close(fig);
fprintf('Saved %s\n', dist_file);

%% Sanity check: trace for the cell with the highest value of each metric
plot_best_rate_trace(audit_summary, 'avg_firing_rate_hz', 'Average firing rate (whole recording)', ...
    fullfile(out_dir, 'firing_rate_best_avg_trace.png'));
plot_best_rate_trace(audit_summary, 'max_firing_rate_hz', 'Max firing rate (best window)', ...
    fullfile(out_dir, 'firing_rate_best_max_trace.png'));
end

function plot_best_rate_trace(audit_summary, field, label, out_file)
vals = [audit_summary.(field)];
valid = isfinite(vals) & imag(vals) == 0;
if ~any(valid)
    fprintf('No finite %s values; skipping %s.\n', field, out_file);
    return
end
idx_pool = find(valid);
[~, bi] = max(real(vals(idx_pool)));
row = audit_summary(idx_pool(bi));

try
    trace = double(load_model_trace(row.session_path, 'raw', false, row.cell_id));
    trace = trace(:);
    [sp, ~, ~] = load_spikes(row.session_path, 'raw', false, row.cell_id);
catch ME
    fprintf('Could not load trace for best %s cell %s_%s cell %d (%s); skipping %s.\n', ...
        field, row.hash_id, row.sess_id, row.cell_id, ME.message, out_file);
    return
end
n = numel(trace);

% is_btsp, same heuristic as dataset_generation*.m: the project folder name
% (the path segment right before anim_id) contains "BTSP" or not.
prefix = extractBefore(row.session_path, [filesep row.anim_id filesep]);
[~, root_folder_name] = fileparts(prefix);
is_btsp = contains(root_folder_name, 'BTSP', 'IgnoreCase', true);
is_stim_frame = false(1, n);
try
    sp_protocol = get_stim_protocol(row.session_path, is_btsp, 1);
    stim_trace = sp_protocol.trace;
    k = min(numel(stim_trace), n);
    is_stim_frame(1:k) = stim_trace(1:k) > 0.1; % matches get_stim_protocol default
catch
    % no stim protocol -- leave as all false
end

% Sampled region to shade: whole recording for the avg metric; the specific
% best window for the max metric (falls back to the whole recording if the
% audit didn't record one, e.g. an older audit file predating this field).
has_window_info = isfield(row, 'best_window_start') && ~isnan(row.best_window_start);
if strcmp(field, 'avg_firing_rate_hz') || ~has_window_info
    window_range = [1, n];
else
    window_range = [row.best_window_start, min(row.best_window_start + row.best_window_len - 1, n)];
end

fig = figure('Color', 'w', 'Position', [100 100 1100 350], 'Visible', 'off'); hold on;
y_lo = min(trace); y_hi = max(trace);
pad = 0.05 * max(y_hi - y_lo, eps);
y_lo = y_lo - pad; y_hi = y_hi + pad;

stim_ranges = contiguous_true_ranges(is_stim_frame);
h_stim = gobjects(0);
for r = 1:size(stim_ranges, 1)
    h_stim(end+1) = patch([stim_ranges(r,1), stim_ranges(r,2), stim_ranges(r,2), stim_ranges(r,1)], ...
        [y_lo, y_lo, y_hi, y_hi], 'r', 'FaceAlpha', 0.15, 'EdgeColor', 'none'); %#ok<AGROW>
end
h_window = patch([window_range(1), window_range(2), window_range(2), window_range(1)], ...
    [y_lo, y_lo, y_hi, y_hi], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');

legend_handles = h_window; legend_labels = {'Sampled region'};
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
title(sprintf('%s: %s\\_%s cell %d [%s] = %.3f Hz, window [%d-%d] (%d frames)', ...
    label, row.hash_id, row.sess_id, row.cell_id, row.recording_type, real(row.(field)), ...
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
