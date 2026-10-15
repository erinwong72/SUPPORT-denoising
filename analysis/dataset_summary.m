function dataset_summary(config)
% dataset_summary.m
% Usage: dataset_summary()  or  dataset_summary('my_config')  - config = name of a
% config file in configs/analysis (see load_analysis_config.m).
% Dataset-level summary of the SUPPORT model comparison: one figure of pooled
% panels instead of per-cell PNGs. The unit of aggregation is the CELL.
% Reads recs.mat / metrics.mat / gains.mat (support_model_comparison.m,
% model_comparison_plots.m). The trace pass (per-spike preservation, stim vs
% non-stim waveforms, noise spectra) is cached in summary_data.mat.
%
% Outputs (Erin/support_data/model_comparison/):
%   summary_overview.png          grand-average waveform, noise spectra, paired PSNR / paper SNR, gain CIs
%   summary_stim_vs_nonstim.png   waveform and per-cell preservation for spikes far from / near stim
%   summary_data.mat              cache of the trace pass
% Bands: mean +/- SEM across cells (waveforms), median with 25-75th percentile (spectra),
% bootstrap 95% CI of the median across cells (paired / gain panels).
arguments
    config = []   % name of a config in configs/analysis (required if there are several) or a cfg struct
end
close all;

%% Config
[root_path, code_path] = setup_analysis_paths(); %#ok<ASGLU>
cfg = load_analysis_config(config);
recompute   = false;   % true: redo the trace pass even if summary_data.mat exists
min_spikes  = 5;       % a cell needs this many spikes (in a condition) to enter a waveform panel
spike_hw    = 15;      % half-width for the per-spike preservation score, frames
wf_hw       = 100;     % half-width of the stim / non-stim waveforms, frames
psd_len     = 128;     % Welch segment length for the noise spectra, frames
nboot       = 2000;
rng(1);
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
recs    = load(fullfile(save_dir, 'recs.mat')).recs;
metrics = load(fullfile(save_dir, 'metrics.mat')).metrics;
g       = load(fullfile(save_dir, 'gains.mat')).g;
den_models = cfg.models;
all_models = [{'raw'}, den_models];
nM = numel(all_models);
colors = model_color_table(nM);   % one per model, grows with the number of models
lab = strrep(all_models, '_', '\_');

%% Aligned per-cell tables (rows follow recs)
hashes = string({recs.cell_hash})';
nC = numel(hashes);
row = nan(nC, nM);
for mi = 1:nM
    [tf, loc] = ismember(hashes, metrics.cell_hash(metrics.model == all_models{mi}));
    idx = find(metrics.model == all_models{mi});
    row(tf, mi) = idx(loc(tf));
end
have = all(~isnan(row), 2);
sc = nan(nC, 1);  sc(have) = metrics.spike_height(row(have, 1));          % raw spike height, the unit
nv = zeros(nC, 1); nv(have) = metrics.n_valid_spikes(row(have, 1));
good = have & isfinite(sc) & sc > 0;
fprintf('%d cells with metrics (%d animals); %d with positive raw spike height; %d with >= %d spikes.\n', ...
    nnz(have), numel(unique({recs(have).anim_id})), nnz(good), nnz(good & nv >= min_spikes), min_spikes);

%% Trace pass: per-spike preservation, stim / non-stim waveforms, noise spectra
cache = fullfile(save_dir, 'summary_data.mat');
if isfile(cache) && ~recompute
    D = load(cache);
else
    nS = 2*wf_hw + 1;
    wf_ns = nan(nC, nM, nS); wf_st = nan(nC, nM, nS);      % mean waveform, non-stim / in-stim spikes (raw spike heights)
    r_ns = nan(nC, numel(den_models)); r_st = r_ns;         % per-cell median per-spike r vs raw
    n_ns = zeros(nC, 1); n_st = zeros(nC, 1);
    psd = []; freqs = [];
    sess_paths = unique(string({recs.session_path}), 'stable');
    for si = 1:numel(sess_paths)
        sp_path = char(sess_paths(si));
        disk_path = to_local_path(sp_path, root_path);
        idx_cells = find(strcmp({recs.session_path}, sp_path));
        idx_cells = idx_cells(good(idx_cells));
        if isempty(idx_cells), continue; end
        try
            TR = cell(1, nM);
            for mi = 1:nM
                tr_ = load_model_trace(disk_path, all_models{mi}, cfg.use_template);
                TR{mi} = tr_;                                          % no detrending, as in compute_trace_metrics
            end
            smask = load_stim_mask(disk_path, size(TR{1}, 1), cfg);
        catch err
            warning('Skipping session %s (resolved to %s): %s', sp_path, disk_path, err.message); continue;
        end
        cs = [0; cumsum(smask(:))];
        for ci = idx_cells(:)'
            r = recs(ci);
            M = cellfun(@(x) x(:, r.cell_id) / sc(ci), TR, 'UniformOutput', false);   % raw spike heights
            n = numel(M{1});
            % noise spectra
            ni = r.noise_start : min(r.noise_start + r.noise_len - 1, n);
            for mi = 1:nM
                [P, freqs] = psd_welch(M{mi}(ni), 1 / r.dt, psd_len);
                if isempty(psd), psd = nan(nC, nM, numel(P)); end
                psd(ci, mi, :) = P;
            end
            % spikes
            hw = max(wf_hw, spike_hw);
            ok = r.spike_idx(r.spike_idx > hw & r.spike_idx < n - hw);
            if isempty(ok), continue; end
            a_ = max(ok - cfg.stim_margin, 1); b_ = min(ok + cfg.stim_margin, numel(smask));
            ns = (cs(b_ + 1) - cs(a_)) == 0;                     % no stim frame within stim_margin
            win = -spike_hw:spike_hw;
            Sn = cellfun(@(x) reshape(x(ok(:) + win), numel(ok), numel(win)), M, 'UniformOutput', false);
            zr = zscore(Sn{1}, 0, 2);
            sr = zeros(numel(ok), numel(den_models));
            for mi = 1:numel(den_models)
                sr(:, mi) = sum(zr .* zscore(Sn{mi+1}, 0, 2), 2) / (numel(win) - 1);
            end
            n_ns(ci) = nnz(ns); n_st(ci) = nnz(~ns);
            for cond = 1:2
                sel = (cond == 1) == ns;                          % cond 1: non-stim, 2: in-stim
                if nnz(sel) < min_spikes, continue; end
                for mi = 1:nM
                    snip = reshape(M{mi}(ok(sel) + (-wf_hw:wf_hw)), nnz(sel), nS);
                    w = mean(snip, 1); w = w - median(w);
                    if cond == 1, wf_ns(ci, mi, :) = w; else, wf_st(ci, mi, :) = w; end
                end
                rr = median(sr(sel, :), 1, 'omitnan');
                if cond == 1, r_ns(ci, :) = rr; else, r_st(ci, :) = rr; end
            end
        end
        fprintf('trace pass: session %d/%d\n', si, numel(sess_paths));
    end
    D = struct('wf_ns', wf_ns, 'wf_st', wf_st, 'r_ns', r_ns, 'r_st', r_st, 'n_ns', n_ns, 'n_st', n_st, ...
        'psd', psd, 'freqs', freqs, 'wf_hw', wf_hw, 'min_spikes', min_spikes);
    save(cache, '-struct', 'D', '-v7.3');
end

%% Figure 1: overview
WF = nan(nC, nM, 1001);
for mi = 1:nM
    for ci = find(good & nv >= min_spikes)'
        w = metrics.waveform{row(ci, mi)};
        WF(ci, mi, :) = (w(:)' - median(w)) / sc(ci);
    end
end
dt_ms = recs(1).dt * 1000;
Lh = 500;

fig = figure('Color', 'w', 'Position', [50 50 1700 950], 'Visible', 'off');
tl = tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile; hold on;                                              % grand average, zoom
grand_avg(squeeze_models(WF), (-50:50) * dt_ms, Lh + 1 + (-50:50), colors, lab);
xlabel('ms from spike'); ylabel('raw spike heights'); title(sprintf('Grand-average waveform (n = %d cells)', nnz(good & nv >= min_spikes)));
legend('Location', 'northeast', 'Interpreter', 'tex', 'FontSize', 8);

nexttile; hold on;                                              % grand average, full
grand_avg(squeeze_models(WF), (-Lh:Lh) * dt_ms, 1:1001, colors, lab);
xlabel('ms from spike'); title('Grand-average waveform, full snippet');

nexttile; hold on;                                              % noise spectra
keep = good & ~any(isnan(D.psd(:, :, 1)), 2);
for mi = 1:nM
    P = squeeze(D.psd(keep, mi, :));
    f = D.freqs(2:end);
    band(f, nanq(P(:, 2:end), 0.25), nanq(P(:, 2:end), 0.75), colors(mi,:));
    plot(f, nanq(P(:, 2:end), 0.5), 'Color', colors(mi,:), 'LineWidth', 1.8);
end
set(gca, 'XScale', 'log', 'YScale', 'log'); grid on; box on;
xlabel('Frequency (Hz)'); ylabel('Noise PSD (raw spike heights^2 / Hz)');
title(sprintf('Noise-window spectrum (median, 25-75%%; n = %d)', nnz(keep)));

% paired PSNR (paper SNR disabled; add back {'snr_paper_db', 'Paper SNR (dB)'} as a second row to re-enable)
metric = {'psnr_db', 'PSNR (dB)'};
for k = 1:size(metric, 1)
    nexttile; hold on;
    V = nan(nC, nM);
    for mi = 1:nM, V(have, mi) = real(metrics.(metric{k,1})(row(have, mi))); end
    if k == 1, V(~good, :) = NaN; end                        % PSNR is undefined for non-positive spike height
    V(~all(isfinite(V), 2), :) = NaN;
    ok_ = ~isnan(V(:, 1));
    plot(1:nM, V(ok_, :)', '-', 'Color', [0 0 0 0.10]);
    txt = cell(1, nM - 1);
    for mi = 1:nM
        [m_, ci_] = boot_median(V(ok_, mi), nboot);
        errorbar(mi, m_, m_ - ci_(1), ci_(2) - m_, 'o', 'Color', colors(mi,:), 'MarkerFaceColor', colors(mi,:), ...
            'LineWidth', 2, 'MarkerSize', 8);
        if mi > 1
            [d_, dci] = boot_median(V(ok_, mi) - V(ok_, 1), nboot);
            txt{mi-1} = sprintf('%s: %+.2f [%+.2f, %+.2f] dB', strrep(all_models{mi}, '_', '\_'), d_, dci(1), dci(2));
        end
    end
    set(gca, 'XTick', 1:nM, 'XTickLabel', lab, 'XLim', [0.5 nM + 0.5], 'TickLabelInterpreter', 'tex');
    ylabel(metric{k,2}); grid on; box on;
    title(sprintf('%s, paired (n = %d cells)', metric{k,2}, nnz(ok_)));
    text(0.02, 0.98, [{'median change vs raw [95% CI]:'}, txt], 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontSize', 8, 'BackgroundColor', [1 1 1 0.8]);
end

nexttile; hold on;                                              % gain decomposition
qty = {'retention', 'noise_reduction', 'snr_gain'};
qlab = {'Spike retention', 'Noise reduction', 'Total SNR gain'};
for qi = 1:numel(qty)
    for mi = 1:numel(den_models)
        v = g.(qty{qi})(g.model == den_models{mi});
        v = v(isfinite(v) & v > 0);
        [m_, ci_] = boot_median(v, nboot);
        x = qi + (mi - 1.5) * 0.2;
        errorbar(x, m_, m_ - ci_(1), ci_(2) - m_, 'o', 'Color', colors(mi+1,:), 'MarkerFaceColor', colors(mi+1,:), ...
            'LineWidth', 2, 'MarkerSize', 8, 'HandleVisibility', 'off');
        text(x + 0.03, m_, sprintf(' %.2f', m_), 'FontSize', 8);
    end
end
for mi = 1:numel(den_models)                                     % legend entries
    plot(nan, nan, 'o', 'Color', colors(mi+1,:), 'MarkerFaceColor', colors(mi+1,:), 'DisplayName', den_models{mi});
end
yline(1, 'k--', 'HandleVisibility', 'off');
set(gca, 'YScale', 'log', 'XTick', 1:numel(qty), 'XTickLabel', qlab, 'XLim', [0.5 numel(qty) + 0.5]);
ylabel('x raw (median, 95% CI)'); grid on; box on; legend('Location', 'best', 'Interpreter', 'none', 'FontSize', 8);
title(sprintf('Gain decomposition (n = %d cells)', numel(unique(g.cell_hash))));

title(tl, 'SUPPORT vs raw, dataset summary (unit = cell)');
exportgraphics(fig, fullfile(save_dir, 'summary_overview.png'), 'Resolution', 150); close(fig);

%% Figure 2: stim vs non-stim
fig = figure('Color', 'w', 'Position', [50 50 1700 500], 'Visible', 'off');
tl = tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
conds = {'wf_ns', 'Spikes > stim margin from stim'; 'wf_st', 'Spikes within stim margin'};
zoom_ = wf_hw - 50 : wf_hw + 50;                                 % +/- 50 frames of the +/- wf_hw snippet
for k = 1:2
    nexttile; hold on;
    W = D.(conds{k,1});
    grand_avg(W, (-50:50) * dt_ms, wf_hw + 1 + (-50:50), colors, lab);
    n_ = nnz(~isnan(W(:, 1, 1)));
    title(sprintf('%s (n = %d cells)', conds{k,2}, n_), 'FontSize', 10);
    xlabel('ms from spike'); ylabel('raw spike heights');
    if k == 1, legend('Location', 'northeast', 'Interpreter', 'tex', 'FontSize', 8); end
end
nexttile; hold on;                                               % per-cell preservation, ECDF
ls = {'-', '--'};
for mi = 1:numel(den_models)
    for k = 1:2
        v = D.(ternary(k == 1, 'r_ns', 'r_st'))(:, mi); v = sort(v(isfinite(v)));
        if isempty(v), continue; end
        stairs(v, (1:numel(v)) / numel(v), ls{k}, 'Color', colors(mi+1,:), 'LineWidth', 1.6, ...
            'DisplayName', sprintf('%s, %s (n=%d)', den_models{mi}, ternary(k == 1, 'non-stim', 'near stim'), numel(v)));
    end
end
xlabel('Per-cell median r vs raw (per-spike snippet)'); ylabel('Fraction of cells'); grid on; box on;
legend('Location', 'northwest', 'Interpreter', 'none', 'FontSize', 8);
title('Spike preservation: solid = non-stim, dashed = near stim', 'FontSize', 10);
title(tl, sprintf('Stim vs non-stim spikes (need >= %d spikes per condition per cell; margin = %d frames)', ...
    min_spikes, cfg.stim_margin));
exportgraphics(fig, fullfile(save_dir, 'summary_stim_vs_nonstim.png'), 'Resolution', 150); close(fig);
fprintf('Done. Figures in %s\n', save_dir);

end

%% -------- Local helpers --------
function W = squeeze_models(WF)
W = WF;   % nC x nM x nSamples
end

function grand_avg(W, x, cols, colors, lab)
% mean +/- SEM across cells (dim 1) of W(:, model, samples(cols))
for mi = 1:size(W, 2)
    A = squeeze(W(:, mi, cols));
    n = sum(~isnan(A), 1);
    mu = mean(A, 1, 'omitnan');
    se = std(A, 0, 1, 'omitnan') ./ sqrt(max(n, 1));
    band(x, mu - se, mu + se, colors(mi,:));
    plot(x, mu, 'Color', colors(mi,:), 'LineWidth', 1.8, 'DisplayName', lab{mi});
end
grid on; box on; xlim(x([1 end]));
end

function band(x, lo, hi, c)
x = x(:)'; lo = lo(:)'; hi = hi(:)';
ok = ~(isnan(lo) | isnan(hi));
fill([x(ok) fliplr(x(ok))], [lo(ok) fliplr(hi(ok))], c, 'FaceAlpha', 0.22, 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
end

function [m, ci] = boot_median(v, nboot)
v = v(isfinite(v));
m = median(v);
if numel(v) < 2, ci = [m m]; return; end
b = median(v(randi(numel(v), numel(v), nboot)), 1);
b = sort(b);
ci = [b(max(1, round(0.025 * nboot))), b(min(nboot, round(0.975 * nboot)))];
end

function q = nanq(A, p)
% quantile p of each column of A, ignoring NaN
q = nan(1, size(A, 2));
for j = 1:size(A, 2)
    v = sort(A(~isnan(A(:, j)), j));
    if isempty(v), continue; end
    pos = 1 + p * (numel(v) - 1);
    lo = floor(pos); hi = ceil(pos);
    q(j) = v(lo) + (pos - lo) * (v(hi) - v(lo));
end
end

function [P, f] = psd_welch(x, fs, L)
% one-sided Welch PSD, Hann window, 50% overlap (no toolbox needed)
x = x(:) - mean(x);
w = 0.5 - 0.5 * cos(2 * pi * (0:L-1)' / (L - 1));
hop = L / 2; nseg = floor((numel(x) - L) / hop) + 1;
S = zeros(L/2 + 1, 1);
for k = 1:nseg
    F = fft(x((k-1) * hop + (1:L)) .* w);
    S = S + abs(F(1:L/2 + 1)).^2;
end
P = S / (nseg * fs * sum(w.^2));
P(2:end-1) = 2 * P(2:end-1);
f = (0:L/2)' * fs / L;
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

