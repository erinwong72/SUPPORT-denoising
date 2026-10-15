function plot_psnr_cutoff_traces(audit_path, nv)
%PLOT_PSNR_CUTOFF_TRACES  Visual aid for choosing a PSNR cutoff: one
% example raw trace for each PSNR level from min_psnr up to the max PSNR in
% psnr_audit_summary.mat, one panel per level on a single figure.
%
%   plot_psnr_cutoff_traces()                                 % looks in pwd
%   plot_psnr_cutoff_traces('.../<cell_type>/psnr_audit')     % dir or .mat
%   plot_psnr_cutoff_traces(audit_path, min_psnr=14, step=1, win_len=3000)  % excerpts instead of whole traces
%
% For each level L in min_psnr:step:max (the max itself is always included),
% one recording with psnr_db within step/2 of L is plotted (each recording
% used at most once), highest PSNR on top. prefer='spikes' (default) takes
% the one with the most total spikes; prefer='nearest' takes the closest PSNR. Levels with no
% recording that close are skipped and listed in the console. Each trace is
% the whole recording by default (win_len=0), with that recording's PSNR noise
% window shaded green (spike- and stim-free by construction) and detected
% spikes in red. With win_len>0 it is instead a win_len-frame excerpt that
% contains the noise window, positioned to include as many spikes as possible.
%
% No baseline subtraction. normalize='spike_height' (default) divides each
% trace by its mean spike waveform peak (the 'spike height' in the PSNR), so
% every panel is in spike-height units and PSNR = 1 / (noise std on that
% scale): the noise band visibly shrinks as PSNR rises. normalize='none'
% shows raw F. Each PSNR level gets its own panel. shared_ylim=true (default)
% gives every panel the same y-span (y_span, default auto) centered on its own
% trace, so noise thickness is comparable; false autoscales each panel.
%
% Needs the raw data reachable from this machine (session_path is translated
% with convert_struct_paths). Saves psnr_cutoff_traces.png (and .csv listing
% the recordings shown) next to the .mat, unless out_file is given.
arguments
    audit_path {mustBeTextScalar} = 'psnr_audit_summary.mat'
    nv.min_psnr (1,1) double = 14
    nv.step (1,1) double {mustBePositive} = 1
    nv.win_len (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    nv.normalize {mustBeMember(nv.normalize, {'spike_height', 'none'})} = 'spike_height'
    nv.prefer {mustBeMember(nv.prefer, {'spikes', 'nearest'})} = 'spikes'
    nv.shared_ylim (1,1) logical = true
    nv.y_span (1,1) double = NaN
    nv.out_file {mustBeTextScalar} = ""
end
audit_path = char(audit_path);
if isfolder(audit_path)
    audit_path = fullfile(audit_path, 'psnr_audit_summary.mat');
end
assert(isfile(audit_path), 'psnr_audit_summary.mat not found: %s', audit_path);

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

S = load(audit_path, 'psnr_summary');
rows = convert_struct_paths(S.psnr_summary, root_path);
psnr_all = [rows.psnr_db];
ok = isfinite(psnr_all) & imag(psnr_all) == 0 & [rows.has_valid_window];
psnr_all(~ok) = NaN;
psnr_all = real(psnr_all);
max_psnr = max(psnr_all);
if isnan(max_psnr) || max_psnr < nv.min_psnr
    error('No recordings with PSNR >= %g (max is %g).', nv.min_psnr, max_psnr);
end

levels = nv.min_psnr:nv.step:max_psnr;
if max_psnr - levels(end) > 1e-9; levels(end+1) = max_psnr; end
levels = fliplr(levels); % highest on top

total_spikes = [rows.total_spikes];
used = false(size(rows));
picked = zeros(1, 0); picked_level = zeros(1, 0);
for L = levels
    d = abs(psnr_all - L);
    d(used | psnr_all < nv.min_psnr) = inf;
    [dmin, bi] = min(d);
    if strcmp(nv.prefer, 'spikes')
        % among recordings close enough to this level, take the spikiest
        near = find(d <= nv.step / 2 + 1e-9);
        if ~isempty(near)
            [~, k] = max(total_spikes(near));
            bi = near(k); dmin = d(bi);
        end
    end
    if isfinite(dmin) && dmin <= nv.step / 2 + 1e-9
        used(bi) = true;
        picked(end+1) = bi; picked_level(end+1) = L; %#ok<AGROW>
    else
        fprintf('No unused recording within %.2g dB of %.1f dB; skipping that level.\n', nv.step / 2, L);
    end
end
assert(~isempty(picked), 'No recordings matched any PSNR level.');
[~, ord] = sort(psnr_all(picked), 'descend'); % top = highest actual PSNR
picked = picked(ord);
n = numel(picked);

shown = struct('hash_id', {}, 'sess_id', {}, 'cell_id', {}, 'recording_type', {}, 'psnr_db', {}, ...
    'win_start', {}, 'win_end', {});
excerpts = cell(1, n); sps = cell(1, n); meta = cell(1, n);
for i = 1:n
    r = rows(picked(i));
    try
        tr = double(load_model_trace(r.session_path, 'raw', false, r.cell_id)); tr = tr(:);
        [sp, ~, ~] = load_spikes(r.session_path, 'raw', false, r.cell_id);
    catch ME
        fprintf('Could not load %s_%s cell %d (%s); skipping.\n', r.hash_id, r.sess_id, r.cell_id, ME.message);
        continue
    end
    nf = numel(tr);
    if nv.win_len == 0
        % whole trace
        wl = nf; w0 = 1;
    else
        % Among excerpts that still contain the whole noise window, take the one
        % with the most spikes, so the plot shows spikes against the noise.
        wl = min(nv.win_len, nf);
        n_end = r.noise_start + r.noise_len_used - 1;
        lo = max(1, n_end - wl + 1); hi = min(r.noise_start, nf - wl + 1);
        if hi < lo; lo = max(1, min(hi, nf - wl + 1)); hi = lo; end
        cand = round(lo):round(hi);
        cum = cumsum([0, accumarray(round(sp(sp >= 1 & sp <= nf)), 1, [nf, 1])']);
        [~, bi] = max(cum(cand + wl) - cum(cand));
        w0 = cand(bi);
    end
    w1 = w0 + wl - 1;
    scale = 1;
    if strcmp(nv.normalize, 'spike_height')
        scale = 1 / r.spike_height; % pure rescale: PSNR = 1 / (noise std on this scale)
    end
    excerpts{i} = tr(w0:w1) * scale; % no baseline subtraction
    n_idx = r.noise_start : (r.noise_start + r.noise_len_used - 1);
    sps{i} = round(sp(sp >= w0 & sp <= w1)) - w0 + 1;
    meta{i} = struct('noise', [n_idx(1), n_idx(end)] - w0 + 1, 'f0', mean(tr(n_idx)) * scale, ...
        'nsd', r.noise_std * scale);
    shown(end+1) = struct('hash_id', r.hash_id, 'sess_id', r.sess_id, 'cell_id', r.cell_id, ...
        'recording_type', r.recording_type, 'psnr_db', r.psnr_db, 'win_start', w0, 'win_end', w1); %#ok<AGROW>
end
loaded = find(~cellfun(@isempty, excerpts));
n_show = numel(loaded);
assert(n_show > 0, 'None of the selected recordings could be loaded.');
max_len = max(cellfun(@numel, excerpts(loaded)));

% Shared y-span: every panel gets the same height (in plotted units), centered
% on its own trace's min/max midpoint, so noise thickness is comparable between
% panels (no data are shifted; only the axis window is). Default span = the
% largest min-to-max range among the traces, +10%; override with y_span.
ranges = cellfun(@(e) max(e) - min(e), excerpts(loaded));
span = nv.y_span;
if isnan(span); span = 1.1 * max(ranges); end

% one panel per PSNR level
fig = figure('Color', 'w', 'Visible', 'off', 'Position', [60 60 1300 max(500, 150 * n_show + 100)]);
tl = tiledlayout(fig, n_show, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
for row_i = 1:n_show
    i = loaded(row_i);
    r = rows(picked(i));
    seg = excerpts{i}; m = meta{i};
    ax = nexttile(tl); hold(ax, 'on');
    if nv.shared_ylim
        yl = (max(seg) + min(seg)) / 2 + span / 2 * [-1 1];
    else
        yl = [min(seg) max(seg)]; pad = 0.05 * max(diff(yl), eps); yl = yl + [-pad pad];
    end
    nz = max(1, m.noise(1)):min(numel(seg), m.noise(2));
    if ~isempty(nz)
        patch(ax, [nz(1) nz(end) nz(end) nz(1)], yl([1 1 2 2]), 'g', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    end
    % grey = noise-window mean +- 1 noise std (the noise level PSNR compares spikes to)
    patch(ax, [1 numel(seg) numel(seg) 1], m.f0 + m.nsd * [-1 -1 1 1], [0.8 0.8 0.8], ...
        'FaceAlpha', 0.5, 'EdgeColor', 'none');
    plot(ax, 1:numel(seg), seg, 'k', 'LineWidth', 0.6);
    sp = sps{i};
    if ~isempty(sp)
        plot(ax, sp, seg(sp), 'r.', 'MarkerSize', 8);
    end
    ylim(ax, yl); xlim(ax, [1 max_len]); box(ax, 'on');
    if strcmp(nv.normalize, 'spike_height')
        ylabel(ax, sprintf('%.1f dB\nF / spike height', r.psnr_db));
    else
        ylabel(ax, sprintf('%.1f dB\nF', r.psnr_db));
    end
    title(ax, sprintf('%s_%s cell %d [%s]', r.hash_id, r.sess_id, r.cell_id, r.recording_type), ...
        'Interpreter', 'none', 'FontSize', 8);
    if row_i < n_show; set(ax, 'XTickLabel', []); end
end
xlabel(tl, 'Frame (noise window green; noise-window mean +-1 std grey; spikes red)');
title(tl, sprintf('Raw traces at each PSNR level from %g dB to max %.1f dB (n=%d of %d recordings)', ...
    nv.min_psnr, max_psnr, n_show, nnz(~isnan(psnr_all))), 'Interpreter', 'none');

out_file = char(nv.out_file);
if isempty(out_file)
    out_file = fullfile(fileparts(audit_path), 'psnr_cutoff_traces.png');
end
exportgraphics(fig, out_file, 'Resolution', 150);
close(fig);
writetable(struct2table(shown), strrep(out_file, '.png', '.csv'));
fprintf('Saved %s\n', out_file);
end
