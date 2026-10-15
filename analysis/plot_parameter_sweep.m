function plot_parameter_sweep(config, groups, epochs, dirnames, nv)
%PLOT_PARAMETER_SWEEP  Median PSNR vs SUPPORT epoch, from the denoised outputs of a sweep.
%
%   plot_parameter_sweep('config_DSI', groups, epochs, dirnames)
%
% Last stage of run_headless_parameter_analysis.sh. Runs support_model_comparison on the
% sweep's output folders (cfg.models = dirnames, raw included automatically) and plots,
% per group (one SUPPORT model), the median per-cell PSNR against epoch with an IQR band,
% plus the raw trace's median as a dashed line.
%
%   config     analysis config name (configs/analysis) or cfg struct, used as the base
%   groups     cellstr, one label per run (the SUPPORT model the run used); one line each
%   epochs     numeric vector, one per run (x axis)
%   dirnames   cellstr, one per run: the support_* folder under each session holding that run
%
% Name-values:
%   tag            suffix for the output folder: <filestr>_<tag>   (default 'epoch_sweep')
%   dataset        overrides cfg.dataset (so {dataset} paths resolve for this sweep)
%   sessions_file  overrides cfg.sessions_file (use the file the preprocessing ran on)
%
% Writes <fanlab root>/<cfg.save_subdir>/<filestr>_<tag>/ : the usual support_model_comparison
% outputs, plus epoch_vs_psnr.png and epoch_vs_psnr.csv. Noise windows are copied from the
% base config's folder when it has them, so reviewed windows carry over.
arguments
    config
    groups cell
    epochs (1,:) double
    dirnames cell
    nv.tag (1,:) char = 'epoch_sweep'
    nv.dataset = ''
    nv.sessions_file = ''
end
assert(numel(groups) == numel(epochs) && numel(epochs) == numel(dirnames), ...
    'groups, epochs and dirnames need one entry per run.');
groups = cellfun(@char, groups(:)', 'UniformOutput', false);
dirnames = cellfun(@char, dirnames(:)', 'UniformOutput', false);

[root_path, ~] = setup_analysis_paths();
if isstruct(config), cfg = config; else, cfg = feval(char(config)); end
if ~isempty(nv.dataset), cfg.dataset = char(nv.dataset); end
if ~isempty(nv.sessions_file), cfg.sessions_file = char(nv.sessions_file); end
cfg = load_analysis_config(cfg);

base_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
cfg.filestr = [cfg.filestr '_' nv.tag];
cfg.models = unique(dirnames, 'stable');
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
if ~exist(fullfile(save_dir, 'noise_regions.mat'), 'file') && exist(fullfile(base_dir, 'noise_regions.mat'), 'file')
    copyfile(fullfile(base_dir, 'noise_regions.mat'), save_dir);
    fprintf('Copied noise windows from %s\n', base_dir);
end

support_model_comparison(cfg);

%% per-run PSNR stats
metrics = load(fullfile(save_dir, 'metrics.mat')).metrics;
mname = string(metrics.model);
raw_med = median(metrics.psnr_db(mname == "raw"), 'omitnan');
n = numel(epochs);
[n_cells, med, q1, q3] = deal(nan(n, 1));
for i = 1:n
    p = metrics.psnr_db(mname == dirnames{i});
    if isempty(p)
        warning('No PSNR rows for %s (did its preprocessing finish?).', dirnames{i});
        continue
    end
    n_cells(i) = numel(p);
    med(i) = median(p, 'omitnan');
    q1(i) = prctile(p, 25);
    q3(i) = prctile(p, 75);
end
res = table(string(groups(:)), epochs(:), string(dirnames(:)), n_cells, med, q1, q3, ...
    'VariableNames', {'group', 'epoch', 'dirname', 'n_cells', 'median_psnr_db', 'q25_psnr_db', 'q75_psnr_db'});
res = sortrows(res, {'group', 'epoch'});
writetable(res, fullfile(save_dir, 'epoch_vs_psnr.csv'));

%% plot
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 640 440]);
ax = axes(fig); hold(ax, 'on');
ug = unique(groups, 'stable');
colors = model_color_table(numel(ug) + 1);
h = gobjects(numel(ug), 1);
for g = 1:numel(ug)
    r = res(res.group == ug{g} & ~isnan(res.median_psnr_db), :);
    if isempty(r), continue, end
    c = colors(g + 1, :);
    fill(ax, [r.epoch; flipud(r.epoch)], [r.q25_psnr_db; flipud(r.q75_psnr_db)], c, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    h(g) = plot(ax, r.epoch, r.median_psnr_db, '-o', 'Color', c, 'LineWidth', 1.5, 'MarkerFaceColor', c);
end
yline(ax, raw_med, '--', 'raw', 'Color', colors(1, :), 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
xlabel(ax, 'SUPPORT training epoch'); ylabel(ax, 'median PSNR (dB)');
title(ax, sprintf('%s: PSNR vs epoch (median, IQR band)', strrep(cfg.filestr, '_', '\_')));
grid(ax, 'on'); box(ax, 'off');
ok = isgraphics(h);
if any(ok), legend(ax, h(ok), strrep(ug(ok), '_', '\_'), 'Location', 'best'); end
exportgraphics(fig, fullfile(save_dir, 'epoch_vs_psnr.png'), 'Resolution', 200);
close(fig);
fprintf('Saved %s\n', fullfile(save_dir, 'epoch_vs_psnr.png'));
end
