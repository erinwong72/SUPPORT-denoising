function support_model_comparison(config)
% support_model_comparison.m
% Usage: support_model_comparison()  or  support_model_comparison('my_config')  - config = name of a
% config file in configs/analysis (see load_analysis_config.m).
% Compare several SUPPORT models on the same recordings. Runs headless.
%
% Noise windows are chosen ONCE per cell by auto_noise_window (spike- and
% stim-free, typical noise level), stored in noise_regions.mat, and reused for
% every model. Review/override them with review_noise_windows.m (interactive);
% rows computed with a window that was later changed are recomputed here.
%
% Outputs (Erin/support_data/model_comparison/):
%   noise_regions.mat  table `noise`: cell_hash, session_path, cell_id, start,
%                      status (auto/confirmed/manual/needs_manual), flag,
%                      n_valid, noise_std
%   recs.mat           struct array, one element per cell, model-independent:
%                      session info, spike times, noise window, firing rate
%   metrics.mat        long table, one row per cell x model ('raw' is a model):
%                      psnr_db, psnr_db_alt (cfg.alt_noise_lens), psnr_db_bc (== psnr_db),
%                      snr_paper_db (disabled, always NaN - see compute_trace_metrics.m).
%                      All PSNR quantities (waveform, spike_height, noise_std)
%                      are cut from the trace as given (no detrending).
%                      spike_height, noise_std, waveform, waveform_r_vs_raw,
%                      sta (spike-triggered average), sta_r_vs_raw, noise_start
%
% The headless pipeline reuses the raw spike times for every model, so firing
% rate is identical across models by construction and lives in recs.
% Trace-derived metrics (PSNR, waveform, STA) differ per model.
arguments
    config = []   % name of a config in configs/analysis (required if there are several) or a cfg struct
end
close all;

%% Config
[root_path, code_path] = setup_analysis_paths();
cfg = load_analysis_config(config);
rerun = false;            % true: recompute every row

opts = struct('snippet_len', cfg.snippet_len, 'noise_len', cfg.noise_len, ...
    'baseline_win', cfg.baseline_win, 'alt_noise_lens', cfg.alt_noise_lens);

save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
recs_file    = fullfile(save_dir, 'recs.mat');
metrics_file = fullfile(save_dir, 'metrics.mat');

%% Cell list and noise windows (automatic, once per cell: see select_noise_windows.m)
sessions = load_session_list(root_path, code_path, cfg.sessions_file, cfg.sel_sessions, cfg.invert_sel_sessions, cfg.dataset_list);
noise = select_noise_windows([], cfg);
if cfg.exclude_no_signal
    fprintf('Excluding %d cells flagged no_signal.\n', sum(noise.no_signal));
    noise = noise(~noise.no_signal, :);   % excluded cells drop out of recs and metrics below
end
if cfg.exclude_artifacts
    % huge template-mask artifact in a trace (see flag_trace_artifacts.m):
    %   raw -> drop the cell from recs and metrics; a model -> drop only that cell x model
    %   row (listed in rerun_template_mask.mat/.csv so the template mask can be re-applied)
    art = flag_trace_artifacts(sessions, cfg, save_dir);
    bad_raw = art.cell_hash(art.is_artifact & art.model == "raw");
    if cfg.exclude_cell_if_any_artifact
        % stricter: an artifact in ANY model's trace drops the whole cell (all models + raw),
        % so every model is compared on the same cells
        bad_raw = unique(art.cell_hash(art.is_artifact));
    end
    fprintf('Excluding %d cells with a trace artifact (%s).\n', numel(bad_raw), ...
        iff(cfg.exclude_cell_if_any_artifact, 'any model or raw', 'raw only; model artifacts drop just that model'));
    noise = noise(~ismember(string(noise.cell_hash), bad_raw), :);
    bad_rows = art.cell_hash(art.is_artifact & art.model ~= "raw") + "|" + art.model(art.is_artifact & art.model ~= "raw");
end

%% Stim handling (cfg.stim_mode): which cells / which spikes the metrics use
%   'all'               every cell, every spike (default)
%   'nonstim_sessions'  only cells in recordings with NO stim at all (stim data found, none above threshold)
%   'nonstim_periods'   every cell, but spike height / STA only from spikes with no stim frame within
%                       cfg.stim_margin (the noise window is already stim-free)
%   'auto'              'nonstim_sessions' if any no-stim recording exists, else 'nonstim_periods'
stim_mode = cfg.stim_mode;
assert(ismember(stim_mode, {'all', 'nonstim_sessions', 'nonstim_periods', 'auto'}), ...
    'cfg.stim_mode must be all, nonstim_sessions, nonstim_periods or auto (got "%s")', stim_mode);
if ismember(stim_mode, {'nonstim_sessions', 'auto'})
    stim_cls = classify_sessions_by_stim(cfg);
    [tf, loc] = ismember(string({sessions.session_path}), stim_cls.session_path);
    s_nostim = false(1, numel(sessions));
    s_nostim(tf) = stim_cls.had_stim_data(loc(tf)) & ~stim_cls.has_stim(loc(tf));
    nostim_hash = string({sessions(s_nostim).cell_hash});
    if strcmp(stim_mode, 'auto')
        if any(s_nostim), stim_mode = 'nonstim_sessions'; else, stim_mode = 'nonstim_periods'; end
        fprintf('stim_mode auto -> %s (%d cells in no-stim recordings)\n', stim_mode, numel(nostim_hash));
    end
end
if strcmp(stim_mode, 'nonstim_sessions')
    assert(~isempty(nostim_hash), 'stim_mode nonstim_sessions: no recordings without stim found.');
    fprintf('Keeping %d cells in recordings with no stim.\n', nnz(ismember(string(noise.cell_hash), nostim_hash)));
    noise = noise(ismember(string(noise.cell_hash), nostim_hash), :);
end
use_periods = strcmp(stim_mode, 'nonstim_periods');
all_models = [{'raw'}, cfg.models];

%% recs: model-independent info per cell
if isfile(recs_file) && ~rerun
    recs = load(recs_file).recs;
    if ~isempty(recs) && ~isfield(recs, 'dataset'), [recs.dataset] = deal(''); end   % saved before datasets were tracked
    s_hash_ = string({sessions.cell_hash}); s_ds_ = string({sessions.dataset});
    for k_ = 1:numel(recs)                                                          % follow the current sessions list
        j_ = find(s_hash_ == string(recs(k_).cell_hash), 1);
        if ~isempty(j_), recs(k_).dataset = char(s_ds_(j_)); end
    end
else
    recs = struct([]);
end
have_rec = strings(0,1);
if ~isempty(recs), have_rec = string({recs.cell_hash}); end

for k = 1:numel(sessions)
    s = sessions(k);
    key = string(s.cell_hash);
    ni = find(noise.cell_hash == key, 1);
    if any(have_rec == key) || isempty(ni) || isnan(noise.start(ni)), continue; end
    try
        [sp, ~, dt] = load_spikes(s.session_path, 'raw', cfg.use_template, s.cell_id);
        n_frames = size(load_model_trace(s.session_path, 'raw', cfg.use_template, s.cell_id), 1);
    catch err
        warning('Skipping rec %s: %s', key, err.message);
        continue;
    end
    r = struct('cell_hash', char(key), 'session_path', s.session_path, ...
        'session_name', s.session_name, 'anim_id', s.anim_id, ...
        'FOV', s.FOV, 'cell_id', s.cell_id, 'dt', dt, 'n_frames', n_frames, ...
        'spike_idx', sp, 'noise_start', noise.start(ni), ...
        'noise_len', min(opts.noise_len, noise.valid_len(ni)), 'noise_valid_len', noise.valid_len(ni));
    r.n_spikes = numel(sp);
    r.dataset = char(string(s.dataset));
    r.firing_rate_hz = r.n_spikes / (n_frames * dt);
    if isempty(recs), recs = r; else, recs(end+1) = r; end %#ok<SAGROW>
end
% follow any window changes made in review_noise_windows.m
keep = true(size(recs));
for k = 1:numel(recs)
    ni = find(noise.cell_hash == string(recs(k).cell_hash), 1);
    if isempty(ni) || isnan(noise.start(ni)), keep(k) = false; continue; end
    recs(k).noise_start = noise.start(ni);
    recs(k).noise_len = min(opts.noise_len, noise.valid_len(ni));   % shorter for cells rescued at < noise_len
    recs(k).noise_valid_len = noise.valid_len(ni);
end
recs = recs(keep);
save(recs_file, 'recs', '-v7.3');

%% metrics: one row per cell x model
if isfile(metrics_file) && ~rerun
    metrics = load(metrics_file).metrics;
else
    metrics = table();
end
if ~isempty(metrics)
    % rows computed under a different spike selection (all spikes vs non-stim only) are not comparable
    ud = metrics.Properties.UserData;
    was_periods = isstruct(ud) && isfield(ud, 'stim_mode') && strcmp(ud.stim_mode, 'nonstim_periods');
    if was_periods ~= use_periods
        fprintf('stim_mode changed: recomputing all metrics.\n');
        metrics = table();
    end
end
if ~isempty(metrics)
    % drop rows computed with a window that has since changed
    cur = nan(height(metrics), 1);
    for i = 1:height(metrics)
        ri = find(strcmp({recs.cell_hash}, metrics.cell_hash(i)), 1);
        if ~isempty(ri), cur(i) = recs(ri).noise_start; end
    end
    stale = ~(metrics.noise_start == cur);
    if any(stale)
        fprintf('Recomputing %d rows whose noise window changed or cell was dropped.\n', sum(stale));
        metrics = metrics(~stale, :);
    end
end
if cfg.exclude_artifacts && ~isempty(metrics)
    metrics = metrics(~ismember(metrics.cell_hash + "|" + metrics.model, bad_rows), :);
end
have = strings(0,1);
if ~isempty(metrics), have = metrics.cell_hash + "|" + metrics.model; end

% single-pixel SNR columns (cfg.pixel_snr); NaN when off or not yet computed (n_roi_pixels is the "done" flag).
% Plain names: footprint of the row's own model; *_rawfp: the raw movie's footprint for every model.
pixel_vars = {'pixel_snr_db', 'pixel_snr_db_median', 'n_roi_pixels', 'n_pixel_nonpositive', ...
    'pixel_snr_rawfp_db', 'pixel_snr_rawfp_db_median', 'n_roi_pixels_rawfp', 'n_pixel_nonpositive_rawfp'};

rows = {};
for k = 1:numel(recs)
    r = recs(k);
    sdisk = to_local_path(r.session_path, root_path);   % recs may hold another machine's path; r.session_path is left as stored
    [spike_used, keep_sp] = select_spikes(r, sdisk, use_periods, cfg);
    for mi = 1:numel(all_models)
        model = all_models{mi};
        if any(have == string(r.cell_hash) + "|" + model), continue; end
        if cfg.exclude_artifacts && any(bad_rows == string(r.cell_hash) + "|" + model), continue; end
        try
            tr = load_model_trace(sdisk, model, cfg.use_template, r.cell_id);
        catch err
            warning('Missing %s / %s: %s', r.cell_hash, model, err.message);
            continue;
        end
        opts_c = opts; opts_c.noise_len = r.noise_len; opts_c.valid_len = r.noise_valid_len;
        m = compute_trace_metrics(tr, spike_used, r.noise_start, opts_c);
        try
            [sp_m, sw_m] = load_spikes(sdisk, model, cfg.use_template, r.cell_id);
            assert(numel(sp_m) == numel(r.spike_idx), 'spike count differs from raw');
            sta = compute_sta(tr, spike_used, sw_m(keep_sp), cfg.sta_half_win);
        catch err
            warning('STA failed for %s / %s: %s', r.cell_hash, model, err.message);
            sta = nan(1, 2*cfg.sta_half_win + 1);
        end
        rows{end+1} = table(string(r.cell_hash), string(r.session_path), ...
            string(r.session_name), r.cell_id, string(model), r.noise_start, m.psnr_db, m.psnr_db_bc, ...
            m.snr_paper_db, m.spike_height, m.noise_std, m.n_valid_spikes, ...
            m.psnr_alt, {m.waveform}, NaN, {sta}, NaN, nan(1, numel(pixel_vars)), 'VariableNames', {'cell_hash', 'session_path', ...
            'session_name', 'cell_id', 'model', 'noise_start', 'psnr_db', 'psnr_db_bc', 'snr_paper_db', ...
            'spike_height', 'noise_std', 'n_valid_spikes', 'psnr_db_alt', 'waveform', ...
            'waveform_r_vs_raw', 'sta', 'sta_r_vs_raw', 'pixel_values'}); %#ok<AGROW>
        rows{end} = splitvars(rows{end}, 'pixel_values', 'NewVariableNames', pixel_vars);   % filled by add_pixel_metrics
    end
end
if ~isempty(metrics)
    % columns that new rows don't carry: `trained` is re-added below; the pixel columns are
    % missing from a metrics.mat saved before they existed
    if ismember('trained', metrics.Properties.VariableNames), metrics = removevars(metrics, 'trained'); end
    if ismember('dataset', metrics.Properties.VariableNames), metrics = removevars(metrics, 'dataset'); end   % re-added below
    for v = pixel_vars
        if ~ismember(v{1}, metrics.Properties.VariableNames), metrics.(v{1}) = nan(height(metrics), 1); end
    end
end
if ~isempty(rows)
    metrics = [metrics; vertcat(rows{:})];
end
if cfg.pixel_snr
    metrics = add_pixel_metrics(metrics, recs, cfg, root_path);
end

% waveform / STA correlation vs the raw one of the same cell (Pearson; scale
% and offset invariant, so no mat2gray needed)
for i = 1:height(metrics)
    j = find(metrics.cell_hash == metrics.cell_hash(i) & metrics.model == "raw", 1);
    if isempty(j), continue; end
    metrics.waveform_r_vs_raw(i) = safe_corr(metrics.waveform{i}, metrics.waveform{j});
    metrics.sta_r_vs_raw(i)      = safe_corr(metrics.sta{i}, metrics.sta{j});
end
[tf_, loc_] = ismember(metrics.cell_hash, string({recs.cell_hash}));     % which dataset each cell came from
ds_all_ = string({recs.dataset})';
metrics.dataset = repmat("", height(metrics), 1); metrics.dataset(tf_) = ds_all_(loc_(tf_));
metrics.trained = flag_trained_cells(metrics, cfg, root_path);   % cell was in that model's training windows (cfg.training_windows)
metrics.Properties.UserData.alt_noise_lens = opts.alt_noise_lens;  % columns of psnr_db_alt
metrics.Properties.UserData.stim_mode = stim_mode;                 % spike selection the rows were computed with
save(metrics_file, 'metrics', '-v7.3');

%% Quick summary
summary_vars = {'psnr_db', 'psnr_db_bc', 'waveform_r_vs_raw', 'sta_r_vs_raw'};  % snr_paper_db disabled
if cfg.pixel_snr, summary_vars = [summary_vars, {'pixel_snr_db', 'pixel_snr_rawfp_db'}]; end
disp(groupsummary(metrics, 'model', 'median', summary_vars));

% sensitivity of median PSNR to the noise-window length (same start frame)
fprintf('Median PSNR (dB): %d-frame window, and alt %s:\n', opts.noise_len, mat2str(opts.alt_noise_lens));
for mi = 1:numel(all_models)
    sel = metrics.model == all_models{mi};
    fprintf('  %-24s %.2f   alt: %s\n', all_models{mi}, median(metrics.psnr_db(sel), 'omitnan'), ...
        mat2str(median(metrics.psnr_db_alt(sel,:), 1, 'omitnan'), 3));
end

% same numbers + medians of the per-cell change vs raw -> model_summary.csv / .mat
raw_m = metrics(metrics.model == "raw", :);
nm = numel(all_models);
n_cells = zeros(nm, 1); [med_psnr, med_dpsnr, med_ret, med_nred, med_gain, med_wf_r, med_sta_r] = deal(nan(nm, 1));
alt_med = nan(nm, numel(opts.alt_noise_lens));
for mi = 1:nm
    t = metrics(metrics.model == all_models{mi}, :);
    [tf, loc] = ismember(t.cell_hash, raw_m.cell_hash);
    t = t(tf, :); r = raw_m(loc(tf), :);
    n_cells(mi)   = height(t);
    med_psnr(mi)  = median(t.psnr_db, 'omitnan');
    med_dpsnr(mi) = median(t.psnr_db - r.psnr_db, 'omitnan');
    med_ret(mi)   = median(t.spike_height ./ r.spike_height, 'omitnan');
    med_nred(mi)  = median(r.noise_std ./ t.noise_std, 'omitnan');
    med_gain(mi)  = median((t.spike_height ./ r.spike_height) .* (r.noise_std ./ t.noise_std), 'omitnan');
    med_wf_r(mi)  = median(t.waveform_r_vs_raw, 'omitnan');
    med_sta_r(mi) = median(t.sta_r_vs_raw, 'omitnan');
    alt_med(mi,:) = median(t.psnr_db_alt, 1, 'omitnan');
end
model_summary = table(string(all_models(:)), n_cells, med_psnr, med_dpsnr, med_ret, med_nred, med_gain, med_wf_r, med_sta_r, ...
    'VariableNames', {'model','n_cells','median_psnr_db','median_delta_psnr_db','median_retention','median_noise_reduction', ...
    'median_snr_gain','median_waveform_r_vs_raw','median_sta_r_vs_raw'});
for k = 1:numel(opts.alt_noise_lens)
    model_summary.(sprintf('median_psnr_db_win%d', opts.alt_noise_lens(k))) = alt_med(:, k);
end
if cfg.pixel_snr
    % single-pixel SNR (footprint pixels only): median over cells of the per-cell mean over pixels,
    % and of its change vs raw; own-model footprint and raw footprint
    for pv = {'pixel_snr_db', 'pixel_snr_rawfp_db'}
        [med_pix, med_dpix] = deal(nan(nm, 1));
        for mi = 1:nm
            t = metrics(metrics.model == all_models{mi}, :);
            [tf, loc] = ismember(t.cell_hash, raw_m.cell_hash);
            t = t(tf, :); r = raw_m(loc(tf), :);
            med_pix(mi)  = median(t.(pv{1}), 'omitnan');
            med_dpix(mi) = median(t.(pv{1}) - r.(pv{1}), 'omitnan');
        end
        model_summary.(['median_' pv{1}]) = med_pix;
        model_summary.(['median_delta_' pv{1}]) = med_dpix;
    end
end
model_summary.Properties.UserData.stim_mode = stim_mode;
model_summary.Properties.UserData.noise_len = opts.noise_len;
save(fullfile(save_dir, 'model_summary.mat'), 'model_summary');
writetable(model_summary, fullfile(save_dir, 'model_summary.csv'));
fprintf('Saved %s\n', fullfile(save_dir, 'model_summary.csv'));
ds_names = unique(metrics.dataset, 'stable'); ds_names = ds_names(ds_names ~= "");
multi_ds = numel(ds_names) > 1;
if multi_ds
    % the same core summary per dataset x model (raw is a model) -> model_summary_by_dataset.csv
    by_ds = table();
    for di = 1:numel(ds_names)
        t_ = core_summary(metrics(metrics.dataset == ds_names(di), :), all_models, opts.alt_noise_lens);
        by_ds = [by_ds; addvars(t_, repmat(ds_names(di), height(t_), 1), 'Before', 1, 'NewVariableNames', 'dataset')]; %#ok<AGROW>
    end
    writetable(by_ds, fullfile(save_dir, 'model_summary_by_dataset.csv'));
    disp(by_ds(:, {'dataset','model','n_cells','median_psnr_db','median_delta_psnr_db','median_snr_gain'}));
    fprintf('Saved %s\n', fullfile(save_dir, 'model_summary_by_dataset.csv'));
end

% per cell x model change vs raw (denoised models only), with seen / unseen = was the cell in that
% model's training windows (cfg.training_windows via flag_trained_cells; all false if not set)
den_names = string(all_models(2:end));
cmp = table();
for mi = 1:numel(den_names)
    t = metrics(metrics.model == den_names(mi), :);
    [tf, loc] = ismember(t.cell_hash, raw_m.cell_hash);
    t = t(tf, :); r = raw_m(loc(tf), :);
    cmp = [cmp; table(t.cell_hash, t.dataset, repmat(den_names(mi), height(t), 1), t.trained, r.psnr_db, t.psnr_db, ...
        t.spike_height ./ r.spike_height, r.noise_std ./ t.noise_std, ...
        'VariableNames', {'cell_hash','dataset','model','trained','psnr_raw','psnr_model','retention','noise_reduction'})]; %#ok<AGROW>
end
cmp.dpsnr = cmp.psnr_model - cmp.psnr_raw;
cmp.snr_gain = cmp.retention .* cmp.noise_reduction;

has_training = any(cmp.trained);
if has_training
    % trained-on vs held-out medians per model (and per dataset when several) -> trained_vs_heldout.csv
    split_rows = {};
    ds_groups = "all"; if multi_ds, ds_groups = [ds_groups; ds_names]; end
    for gi_ = 1:numel(ds_groups)
        cmp_g = cmp; if ds_groups(gi_) ~= "all", cmp_g = cmp(cmp.dataset == ds_groups(gi_), :); end
        for mi = 1:numel(den_names)
            for tr_ = [false true]
                t = cmp_g(cmp_g.model == den_names(mi) & cmp_g.trained == tr_, :);
                split_rows{end+1} = table(ds_groups(gi_), den_names(mi), iff(tr_, "trained_on", "held_out"), height(t), ...
                    median(t.psnr_raw, 'omitnan'), median(t.psnr_model, 'omitnan'), median(t.dpsnr, 'omitnan'), ...
                    median(t.retention(t.retention > 0), 'omitnan'), median(t.noise_reduction, 'omitnan'), median(t.snr_gain(t.retention > 0), 'omitnan'), ...
                    'VariableNames', {'dataset','model','split','n_cells','median_psnr_raw','median_psnr_db','median_delta_psnr_db', ...
                    'median_retention','median_noise_reduction','median_snr_gain'}); %#ok<AGROW>
            end
        end
    end
    split_tbl = vertcat(split_rows{:});
    split_tbl.Properties.UserData.stim_mode = stim_mode;
    disp(split_tbl);
    writetable(split_tbl, fullfile(save_dir, 'trained_vs_heldout.csv'));
    fprintf('Saved %s\n', fullfile(save_dir, 'trained_vs_heldout.csv'));
end

% denoised vs raw PSNR, one point per cell; with several datasets one row of panels per dataset
fig_rows = iff(multi_ds, numel(ds_names), 1);
fig_cols = iff(has_training, numel(den_names), 1);
fig_ps = figure('Color', 'w', 'Position', [100 100 max(1100, 330 * fig_cols + 80) 450 * fig_rows + 50], 'Visible', 'off');
tl_ps = tiledlayout(fig_rows, fig_cols, 'TileSpacing', 'compact');
seen_col = [0.85 0.33 0.10]; unseen_col = [0.00 0.45 0.74];
for ri = 1:fig_rows
    cmp_r = cmp; ds_lbl = '';
    if multi_ds, cmp_r = cmp(cmp.dataset == ds_names(ri), :); ds_lbl = [char(ds_names(ri)) ': ']; end
    if has_training
        % one panel per model, colored by seen (in that model's training windows) vs unseen
        for mi = 1:numel(den_names)
            nexttile; hold on;
            t = cmp_r(cmp_r.model == den_names(mi), :);
            scatter(t.psnr_raw(~t.trained), t.psnr_model(~t.trained), 25, unseen_col, 'filled', 'MarkerFaceAlpha', 0.6, ...
                'DisplayName', sprintf('heldout (n=%d)', nnz(~t.trained)));
            scatter(t.psnr_raw(t.trained), t.psnr_model(t.trained), 25, seen_col, 'filled', 'MarkerFaceAlpha', 0.6, ...
                'DisplayName', sprintf('trained (n=%d)', nnz(t.trained)));
            lims = [min([xlim ylim]), max([xlim ylim])];
            plot(lims, lims, 'k--', 'HandleVisibility', 'off');
            xlim(lims); ylim(lims); axis square; grid on; box on;
            xlabel('PSNR (dB), raw'); title([ds_lbl strrep(char(den_names(mi)), '_', '\_')], 'FontSize', 9);
            if mi == 1, ylabel('PSNR (dB), denoised'); end
            legend('Location', 'northwest', 'FontSize', 8);
        end
    else
        nexttile; hold on;
        for mi = 1:numel(den_names)
            t = cmp_r(cmp_r.model == den_names(mi), :);
            c_ = model_color_table(numel(all_models)); c_ = c_(mi + 1, :);
            scatter(t.psnr_raw, t.psnr_model, 25, c_, 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', char(den_names(mi)));
        end
        lims = [min([xlim ylim]), max([xlim ylim])];
        plot(lims, lims, 'k--', 'HandleVisibility', 'off');
        xlim(lims); ylim(lims); title(strtrim(ds_lbl(1:max(end-2, 0))), 'FontSize', 9);
        xlabel('PSNR (dB), raw'); ylabel('PSNR (dB), denoised');
        axis square; grid on;
        legend('Location', 'best', 'Interpreter', 'none');
    end
end
if has_training, title(tl_ps, 'Denoised vs raw PSNR: trained vs heldout recordings'); end
exportgraphics(fig_ps, fullfile(save_dir, 'psnr_snr_by_model.png'), 'Resolution', 150);

% single-pixel SNR (footprint pixels), denoised vs raw, one point per cell; left: each model's own
% footprint, right: the raw footprint for every model (same pixels in all models)
if cfg.pixel_snr
    fig_px = figure('Color', 'w', 'Position', [100 100 1100 500], 'Visible', 'off');
    pixel_panels = {'pixel_snr_db', 'own-model footprint'; 'pixel_snr_rawfp_db', 'raw footprint'};
    for pp = 1:size(pixel_panels, 1)
        subplot(1, size(pixel_panels, 1), pp); hold on;
        pv = pixel_panels{pp, 1};
        for mi = 1:numel(den_names)
            t = metrics(metrics.model == den_names(mi), :);
            [tf, loc] = ismember(t.cell_hash, raw_m.cell_hash);
            c_ = model_color_table(numel(all_models)); c_ = c_(mi + 1, :);
            scatter(raw_m.(pv)(loc(tf)), t.(pv)(tf), 25, c_, 'filled', 'MarkerFaceAlpha', 0.6, ...
                'DisplayName', char(den_names(mi)));
        end
        lims = [min([xlim ylim]), max([xlim ylim])];
        plot(lims, lims, 'k--', 'HandleVisibility', 'off');
        xlim(lims); ylim(lims); axis square; grid on;
        xlabel('Single-pixel SNR (dB), raw'); ylabel('Single-pixel SNR (dB), denoised');
        title(pixel_panels{pp, 2});
        if pp == 1, legend('Location', 'best', 'Interpreter', 'none'); end
    end
    exportgraphics(fig_px, fullfile(save_dir, 'pixel_snr_by_model.png'), 'Resolution', 150);
end

end

%% -------- Local helpers --------
function t_out = core_summary(m, all_models, alt_lens)
% per-model medians for one set of cells (same numbers as model_summary, without the pixel columns)
raw_m = m(m.model == "raw", :);
nm = numel(all_models);
n_cells = zeros(nm, 1); [med_psnr, med_dpsnr, med_ret, med_nred, med_gain, med_wf_r, med_sta_r] = deal(nan(nm, 1));
alt_med = nan(nm, numel(alt_lens));
for mi = 1:nm
    t = m(m.model == all_models{mi}, :);
    [tf, loc] = ismember(t.cell_hash, raw_m.cell_hash);
    t = t(tf, :); r = raw_m(loc(tf), :);
    n_cells(mi)   = height(t);
    med_psnr(mi)  = median(t.psnr_db, 'omitnan');
    med_dpsnr(mi) = median(t.psnr_db - r.psnr_db, 'omitnan');
    med_ret(mi)   = median(t.spike_height ./ r.spike_height, 'omitnan');
    med_nred(mi)  = median(r.noise_std ./ t.noise_std, 'omitnan');
    med_gain(mi)  = median((t.spike_height ./ r.spike_height) .* (r.noise_std ./ t.noise_std), 'omitnan');
    med_wf_r(mi)  = median(t.waveform_r_vs_raw, 'omitnan');
    med_sta_r(mi) = median(t.sta_r_vs_raw, 'omitnan');
    if ~isempty(alt_lens), alt_med(mi,:) = median(t.psnr_db_alt, 1, 'omitnan'); end
end
t_out = table(string(all_models(:)), n_cells, med_psnr, med_dpsnr, med_ret, med_nred, med_gain, med_wf_r, med_sta_r, ...
    'VariableNames', {'model','n_cells','median_psnr_db','median_delta_psnr_db','median_retention','median_noise_reduction', ...
    'median_snr_gain','median_waveform_r_vs_raw','median_sta_r_vs_raw'});
for k = 1:numel(alt_lens)
    t_out.(sprintf('median_psnr_db_win%d', alt_lens(k))) = alt_med(:, k);
end
end

function out = iff(cond, a, b)
    if cond, out = a; else, out = b; end
end

function [spike_used, keep_sp] = select_spikes(r, sdisk, use_periods, cfg)
    % spikes the metrics use for one cell; with use_periods, only those with no stim frame within
    % cfg.stim_margin (recordings without stim data keep all)
    spike_used = r.spike_idx; keep_sp = true(size(r.spike_idx));
    if ~use_periods, return; end
    [smask, had_stim_data] = load_stim_mask(sdisk, r.n_frames, cfg);
    if had_stim_data && any(smask)
        cs = [0; cumsum(smask(:))];
        a_ = max(r.spike_idx - cfg.stim_margin, 1); b_ = min(r.spike_idx + cfg.stim_margin, numel(smask));
        keep_sp = (cs(b_ + 1) - cs(a_)) == 0;
        spike_used = r.spike_idx(keep_sp);
    end
end

function metrics = add_pixel_metrics(metrics, recs, cfg, root_path)
    % Fill the single-pixel SNR columns for rows not done yet (either n_roi_pixels NaN). One call per
    % recording: each model's movie is preprocessed once as in ICA_Pre and shared by the cells; the raw
    % movie is always processed too, since the raw footprint is rebuilt from it. See
    % compute_recording_pixel_snr.m.
    assert(cfg.use_template, 'cfg.pixel_snr uses the template footprint: set cfg.use_template = true');
    todo = find(isnan(metrics.n_roi_pixels) | isnan(metrics.n_roi_pixels_rawfp));
    if isempty(todo), return; end
    sdisk = strings(height(metrics), 1);
    for i = todo'
        sdisk(i) = to_local_path(char(metrics.session_path(i)), root_path);
    end
    recordings = unique(sdisk(todo));
    fprintf('Single-pixel SNR: %d rows in %d recordings.\n', numel(todo), numel(recordings));
    for g = 1:numel(recordings)
        rows_g = todo(sdisk(todo) == recordings(g));
        models_g = cellstr(unique(metrics.model(rows_g), 'stable'))';
        cells_g = unique(metrics.cell_id(rows_g))';
        wanted = false(numel(models_g), numel(cells_g));
        expected_frames = zeros(1, numel(cells_g));
        for i = rows_g'
            mi = find(strcmp(models_g, metrics.model(i)), 1);
            ci = find(cells_g == metrics.cell_id(i), 1);
            wanted(mi, ci) = true;
            ri = find(strcmp({recs.cell_hash}, metrics.cell_hash(i)), 1);
            if ~isempty(ri), expected_frames(ci) = recs(ri).n_frames; end
        end
        [own, rawfp] = compute_recording_pixel_snr(char(recordings(g)), models_g, cells_g, wanted, expected_frames, cfg);
        for i = rows_g'
            mi = find(strcmp(models_g, metrics.model(i)), 1);
            ci = find(cells_g == metrics.cell_id(i), 1);
            if ~isempty(own{mi, ci})
                metrics.pixel_snr_db(i) = own{mi, ci}.snr_db;
                metrics.pixel_snr_db_median(i) = own{mi, ci}.snr_db_median;
                metrics.n_roi_pixels(i) = own{mi, ci}.n_roi_pixels;
                metrics.n_pixel_nonpositive(i) = own{mi, ci}.n_nonpositive;
            end
            if ~isempty(rawfp{mi, ci})
                metrics.pixel_snr_rawfp_db(i) = rawfp{mi, ci}.snr_db;
                metrics.pixel_snr_rawfp_db_median(i) = rawfp{mi, ci}.snr_db_median;
                metrics.n_roi_pixels_rawfp(i) = rawfp{mi, ci}.n_roi_pixels;
                metrics.n_pixel_nonpositive_rawfp(i) = rawfp{mi, ci}.n_nonpositive;
            end
        end
    end
end

function r = safe_corr(a, b)
    a = a(:); b = b(:);
    ok = ~isnan(a) & ~isnan(b);
    if nnz(ok) < 3, r = NaN; else, r = corr(a(ok), b(ok)); end
end
