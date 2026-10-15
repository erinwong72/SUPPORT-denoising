function model_comparison_plots(config)
% model_comparison_plots.m
% Usage: model_comparison_plots()  or  model_comparison_plots('my_config')  - config = name of a
% config file in configs/analysis (see load_analysis_config.m).
% Gain decomposition and per-cell trace plots for the SUPPORT model comparison.
% Reads recs.mat / metrics.mat written by support_model_comparison.m.
%
%   SNR gain = retention x noise reduction   (linear amplitude ratios vs raw)
%   retention        = spike_height_model / spike_height_raw
%   noise_reduction  = noise_std_raw / noise_std_model        (500-frame window)
%   snr_gain_db      = 20*log10(retention * noise_reduction) = psnr_db - psnr_db_raw
%   paper_delta_db   DISABLED (snr_paper_db is NaN, see compute_trace_metrics.m); was
%                    snr_paper_db_model - snr_paper_db_raw  (movmean estimator, for reference)
% Heights, noise std and plotted traces all come from the traces as given (no detrending),
% see compute_trace_metrics.m. Plots only shift traces by a display offset (stacking / zooms).
%
% Outputs (Erin/support_data/model_comparison/):
%   gains.mat / gains.csv    one row per cell x denoised model
%   gain_summary.png         retention vs noise reduction + per-model distributions
%   <FOV folder>/<session>_cell<k>.png   one per cell (FOV folder = animal_date_slice_FOV)
%       whole trace (all models stacked, units of raw spike height), spike
%       zooms (least / median / most preserved spike), mean waveform, gain bars
arguments
    config = []   % name of a config in configs/analysis (required if there are several) or a cfg struct
end
close all;

%% Config
[root_path, code_path] = setup_analysis_paths(); %#ok<ASGLU>
cfg = load_analysis_config(config);
spike_hw    = 15;    % half-width of snippet used to score per-spike preservation, frames
zoom_hw     = 30;    % half-width of the spike zoom panels, frames
wf_zoom_hw  = 50;    % half-width of the zoomed mean-waveform panel, frames
% resume: skip cells whose figure is newer than this script and than metrics.mat, so an
% interrupted run (or a MATLAB graphics hang) can be restarted without redoing everything
resume = true;
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
layout_time = datenum(2026, 10, 8, 12, 0, 0);   % bump when the figure layout changes (figures older than this are redrawn)
script_time = max(layout_time, dir(fullfile(save_dir, 'metrics.mat')).datenum);
recs    = load(fullfile(save_dir, 'recs.mat')).recs;
metrics = load(fullfile(save_dir, 'metrics.mat')).metrics;
% spike selection the metrics were computed with (support_model_comparison.m, resolved from 'auto')
metrics.trained = flag_trained_cells(metrics, cfg, root_path);   % recomputed from cfg.training_windows each run
plot_mode = 'all';
if isstruct(metrics.Properties.UserData) && isfield(metrics.Properties.UserData, 'stim_mode')
    plot_mode = metrics.Properties.UserData.stim_mode;
end
if ~ismember(cfg.stim_mode, {'auto', plot_mode})
    warning(['cfg.stim_mode is "%s" but metrics.mat was computed with "%s": rerun support_model_comparison ' ...
        'first, or these plots will not follow cfg.stim_mode.'], cfg.stim_mode, plot_mode);
end
den_models = cfg.models;
all_models = [{'raw'}, den_models];
colors = model_color_table(numel(all_models));   % raw, then one per model (grows with the number of models)

%% Gains
% cells whose mean waveform peak is negative get a negative retention and are
% left out of the plots
raw = metrics(metrics.model == "raw", :);
g = table();
for mi = 1:numel(den_models)
    t = metrics(metrics.model == den_models{mi}, :);
    [tf, loc] = ismember(t.cell_hash, raw.cell_hash);
    t = t(tf, :); r = raw(loc(tf), :);
    row = table(t.cell_hash, t.session_name, t.cell_id, t.model, t.n_valid_spikes, ...
        t.spike_height ./ r.spike_height, ...
        r.noise_std ./ t.noise_std, t.snr_paper_db - r.snr_paper_db, ...   % paper SNR disabled: NaN - NaN = NaN
        'VariableNames', {'cell_hash','session_name','cell_id','model','n_valid_spikes', ...
        'retention','noise_reduction','paper_delta_db'});
    row.snr_gain = row.retention .* row.noise_reduction;
    row.snr_gain_db = 20 * log10(row.snr_gain);
    row.check_psnr_diff = (t.psnr_db - r.psnr_db) - row.snr_gain_db;   % should be ~0
    g = [g; row]; %#ok<AGROW>
end
[tf_, loc_] = ismember(g.cell_hash + "|" + g.model, metrics.cell_hash + "|" + metrics.model);
g.trained = false(height(g), 1); g.trained(tf_) = metrics.trained(loc_(tf_));
g.dataset = repmat("", height(g), 1);
if ismember('dataset', metrics.Properties.VariableNames), g.dataset(tf_) = metrics.dataset(loc_(tf_)); end
ds_names = unique(g.dataset, 'stable'); ds_names = ds_names(ds_names ~= "");
multi_ds = numel(ds_names) > 1;      % several datasets pooled in one run: marker shape / dodge = dataset
if ~multi_ds, ds_names = ""; end
ds_marker = {'o', 's', '^', 'd', 'v', 'p'};
fprintf('max |snr_gain_db - dPSNR| = %.2g dB\n', max(abs(g.check_psnr_diff), [], 'omitnan'));
save(fullfile(save_dir, 'gains.mat'), 'g');
writetable(removevars(g, 'check_psnr_diff'), fullfile(save_dir, 'gains.csv'));
gain_summary_tbl = groupsummary(g, 'model', 'median', {'retention','noise_reduction','snr_gain','snr_gain_db'});  % paper_delta_db disabled (NaN)
disp(gain_summary_tbl);
writetable(gain_summary_tbl, fullfile(save_dir, 'gains_median_summary.csv'));
if multi_ds
    gain_by_ds = groupsummary(g, {'dataset', 'model'}, 'median', {'retention','noise_reduction','snr_gain','snr_gain_db'});
    disp(gain_by_ds);
    writetable(gain_by_ds, fullfile(save_dir, 'gains_median_summary_by_dataset.csv'));
end

%% Summary figure
fig = figure('Color', 'w', 'Position', [100 100 1500 700], 'Visible', 'off');
tl = tiledlayout(2, 4, 'TileSpacing', 'compact');
nexttile([2 2]); hold on;
for mi = 1:numel(den_models)
    for di = 1:numel(ds_names)
        s = g(g.model == den_models{mi} & g.retention > 0 & g.noise_reduction > 0, :);
        if multi_ds, s = s(s.dataset == ds_names(di), :); end
        tr_ = s.trained;
        scatter(s.noise_reduction(~tr_), s.retention(~tr_), 30, colors(mi+1,:), ds_marker{di}, 'filled', ...
            'MarkerFaceAlpha', 0.55, 'DisplayName', iff(di == 1, den_models{mi}, ''), ...
            'HandleVisibility', iff(di == 1, 'on', 'off'));
        if any(tr_)   % cells the model was trained on: same color, black ring
            scatter(s.noise_reduction(tr_), s.retention(tr_), 30, colors(mi+1,:), ds_marker{di}, 'filled', 'MarkerFaceAlpha', 0.55, ...
                'MarkerEdgeColor', 'k', 'LineWidth', 1.2, 'HandleVisibility', 'off');
        end
    end
end
if multi_ds   % legend entries for the dataset markers
    for di = 1:numel(ds_names)
        scatter(nan, nan, 30, [0.4 0.4 0.4], ds_marker{di}, 'filled', 'DisplayName', char(ds_names(di)));
    end
end
if any(g.trained), scatter(nan, nan, 30, 'o', 'MarkerEdgeColor', 'k', 'LineWidth', 1.2, 'DisplayName', 'trained on (black ring)'); end
set(gca, 'XScale', 'log', 'YScale', 'log'); grid on; axis square; box on;
xl = [0.4 4]; yl = [0.3 1.3];
xlim(xl); ylim(yl);
xg = logspace(log10(xl(1)), log10(xl(2)), 50);
for gain = [0.5 0.75 1 1.5 2 3]                   % iso-SNR-gain lines: retention = gain / noise_reduction
    plot(xg, gain ./ xg, ':', 'Color', [0.55 0.55 0.55], 'HandleVisibility', 'off');
    xt = min(xl(2), gain / yl(1)) * 0.93;          % label where the line meets the axes
    text(xt, gain / xt, sprintf('%gx', gain), 'Color', [0.35 0.35 0.35], 'FontSize', 9, ...
        'BackgroundColor', 'w', 'Margin', 0.5, 'Clipping', 'on');
end
xline(1, 'k--', 'HandleVisibility', 'off'); yline(1, 'k--', 'HandleVisibility', 'off');
xlabel('Noise reduction (raw noise std / model noise std)');
ylabel('Spike retention (model height / raw height)');
title('Per cell (dotted: iso-SNR-gain lines, total gain = retention x noise reduction)');
legend('Location', 'best', 'Interpreter', 'none');

panels = {'retention', 'Spike retention', 1; 'noise_reduction', 'Noise reduction (x)', 1; ...
          'snr_gain', 'Total SNR gain (x)', 1};
          % paper_delta_db disabled; add back {'paper_delta_db', 'Paper SNR change (dB, movmean)', 0} to re-enable
for pi_ = 1:size(panels, 1)
    nexttile; hold on;
    nD_ = numel(ds_names); dodge_ = linspace(-0.2, 0.2, max(nD_, 2)); if nD_ == 1, dodge_ = 0; end
    for mi = 1:numel(den_models)
        for di = 1:nD_
            sel_ = g.model == den_models{mi};
            if multi_ds, sel_ = sel_ & g.dataset == ds_names(di); end
            v = g.(panels{pi_,1})(sel_); tr_ = g.trained(sel_);
            if panels{pi_,3}, ok_ = isfinite(v) & v > 0; else, ok_ = isfinite(v); end
            v = v(ok_); tr_ = tr_(ok_);
            xc_ = mi + dodge_(di);
            x = xc_ + 0.12 / nD_ * randn(size(v));
            scatter(x(~tr_), v(~tr_), 12, colors(mi+1,:), ds_marker{di}, 'filled', 'MarkerFaceAlpha', 0.35);
            scatter(x(tr_), v(tr_), 12, colors(mi+1,:), ds_marker{di}, 'filled', 'MarkerFaceAlpha', 0.35, ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.8);     % trained-on cells: black ring
            plot(xc_ + [-0.3 0.3] / nD_, median(v) * [1 1], 'k-', 'LineWidth', 2);
            text(xc_, median(v), sprintf(' %.2f', median(v)), 'VerticalAlignment', 'bottom', 'FontSize', 8);
        end
    end
    yline(panels{pi_,3}, 'k--');     % 1 for ratios, 0 for the dB change
    if panels{pi_,3}, set(gca, 'YScale', 'log'); end
    set(gca, 'XTick', 1:numel(den_models), ...
        'XTickLabel', strrep(den_models, '_', '\_'), 'XLim', [0.4 numel(den_models)+0.6]);
    ylabel(panels{pi_,2}); grid on; box on;
end
title(tl, sprintf('SUPPORT gain vs raw (n = %d cells; black line = median%s%s)', numel(unique(g.cell_hash)), ...
    iff(any(g.trained), '; black ring = trained on', ''), iff(multi_ds, ['; marker = dataset: ' char(strjoin(ds_names, ', '))], '')));
exportgraphics(fig, fullfile(save_dir, 'gain_summary.png'), 'Resolution', 150); close(fig);

% trained_vs_heldout.csv (medians per model, trained-on vs held-out) is written by support_model_comparison.m

%% Per-cell figures
sess_paths = unique(string({recs.session_path}), 'stable');
% per-cell figures go in their own folder when the non-stim-periods view is on, so they never mix
% with the all-spike figures from other stim modes
fig_root = save_dir;
rec_ds = @(r) dataset_subfolder(r, multi_ds);   % per-dataset subfolder when several datasets are pooled
if strcmp(plot_mode, 'nonstim_periods'), fig_root = fullfile(save_dir, 'nonstim_periods'); end
n_done = 0; n_skipped_nospikes = 0;
for si = 1:numel(sess_paths)
    sp_path = char(sess_paths(si));
    disk_path = to_local_path(sp_path, root_path);
    idx_cells = find(strcmp({recs.session_path}, sp_path));
    % a figure lives in nonstim_recordings/ (no stim in the recording) or in the regular folder
    % (stim / unknown); which one is only known after the stim mask is loaded, so check both
    fresh = false(1, numel(idx_cells));
    for q = 1:numel(idx_cells)
        k_ = idx_cells(q);
        fn_ = sprintf('%s_cell%d.png', regexprep(recs(k_).session_name, '[^\w\-]', '_'), recs(k_).cell_id);
        for base_ = {fig_root, fullfile(fig_root, 'nonstim_recordings')}
            f_ = fullfile(base_{1}, rec_ds(recs(k_)), fov_folder(recs(k_)), fn_);
            fresh(q) = fresh(q) || (isfile(f_) && dir(f_).datenum > script_time);
        end
    end
    if resume && all(fresh)
        n_done = n_done + numel(idx_cells); continue;
    end
    try                                                  % load each model once per session
        TR = cell(1, numel(all_models));
        for mi = 1:numel(all_models)
            tr_ = load_model_trace(disk_path, all_models{mi}, cfg.use_template);
            TR{mi} = tr_;   % no detrending, as in compute_trace_metrics
        end
    catch err
        warning('Skipping session %s (resolved to %s): %s', sp_path, disk_path, err.message); continue;
    end
    % stim / blue-light frames (same recipe as the noise-window picker), shared by the session's cells
    [smask, stim_ok] = load_stim_mask(disk_path, size(TR{1}, 1), cfg);
    d_ = diff([0, smask(:)', 0]);
    stim_runs = [find(d_ == 1); find(d_ == -1) - 1]';      % [start end] frames, one row per stim epoch
    % recordings with no stim go in their own folder; for recordings with stim, the 'nonstim_periods'
    % view cuts the stim periods (+/- cfg.stim_margin) out of the traces
    is_nostim_rec = stim_ok && ~any(smask);
    periods_view = strcmp(plot_mode, 'nonstim_periods') && stim_ok && any(smask);
    stim_zone = movmax(double(smask(:)), 2 * cfg.stim_margin + 1) > 0;   % stim frames dilated by the margin
    out_dir = fig_root;
    if is_nostim_rec, out_dir = fullfile(fig_root, 'nonstim_recordings'); end
    out_dir = fullfile(out_dir, rec_ds(recs(idx_cells(1))), fov_folder(recs(idx_cells(1))));

    for ci = idx_cells(:)'
        r = recs(ci);
        if resume && fresh(idx_cells == ci), n_done = n_done + 1; continue; end
        if strcmp(plot_mode, 'nonstim_periods')
            % only cells that fire outside stim periods (same +/- cfg.stim_margin rule as the metrics)
            n_free = nnz(~stim_zone(r.spike_idx(r.spike_idx >= 1 & r.spike_idx <= numel(stim_zone))));
            if n_free == 0
                n_skipped_nospikes = n_skipped_nospikes + 1; continue;
            end
        end
        if ~exist(out_dir, 'dir'), mkdir(out_dir); end   % only when a figure is actually drawn
        M = cellfun(@(x) x(:, r.cell_id), TR, 'UniformOutput', false);   % 1 x nModels traces
        mrows = arrayfun(@(mi) {find(metrics.cell_hash == string(r.cell_hash) & ...
            metrics.model == all_models{mi}, 1)}, 1:numel(all_models));
        if any(cellfun(@isempty, mrows))
            warning('No metrics rows for %s; skipping its figure.', r.cell_hash); continue;
        end
        mrows = [mrows{:}];
        mm = metrics(mrows, :);
        sc = mm.spike_height(1);                          % raw spike height = 1 unit
        if ~isfinite(sc) || sc <= 0, sc = std(M{1}); end
        n = numel(M{1}); t_s = (0:n-1)' * r.dt;

        fig = figure('Color', 'w', 'Position', [50 50 1700 1000], 'Visible', 'off');
        tl = tiledlayout(3, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

        % whole trace, stacked (raw at top), median-subtracted, units of raw spike height
        nexttile([1 4]); hold on;
        Mv = M;
        if periods_view, Mv = cellfun(@(x) setnan(x, stim_zone), M, 'UniformOutput', false); end   % break lines over stim
        Z = cellfun(@(x) (x - median(x, 'omitnan')) / sc, Mv, 'UniformOutput', false);
        off = 1.15 * (prctile(Z{1}, 99.95) - prctile(Z{1}, 0.05));
        if ~isfinite(off) || off <= 0, off = 1; end
        for mi = 1:numel(all_models)
            plot(t_s, Z{mi} - (mi-1) * off, 'Color', colors(mi,:), 'LineWidth', 0.5, ...
                'DisplayName', all_models{mi});
        end
        ni = r.noise_start + [0 r.noise_len-1];
        xregion(t_s(ni(1)), t_s(min(ni(2), n)), 'FaceColor', [1 0.9 0.4], 'FaceAlpha', 0.3, ...
            'HandleVisibility', 'off');
        sp_view = r.spike_idx;
        if periods_view, sp_view = sp_view(~stim_zone(sp_view)); end
        if ~isempty(sp_view)
            plot(t_s(sp_view), Z{1}(sp_view) * 0 + prctile(Z{1}, 99.95) + 0.1*off, 'v', ...
                'Color', [0.3 0.3 0.3], 'MarkerSize', 3, 'HandleVisibility', 'off');
        end
        xlim([0 t_s(end)]); yticks([]); xlabel('Time (s)');
        ylim(ylim);                                          % freeze so the stim shading spans the panel
        if ~periods_view, draw_stim(gca, stim_runs, r.dt, 1, 'stim (blue light)'); end
        if ~periods_view && size(stim_runs, 1) <= 12                          % label onset times when there are few
            for q = 1:size(stim_runs, 1)
                text((stim_runs(q,1) - 1) * r.dt, max(ylim), sprintf(' %.2f s', (stim_runs(q,1) - 1) * r.dt), ...
                    'Color', [0 0.3 0.7], 'FontSize', 7, 'VerticalAlignment', 'top');
            end
        end
        ylabel('units of raw spike height (stacked)');
        legend('Location', 'eastoutside', 'Interpreter', 'none');
        if ~stim_ok, stim_txt = 'no stim data';
        else, stim_txt = sprintf('%d stim epochs, %.2f s total', size(stim_runs, 1), nnz(smask) * r.dt); end
        if periods_view
            title(sprintf('Whole trace, stim periods removed (+/- %d frames): %d non-stim spikes (triangles); yellow = noise window (%s)', ...
                cfg.stim_margin, numel(sp_view), stim_txt));
        else
            title(sprintf('Whole trace: %d spikes (triangles); yellow = noise window; blue = stim (%s)', ...
                r.n_spikes, stim_txt));
        end

        % per-spike preservation: Pearson r of each model's snippet vs raw, mean over models
        ok = r.spike_idx(r.spike_idx > zoom_hw & r.spike_idx < n - zoom_hw & ...
                         r.spike_idx > spike_hw & r.spike_idx < n - spike_hw);
        score = nan(size(ok));
        if ~isempty(ok)
            win = -spike_hw:spike_hw;
            Sn = cellfun(@(x) reshape(x(ok(:) + win), numel(ok), numel(win)), M, 'UniformOutput', false);
            sr = zeros(numel(ok), numel(den_models));
            zr = zscore(Sn{1}, 0, 2);
            for mi = 1:numel(den_models)
                sr(:, mi) = sum(zr .* zscore(Sn{mi+1}, 0, 2), 2) / (numel(win) - 1);
            end
            score = mean(sr, 2, 'omitnan');
        end
        % spikes with no stim frame within cfg.stim_margin (same distance the noise-window picker uses)
        cs = [0; cumsum(smask(:))];
        a_ = max(ok - cfg.stim_margin, 1); b_ = min(ok + cfg.stim_margin, numel(smask));
        nonstim = (cs(b_ + 1) - cs(a_)) == 0;
        tz = (-zoom_hw:zoom_hw) * r.dt * 1000;
        % least / most preserved spikes are dropped for now (pick_three still picks all three);
        % only the median-preserved spike is shown, over all spikes and (if the recording has stim) non-stim spikes
        has_stim = ~isempty(stim_runs);

        % row 2: median-preserved spike among ALL spikes
        if ~periods_view      % in the non-stim-periods view only spikes away from stim are shown
            pick = pick_median(score, true(size(ok)));
            nexttile; hold on;
            spike_panel(ok, score, pick, 2, 'All: median', M, sc, colors, zoom_hw, r.dt, tz, stim_runs);
        end

        % ... and among NON-STIM spikes, only when the recording contains stim periods
        if has_stim
            pick_ns = pick_median(score, nonstim);
            nexttile; hold on;
            spike_panel(ok, score, pick_ns, 2, 'Non-stim: median', M, sc, colors, zoom_hw, r.dt, tz, stim_runs);
        end

        % mean waveform, zoomed
        WF = cell2mat(cellfun(@(w) w(:)', mm.waveform, 'UniformOutput', false));   % nModels x 2L+1
        L = (size(WF, 2) - 1) / 2;
        nexttile; hold on;
        c = L + 1 + (-wf_zoom_hw:wf_zoom_hw);
        for mi = 1:numel(all_models)
            plot((-wf_zoom_hw:wf_zoom_hw) * r.dt * 1000, (WF(mi, c) - median(WF(mi, :))) / sc, ...
                'Color', colors(mi,:), 'LineWidth', 1.5);
        end
        xlabel('ms from spike'); title(sprintf('Mean waveform, zoom (n = %d)', mm.n_valid_spikes(1)), 'FontSize', 9);
        grid on; box on;

        % gain bars
        nexttile; hold on;
        gs = g(g.cell_hash == string(r.cell_hash), :);
        if ~isempty(gs)
            gs = gs(cellfun(@(m) find(strcmp(den_models, m)), cellstr(gs.model)) > 0, :);
            [~, o] = sort(cellfun(@(m) find(strcmp(den_models, m)), cellstr(gs.model)));
            gs = gs(o, :);
            % dots on a log axis (bars would anchor at an arbitrary baseline)
            B = [gs.retention, gs.noise_reduction, gs.snr_gain];
            mk = {'o', 's', 'd'}; mc = [0.25 0.6 0.35; 0.35 0.5 0.8; 0.1 0.1 0.1];
            for k = 1:3
                plot(1:height(gs), B(:, k), mk{k}, 'MarkerFaceColor', mc(k,:), 'MarkerEdgeColor', 'k', ...
                    'MarkerSize', 9, 'LineStyle', 'none');
                for q = 1:height(gs)
                    text(q + 0.08, B(q, k), sprintf('%.2f', B(q, k)), 'FontSize', 7);
                end
            end
            set(gca, 'XTick', 1:height(gs), 'XTickLabel', strrep(cellstr(gs.model), '_', '\_'), ...
                'YScale', 'log', 'TickLabelInterpreter', 'tex', 'XLim', [0.5 height(gs)+0.5]);
            yl_ = [min([B(:); 1]), max([B(:); 1])];
            ylim(yl_ .* [0.9 1.1]);
            yline(1, 'k--'); legend({'retention', 'noise red.', 'SNR gain'}, 'Location', 'best', 'FontSize', 7);
        end
        title('Gain vs raw (x)', 'FontSize', 9); grid on; box on;

        % mean waveform, full snippet
        nexttile([1 2]); hold on;
        for mi = 1:numel(all_models)
            plot((-L:L) * r.dt * 1000, (WF(mi, :) - median(WF(mi, :))) / sc, ...
                'Color', colors(mi,:), 'LineWidth', 1.2, 'DisplayName', all_models{mi});
        end
        xlabel('ms from spike'); ylabel('raw spike heights');
        title('Mean waveform, full snippet'); grid on; box on; xlim([-L L] * r.dt * 1000);

        title(tl, sprintf('%s | cell %d | FOV %d | %s', r.session_name, r.cell_id, r.FOV, r.anim_id), ...
            'Interpreter', 'none');
        exportgraphics(fig, fullfile(out_dir, sprintf('%s_cell%d.png', ...
            regexprep(r.session_name, '[^\w\-]', '_'), r.cell_id)), 'Resolution', 110);
        close(fig); n_done = n_done + 1;
    end
    fprintf('session %d/%d done (%d cell figures so far)\n', si, numel(sess_paths), n_done);
end
if n_skipped_nospikes > 0
    fprintf('Skipped %d cell(s) with no spikes outside stim periods (stim_mode = nonstim_periods).\n', n_skipped_nospikes);
end

end

%% -------- Local helpers --------
function d = dataset_subfolder(r, multi_ds)
% name of the per-dataset output subfolder ('' unless several datasets are pooled)
d = '';
if multi_ds && isfield(r, 'dataset'), d = r.dataset; end
end

function out = iff(cond, a, b)
    if cond, out = a; else, out = b; end
end

function x = setnan(x, mask)
% NaN where mask is true (breaks plotted lines)
x(mask(:)) = NaN;
end

function name = fov_folder(r)
% FOV numbers repeat across animals, so key the folder on animal + date + slice + FOV
% taken from the session path (.../<date_...>/<slice>/<FOV>/<session>).
parts = strsplit(strrep(r.session_path, '\', '/'), '/');
if numel(parts) >= 4 && startsWith(parts{end-1}, 'FOV')
    name = sprintf('%s_%s_%s_%s', r.anim_id, parts{end-3}, parts{end-2}, parts{end-1});
else
    name = sprintf('%s_FOV%d', r.anim_id, r.FOV);
end
name = regexprep(name, '[^\w\-]', '_');
end

function draw_stim(ax, runs, unit, one_based, name)
% Shade stim epochs [start end] (frames) across the axes' current y-limits.
% unit converts frames to the x axis unit; one_based=1 for absolute frame
% indices (frame 1 starts at time 0), 0 for frame offsets already relative to a spike.
if isempty(runs), return; end
yl = ylim(ax);
x0 = (runs(:,1) - one_based) * unit; x1 = runs(:,2) * unit;
X = [x0 x1 x1 x0 nan(size(x0))]'; Y = repmat([yl(1) yl(1) yl(2) yl(2) nan], size(x0, 1), 1)';
p = patch(ax, 'XData', X(:), 'YData', Y(:), 'FaceColor', [0.55 0.75 1], 'FaceAlpha', 0.35, ...
    'EdgeColor', [0.2 0.4 0.9], 'LineWidth', 0.75, 'DisplayName', name);   % outline keeps ~50 ms epochs visible
if isempty(name), p.HandleVisibility = 'off'; end
uistack(p, 'bottom');
end

function pick = pick_median(score, allowed)
% [NaN idx NaN]: index (into the spike list) of the median-preserved spike among `allowed`
% (same layout as pick_three so spike_panel(..., k = 2) works)
pick = nan(1, 3);
cand = find(allowed(:) & ~isnan(score(:)));
if isempty(cand), return; end
[~, o] = sort(score(cand));
pick(2) = cand(o(ceil(numel(o)/2)));
end

function pick = pick_three(score, allowed)
% indices (into the spike list) of the least / median / most preserved spike among `allowed`
pick = nan(1, 3);
cand = find(allowed(:) & ~isnan(score(:)));
if numel(cand) < 3, return; end
[~, o] = sort(score(cand));
pick = cand(o([1, ceil(numel(o)/2), numel(o)]))';
end

function spike_panel(ok, score, pick, k, label, M, sc, colors, zoom_hw, dt, tz, stim_runs)
% zoom on one spike, all models overlaid, in units of raw spike height
if isnan(pick(k))
    title([label ' (no spikes)'], 'FontSize', 9);
    xlabel('ms from spike'); grid on; box on; return;
end
i0 = ok(pick(k));
for mi = 1:numel(M)
    seg = M{mi}(i0 + (-zoom_hw:zoom_hw));
    plot(tz, (seg - median(seg)) / sc, 'Color', colors(mi,:), 'LineWidth', 1.2);
end
yl_ = ylim; ylim(yl_);
zr_ = i0 + [-zoom_hw zoom_hw];
hit = stim_runs(:,2) >= zr_(1) & stim_runs(:,1) <= zr_(2);
if any(hit)
    sr_ = min(max(stim_runs(hit, :), zr_(1)), zr_(2)) - i0;   % clip epochs to the window
    draw_stim(gca, sr_, dt * 1000, 0, '');                    % x in ms from spike
end
title(sprintf('%s spike (frame %d, r = %.2f)%s', label, i0, score(pick(k)), ...
    repmat(' [in stim]', 1, any(hit))), 'FontSize', 9);
xlabel('ms from spike'); grid on; box on; xlim(tz([1 end]));
if k == 1, ylabel('raw spike heights'); end
end
