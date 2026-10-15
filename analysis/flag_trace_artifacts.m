function art = flag_trace_artifacts(sessions, cfg, save_dir)
%FLAG_TRACE_ARTIFACTS  Flag cell x model traces with a huge artifact, e.g. a
% single-frame transient ~100x the noise. It appears when the template mask
% misplaces on the raw movie, or when it is applied to a denoised movie
% (sometimes only one of several models) even though raw extracted fine.
%
%   art = flag_trace_artifacts(sessions, cfg, save_dir)
%
% Every trace in [{'raw'}, cfg.models] is checked, on the trace as given (no detrending):
%   artifact_ratio = max(|x - median(x)|) / (1.4826 * MAD(x)).
% (the median only centres the deviation for this ratio; nothing is subtracted anywhere else)
% Real spikes are a handful of sigma; the artifact is >> cfg.artifact_max_sigma.
%
% Consequences (applied by support_model_comparison.m):
%   raw flagged    -> the whole cell is excluded (nothing to compare against)
%   model flagged  -> only that cell x model row is excluded
%                     and it is listed in the rerun list (redo ICA Pre / Choose / spikes)
%
% Ratios are cached per cell x model in <save_dir>/artifact_flags.mat, so
% changing cfg.artifact_max_sigma only re-thresholds. Delete the file to
% recompute. Outputs in save_dir:
%   excluded_artifact_cells.csv   flagged raw traces (cell excluded)
%   rerun_template_mask.mat/.csv  struct array / table `rerun` of flagged model traces
%                                 (read by preprocessing_headless
%                                 rerun_flagged): session_path, model, cell_id, cell_hash,
%                                 artifact_ratio, peak_frame
%
% art: table (cell_hash, session_path, session_name, cell_id, model,
% artifact_ratio, peak_frame, is_artifact).
cache_file = fullfile(save_dir, 'artifact_flags.mat');
if isfile(cache_file), art = load(cache_file, 'art').art; else, art = table(); end
% a cached row is stale once its trace file was rewritten (e.g. after a rerun of ICA Choose)
if ~isempty(art)
    fresh = false(height(art), 1);
    for i = 1:height(art)
        d = dir(trace_file(art.session_path(i), art.model(i), cfg.use_template));
        fresh(i) = ~isempty(d) && d(1).datenum <= art.trace_datenum(i);
    end
    if any(~fresh), fprintf('flag_trace_artifacts: recomputing %d rows whose trace file changed\n', sum(~fresh)); end
    art = art(fresh, :);
end
have = strings(0, 1);
if ~isempty(art), have = art.cell_hash + "|" + art.model; end
models = [{'raw'}, cfg.models];

rows = {};
for k = 1:numel(sessions)
    s = sessions(k);
    for mi = 1:numel(models)
        key = string(s.cell_hash) + "|" + models{mi};
        if any(have == key), continue; end
        try
            tr = load_model_trace(s.session_path, models{mi}, cfg.use_template, s.cell_id);
        catch err
            warning('flag_trace_artifacts: skipping %s: %s', key, err.message);
            continue;
        end
        d = dir(trace_file(s.session_path, models{mi}, cfg.use_template));
        x = tr;
        dev = abs(x - median(x, 'omitnan'));
        [pk, pf] = max(dev);
        rows{end+1} = table(string(s.cell_hash), string(s.session_path), string(s.session_name), ...
            s.cell_id, string(models{mi}), pk / (1.4826 * median(dev, 'omitnan')), pf, false, d(1).datenum, ...
            'VariableNames', {'cell_hash', 'session_path', 'session_name', 'cell_id', 'model', ...
            'artifact_ratio', 'peak_frame', 'is_artifact', 'trace_datenum'}); %#ok<AGROW>
    end
end
if ~isempty(rows)
    art = [art; vertcat(rows{:})];
    save(cache_file, 'art');
end

art.is_artifact = art.artifact_ratio > cfg.artifact_max_sigma;
bad_raw = sortrows(art(art.is_artifact & art.model == "raw", :), 'artifact_ratio', 'descend');
writetable(bad_raw, fullfile(save_dir, 'excluded_artifact_cells.csv'));

% rerun list: model traces flagged (raw-flagged cells are just excluded, not rerun)
rerun_t = sortrows(art(art.is_artifact & art.model ~= "raw", :), {'model', 'artifact_ratio'}, {'ascend', 'descend'});
rerun = table2struct(rerun_t(:, {'session_path', 'model', 'cell_id', 'cell_hash', 'artifact_ratio', 'peak_frame'}));
save(fullfile(save_dir, 'rerun_template_mask.mat'), 'rerun');
writetable(rerun_t(:, {'session_path', 'session_name', 'model', 'cell_id', 'cell_hash', 'artifact_ratio', 'peak_frame'}), ...
    fullfile(save_dir, 'rerun_template_mask.csv'));

fprintf('flag_trace_artifacts: %d raw traces flagged (cells excluded); %d model traces flagged for rerun (> %g robust sigma)\n', ...
    height(bad_raw), height(rerun_t), cfg.artifact_max_sigma);
if ~isempty(rerun_t), disp(groupsummary(rerun_t, 'model')); end
end

function f = trace_file(session_path, model, use_template)
% same file load_model_trace.m reads
d = string(session_path);
if string(model) ~= "raw", d = fullfile(d, model); end
if use_template
    f = char(fullfile(d, 'template_mask_results', 'Masks_BestIcaTrace_template.mat'));
else
    f = char(fullfile(d, 'Masks_BestIcaTrace.mat'));
end
end
