function stim_vs_nostim_comparison(config)
% stim_vs_nostim_comparison.m
% Usage: stim_vs_nostim_comparison()  or  stim_vs_nostim_comparison('my_config')  - config = name of a
% config file in configs/analysis (see load_analysis_config.m).
% Compare metrics between recordings with NO stimulation at all and
% recordings that had stim, for each model. Reads metrics.mat (and
% gains.mat if present) from support_model_comparison.m / model_comparison_plots.m;
% classifies sessions with classify_sessions_by_stim.m (cached, resumable).
%
% A session is "no_stim" only if stim data was found and no frame crossed
% cfg.stim_thresh; "unknown" (no stim data found) is a separate group, kept
% out of the comparison by default (include_unknown = false below).
%
% Outputs (Erin/support_data/model_comparison/):
%   stim_regions.mat            table `stim`: per-session classification
%   stim_group_metrics.csv      metrics.mat joined with each row's stim group
%   stim_vs_nostim.png          per-model, per-metric comparison
arguments
    config = []   % name of a config in configs/analysis (required if there are several) or a cfg struct
end
close all;

include_unknown = false;   % true: plot the "unknown" (no stim data) group too

[root_path, ~] = setup_analysis_paths();
cfg = load_analysis_config(config);
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
metrics_file = fullfile(save_dir, 'metrics.mat');
gains_file = fullfile(save_dir, 'gains.mat');
assert(isfile(metrics_file), 'No metrics.mat yet - run support_model_comparison.m first.');

metrics = load(metrics_file, 'metrics').metrics;
stim = classify_sessions_by_stim(cfg);

%% Join: one group label per row of metrics, by session_path
% metrics.session_path may have been saved by a headless run on a different
% machine/OS (see to_local_path.m); stim.session_path is always in this
% machine's form (from load_session_list inside classify_sessions_by_stim).
local_session_path = arrayfun(@(p) string(to_local_path(char(p), root_path)), metrics.session_path);
[tf, loc] = ismember(local_session_path, stim.session_path);
group = repmat("unknown", height(metrics), 1);
group(tf & stim.has_stim(loc(tf))) = "has_stim";
group(tf & ~stim.has_stim(loc(tf)) & stim.had_stim_data(loc(tf))) = "no_stim";
metrics.stim_group = group;

n_cells_by_group = groupsummary(unique(metrics(:, {'cell_hash','stim_group'})), 'stim_group');
disp(n_cells_by_group);
n_sessions_by_group = groupsummary(stim, {'had_stim_data','has_stim'});
disp(n_sessions_by_group);

writetable(metrics(:, {'cell_hash','session_path','session_name','cell_id','model','stim_group', ...
    'psnr_db','spike_height','noise_std'}), fullfile(save_dir, 'stim_group_metrics.csv'));  % snr_paper_db disabled

if ~include_unknown
    metrics = metrics(metrics.stim_group ~= "unknown", :);
end
groups = ["no_stim", "has_stim"];
group_colors = [0.20 0.55 0.35; 0.75 0.25 0.20];

%% Optional: fold in gain metrics (retention / noise_reduction / snr_gain)
panels = {'psnr_db', 'PSNR (dB)', 0};  % snr_paper_db disabled; add back {'snr_paper_db', 'SNR, paper definition (dB)', 0} to re-enable
if isfile(gains_file)
    g = load(gains_file, 'g').g;
    % stim_group is per cell (not per model), so join on cell_hash alone
    cell_group = unique(metrics(:, {'cell_hash','stim_group'}));
    [tf, loc] = ismember(g.cell_hash, cell_group.cell_hash);
    g.stim_group = repmat("unknown", height(g), 1);
    g.stim_group(tf) = cell_group.stim_group(loc(tf));
    if ~include_unknown, g = g(g.stim_group ~= "unknown", :); end
    panels = [panels; {'retention', 'Spike retention (x)', 1; 'noise_reduction', 'Noise reduction (x)', 1; ...
        'snr_gain', 'Total SNR gain (x)', 1}];
else
    g = table();
    fprintf('No gains.mat found; run model_comparison_plots.m first for retention/noise_reduction/snr_gain panels.\n');
end

%% Per model x group summary + rank-sum test
all_models = unique(metrics.model, 'stable');
fprintf('\nMedian by model x stim group (Wilcoxon rank-sum p, no_stim vs has_stim):\n');
for mi = 1:numel(all_models)
    m = all_models(mi);
    a = metrics.psnr_db(metrics.model == m & metrics.stim_group == "no_stim");
    b = metrics.psnr_db(metrics.model == m & metrics.stim_group == "has_stim");
    p = ranksum_safe(a, b);
    fprintf('  %-24s psnr_db: no_stim=%.2f (n=%d)  has_stim=%.2f (n=%d)  p=%.3g\n', ...
        m, median(a, 'omitnan'), nnz(~isnan(a)), median(b, 'omitnan'), nnz(~isnan(b)), p);
end

%% Figure: one panel per metric, models on x, dodged by stim group
fig = figure('Color', 'w', 'Position', [100 100 300*size(panels,1)+100 450], 'Visible', 'off');
tl = tiledlayout(1, size(panels, 1), 'TileSpacing', 'compact');
for pnl = 1:size(panels, 1)
    var = panels{pnl, 1};
    is_gain = ismember(var, {'retention','noise_reduction','snr_gain'});
    src = metrics; if is_gain, src = g; end
    if is_gain, mods = unique(src.model, 'stable'); else, mods = all_models; end
    nexttile; hold on;
    legend_h = gobjects(1, numel(groups));
    for mi = 1:numel(mods)
        for gi = 1:numel(groups)
            v = src.(var)(src.model == mods(mi) & src.stim_group == groups(gi));
            v = v(isfinite(v));
            x0 = mi + (gi - 1.5) * 0.28;
            h = scatter(x0 + 0.08*randn(size(v)), v, 12, group_colors(gi,:), 'filled', 'MarkerFaceAlpha', 0.4);
            if mi == 1, legend_h(gi) = h; end
            if ~isempty(v)
                plot(x0 + [-0.12 0.12], median(v)*[1 1], 'Color', group_colors(gi,:), 'LineWidth', 2.5, ...
                    'HandleVisibility', 'off');
            end
        end
        a = src.(var)(src.model == mods(mi) & src.stim_group == "no_stim");
        b = src.(var)(src.model == mods(mi) & src.stim_group == "has_stim");
        p = ranksum_safe(a, b);
        yl = ylim;
        text(mi, yl(2), sig_label(p), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 9);
    end
    if panels{pnl,3}, set(gca, 'YScale', 'log'); yline(1, 'k--', 'HandleVisibility', 'off'); end
    set(gca, 'XTick', 1:numel(mods), 'XTickLabel', strrep(cellstr(mods), '_', '\_'), ...
        'XLim', [0.4 numel(mods)+0.6]);
    ylabel(panels{pnl, 2}); grid on; box on;
    if pnl == 1
        legend(legend_h, cellstr(groups), 'Location', 'best');
    end
end
title(tl, sprintf('No-stim vs stim recordings (n cells: no\\_stim=%d, has\\_stim=%d%s)', ...
    group_count(n_cells_by_group, "no_stim"), group_count(n_cells_by_group, "has_stim"), ...
    iff(include_unknown, sprintf(', unknown=%d', group_count(n_cells_by_group, "unknown")), '')), ...
    'Interpreter', 'tex');
exportgraphics(fig, fullfile(save_dir, 'stim_vs_nostim.png'), 'Resolution', 150); close(fig);
fprintf('Saved %s\n', fullfile(save_dir, 'stim_vs_nostim.png'));

%% Denoised vs raw PSNR per cell (raw is not in the plots above, so pull it from metrics)
raw = metrics(metrics.model == "raw", :);
den = metrics(metrics.model ~= "raw", :);
[tf, loc] = ismember(den.cell_hash, raw.cell_hash);
den = den(tf, :);
den.psnr_raw = raw.psnr_db(loc(tf));
den.dpsnr = den.psnr_db - den.psnr_raw;
den_models = unique(den.model, 'stable');
model_colors = model_color_table(numel(den_models) + 1);
model_colors = model_colors(2:end, :);   % skip raw's gray; same colors as model_comparison_plots.m

% Outliers: robust z-score of dPSNR within each model x group (median/MAD), plus anything
% far off the raw=denoised diagonal. Written to CSV so the recordings can be inspected.
den.dpsnr_z = nan(height(den), 1);
for mi = 1:numel(den_models)
    for gi = 1:numel(groups)
        idx = den.model == den_models(mi) & den.stim_group == groups(gi);
        d = den.dpsnr(idx);
        den.dpsnr_z(idx) = (d - median(d, 'omitnan')) / (1.4826 * mad(d, 1));
    end
end
outlier_z = 6;
den.is_outlier = abs(den.dpsnr_z) > outlier_z | den.psnr_db > 40 | den.psnr_raw > 40;
outliers = sortrows(den(den.is_outlier, {'cell_hash','session_path','session_name','cell_id','model', ...
    'stim_group','psnr_raw','psnr_db','dpsnr','dpsnr_z','spike_height','noise_std'}), 'dpsnr', 'descend');
writetable(outliers, fullfile(save_dir, 'stim_vs_nostim_outliers.csv'));
fprintf('\n%d outlier rows (|robust z of dPSNR| > %g or PSNR > 40 dB) -> stim_vs_nostim_outliers.csv\n', height(outliers), outlier_z);
disp(outliers(:, {'session_name','cell_id','model','stim_group','psnr_raw','psnr_db','dpsnr_z'}));

% Axis limits from the bulk of the data; outliers are drawn as triangles clipped to the edge
vals = [den.psnr_raw(~den.is_outlier); den.psnr_db(~den.is_outlier)];
lim = [floor(min(vals)/5)*5 - 2, ceil(max(vals)/5)*5 + 2];

% Figure 2: one panel per model, colored by stim group
fig = figure('Color', 'w', 'Position', [100 100 330*numel(den_models)+80 400], 'Visible', 'off');
tl = tiledlayout(1, numel(den_models), 'TileSpacing', 'compact');
for mi = 1:numel(den_models)
    nexttile; hold on;
    hs = gobjects(1, numel(groups));
    for gi = 1:numel(groups)
        s = den(den.model == den_models(mi) & den.stim_group == groups(gi), :);
        hs(gi) = scatter_clipped(s.psnr_raw, s.psnr_db, lim, group_colors(gi,:));
    end
    plot(lim, lim, 'k--', 'HandleVisibility', 'off');
    axis square; xlim(lim); ylim(lim); grid on; box on;
    xlabel('PSNR (dB), raw'); title(strrep(char(den_models(mi)), '_', '\_'), 'FontSize', 9);
    if mi == 1
        ylabel('PSNR (dB), denoised');
        legend(hs, strcat(cellstr(groups), " (n=", string(arrayfun(@(k) nnz(den.model == den_models(1) & den.stim_group == groups(k)), 1:2)), ")"), 'Location', 'northwest', 'Interpreter', 'none');
    end
end
title(tl, 'Denoised vs raw PSNR by model (triangles = outliers clipped to axis edge)');
exportgraphics(fig, fullfile(save_dir, 'stim_vs_nostim_psnr_by_model.png'), 'Resolution', 150); close(fig);

% Figure 3: one panel per stim group, colored by model
fig = figure('Color', 'w', 'Position', [100 100 900 430], 'Visible', 'off');
tl = tiledlayout(1, 2, 'TileSpacing', 'compact');
for gi = 1:numel(groups)
    nexttile; hold on;
    hs = gobjects(1, numel(den_models));
    for mi = 1:numel(den_models)
        s = den(den.model == den_models(mi) & den.stim_group == groups(gi), :);
        hs(mi) = scatter_clipped(s.psnr_raw, s.psnr_db, lim, model_colors(mi,:));
    end
    plot(lim, lim, 'k--', 'HandleVisibility', 'off');
    axis square; xlim(lim); ylim(lim); grid on; box on;
    xlabel('PSNR (dB), raw'); ylabel('PSNR (dB), denoised');
    title(sprintf('%s (n cells=%d)', strrep(char(groups(gi)), '_', '\_'), group_count(n_cells_by_group, groups(gi))));
    if gi == 1, legend(hs, strrep(cellstr(den_models), '_', '\_'), 'Location', 'northwest', 'FontSize', 8); end
end
title(tl, 'Denoised vs raw PSNR: no stim vs stim recordings (triangles = outliers clipped to axis edge)');
exportgraphics(fig, fullfile(save_dir, 'stim_vs_nostim_psnr_by_group.png'), 'Resolution', 150); close(fig);
fprintf('Saved stim_vs_nostim_psnr_by_model.png and stim_vs_nostim_psnr_by_group.png in %s\n', save_dir);

end

%% -------- Local helpers --------
function h = scatter_clipped(x, y, lim, col)
    % points outside lim are clamped to the edge and drawn as triangles
    out = x < lim(1) | x > lim(2) | y < lim(1) | y > lim(2);
    xc = min(max(x, lim(1)), lim(2)); yc = min(max(y, lim(1)), lim(2));
    h = scatter(xc(~out), yc(~out), 14, col, 'filled', 'MarkerFaceAlpha', 0.35);
    if any(out)
        scatter(xc(out), yc(out), 40, col, '^', 'filled', 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
    end
end

function p = ranksum_safe(a, b)
    a = a(isfinite(a)); b = b(isfinite(b));
    if numel(a) < 3 || numel(b) < 3, p = NaN; else, p = ranksum(a, b); end
end

function s = sig_label(p)
    if isnan(p), s = 'n/a';
    elseif p < 0.001, s = 'p<0.001';
    else, s = sprintf('p=%.3g', p);
    end
end

function out = iff(cond, a, b)
    if cond, out = a; else, out = b; end
end

function n = group_count(group_summary, name)
    i = strcmp(group_summary.stim_group, name);
    if any(i), n = group_summary.GroupCount(i); else, n = 0; end
end
