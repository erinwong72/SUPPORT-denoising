function plot_psnr_negative_traces(audit_path, nv)
%PLOT_PSNR_NEGATIVE_TRACES  Plot the recordings whose PSNR came out negative
% (spike height smaller than the noise std, or a negative spike height, which
% is stored as NaN with the 'non_real_psnr' flag), since a real spiking cell
% shouldn't land there -- usually a bad noise window, a bad spike list, or a
% spike waveform that isn't a positive peak.
%
%   plot_psnr_negative_traces()                               % looks in pwd
%   plot_psnr_negative_traces('.../<cell_type>/psnr_audit')   % dir or .mat
%   plot_psnr_negative_traces(audit_path, win_len=3000)  % excerpt instead of whole trace
%
% One row per flagged recording (most negative first):
%   left   the whole raw trace by default (win_len=0); with win_len>0, a
%          win_len-frame excerpt placed to hold the PSNR noise window plus as
%          many spikes as possible. Noise window shaded green, spikes red.
%          y-axis is raw F (same as the other raw-trace plots). The grey band
%          is the noise-window mean +-1 noise std, the noise level PSNR
%          compares the spikes against;
%   right  the mean spike waveform (+-snippet_len frames around each spike),
%          also raw F, with the same grey band. The peak's height above the
%          noise-window mean, divided by the noise std, is the PSNR.
% Saves psnr_negative_traces.png and psnr_negative_traces.csv next to the .mat.
% Does nothing (prints a message) if no recording is flagged.
arguments
    audit_path {mustBeTextScalar} = 'psnr_audit_summary.mat'
    nv.win_len (1,1) double {mustBeNonnegative, mustBeInteger} = 0
    nv.snippet_len (1,1) double {mustBePositive, mustBeInteger} = 500
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
has_win = [rows.has_valid_window];
p = [rows.psnr_db];
neg_db = has_win & imag(p) == 0 & real(p) < 0;
non_real = has_win & (isnan(p) | imag(p) ~= 0) & [rows.spike_height] <= 0;
sel = find(neg_db | non_real);
if isempty(sel)
    fprintf('No negative or non-real PSNR values in %s.\n', audit_path);
    return
end
sort_key = real(p(sel)); sort_key(isnan(sort_key)) = -inf; % non-real first
[~, ord] = sort(sort_key, 'ascend');
sel = sel(ord);
n = numel(sel);
fprintf('%d recording(s) with negative/non-real PSNR:\n', n);

fig = figure('Color', 'w', 'Visible', 'off', 'Position', [60 60 1400 max(300, 170 * n + 100)]);
tl = tiledlayout(fig, n, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
shown = struct('hash_id', {}, 'sess_id', {}, 'cell_id', {}, 'recording_type', {}, 'psnr_db', {}, ...
    'spike_height', {}, 'noise_std', {}, 'n_valid_spikes', {}, 'win_start', {}, 'win_end', {}, 'kind', {});
L = nv.snippet_len;
for i = 1:n
    r = rows(sel(i));
    kind = 'negative_psnr';
    if non_real(sel(i)); kind = 'negative_spike_height'; end
    fprintf('  %s_%s cell %d [%s]: %s, psnr=%.2f dB, spike_height=%.3g, noise_std=%.3g, n_spikes=%d\n', ...
        r.hash_id, r.sess_id, r.cell_id, r.recording_type, kind, real(r.psnr_db), r.spike_height, r.noise_std, r.n_valid_spikes);
    try
        tr = double(load_model_trace(r.session_path, 'raw', false, r.cell_id)); tr = tr(:);
        [sp, ~, ~] = load_spikes(r.session_path, 'raw', false, r.cell_id);
    catch ME
        fprintf('    could not load (%s); skipping.\n', ME.message);
        continue
    end
    nf = numel(tr);
    sp = round(sp(sp >= 1 & sp <= nf));
    % if the audit used a window_len window, only its spikes went into the PSNR
    if isfield(r, 'window_start') && ~isnan(r.window_start) && r.window_len < nf
        sp = sp(sp >= r.window_start & sp < r.window_start + r.window_len);
    end

    n_end = r.noise_start + r.noise_len_used - 1;
    if nv.win_len == 0
        % whole trace
        wl = nf; w0 = 1;
    else
        % excerpt containing the whole noise window with the most spikes
        wl = min(nv.win_len, nf);
        lo = max(1, n_end - wl + 1); hi = min(r.noise_start, nf - wl + 1);
        if hi < lo; lo = max(1, min(hi, nf - wl + 1)); hi = lo; end
        cand = round(lo):round(hi);
        cum = cumsum([0, accumarray(sp(:), 1, [nf, 1])']);
        [~, bi] = max(cum(cand + wl) - cum(cand));
        w0 = cand(bi);
    end
    w1 = w0 + wl - 1;
    sd = r.noise_std;
    % raw F; the grey band is the noise-window mean +- 1 noise std
    f0 = mean(tr(r.noise_start:n_end));
    seg = tr(w0:w1);
    sps = sp(sp >= w0 & sp <= w1) - w0 + 1;
    nz = [r.noise_start, n_end] - w0 + 1;

    ax = nexttile(tl, (i - 1) * 4 + 1, [1 3]); hold(ax, 'on');
    yl = [min(seg) max(seg)]; pad = 0.05 * max(diff(yl), eps); yl = yl + [-pad pad];
    patch(ax, [nz(1) nz(2) nz(2) nz(1)], yl([1 1 2 2]), 'g', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    patch(ax, [1 wl wl 1], f0 + sd * [-1 -1 1 1], [0.8 0.8 0.8], 'FaceAlpha', 0.5, 'EdgeColor', 'none');
    plot(ax, 1:wl, seg, 'k', 'LineWidth', 0.6);
    plot(ax, sps, seg(sps), 'r.', 'MarkerSize', 8);
    ylim(ax, yl); xlim(ax, [1 wl]); box(ax, 'on');
    ylabel(ax, 'F');
    xlabel(ax, 'frame');
    if nv.win_len ~= 0; xlabel(ax, sprintf('frame (excerpt starts at %d)', w0)); end
    if non_real(sel(i))
        t = sprintf('%s_%s cell %d [%s]: spike height %.3g < 0 (PSNR undefined), noise std %.3g, %d spikes', ...
            r.hash_id, r.sess_id, r.cell_id, r.recording_type, r.spike_height, sd, r.n_valid_spikes);
    else
        t = sprintf('%s_%s cell %d [%s]: PSNR %.2f dB (spike height %.3g / noise std %.3g), %d spikes', ...
            r.hash_id, r.sess_id, r.cell_id, r.recording_type, real(r.psnr_db), r.spike_height, sd, r.n_valid_spikes);
    end
    title(ax, t, 'Interpreter', 'none', 'FontSize', 8);

    % mean spike waveform, same snippet recipe as compute_trace_metrics
    valid = sp(sp > L & sp < nf - L);
    ax2 = nexttile(tl, (i - 1) * 4 + 4); hold(ax2, 'on');
    if ~isempty(valid)
        wf = mean(reshape(tr(valid(:) + (-L:L)), numel(valid), 2 * L + 1), 1);
        patch(ax2, [-L L L -L], f0 + sd * [-1 -1 1 1], [0.8 0.8 0.8], 'FaceAlpha', 0.5, 'EdgeColor', 'none');
        plot(ax2, -L:L, wf, 'k', 'LineWidth', 1);
        ylabel(ax2, 'F');
        xline(ax2, 0, ':');
        xlim(ax2, [-L L]); box(ax2, 'on');
    end
    title(ax2, 'mean spike waveform (grey = noise-window mean \pm1 noise std)', 'FontSize', 8);
    shown(end+1) = struct('hash_id', r.hash_id, 'sess_id', r.sess_id, 'cell_id', r.cell_id, ... %#ok<AGROW>
        'recording_type', r.recording_type, 'psnr_db', real(r.psnr_db), 'spike_height', r.spike_height, ...
        'noise_std', sd, 'n_valid_spikes', r.n_valid_spikes, 'win_start', w0, 'win_end', w1, 'kind', kind);
end
title(tl, sprintf('Recordings with negative PSNR (n=%d of %d audited with a valid window); raw F, noise window green, noise-window mean +-1 std grey, spikes red', ...
    n, nnz(has_win)), 'Interpreter', 'none');

out_file = char(nv.out_file);
if isempty(out_file)
    out_file = fullfile(fileparts(audit_path), 'psnr_negative_traces.png');
end
exportgraphics(fig, out_file, 'Resolution', 150);
close(fig);
if ~isempty(shown)
    writetable(struct2table(shown), strrep(out_file, '.png', '.csv'));
end
fprintf('Saved %s\n', out_file);
end
