function stim = classify_sessions_by_stim(config)
%CLASSIFY_SESSIONS_BY_STIM  Per-SESSION (not per-cell) stim classification,
% cached and resumable like select_noise_windows.m. Sessions are classified
% once and reused by every cell in that session.
%
%   stim = classify_sessions_by_stim()
%   stim = classify_sessions_by_stim(config)   % config: see load_analysis_config.m
%
% Table columns:
%   session_path, had_stim_data (get_stim_protocol succeeded), stim_frac
%   (fraction of frames above cfg.stim_thresh), has_stim (stim_frac > 0)
%
% A session counts as "no stim" only when had_stim_data is true and
% has_stim is false, i.e. stim data was found and it shows no stimulated
% frames. had_stim_data = false means "unknown", not "no stim" - see
% stim_vs_nostim_comparison.m, which keeps that group separate.
if nargin < 1, config = []; end
[root_path, code_path] = setup_analysis_paths();
cfg = load_analysis_config(config);
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
stim_file = fullfile(save_dir, 'stim_regions.mat');

sessions = load_session_list(root_path, code_path, cfg.sessions_file, cfg.sel_sessions, cfg.invert_sel_sessions, cfg.dataset_list);
session_paths = unique(string({sessions.session_path}), 'stable');

if isfile(stim_file)
    stim = load(stim_file, 'stim').stim;
else
    stim = table('Size', [0 4], 'VariableTypes', {'string','logical','double','logical'}, ...
        'VariableNames', {'session_path','had_stim_data','stim_frac','has_stim'});
end

n_new = 0;
for k = 1:numel(session_paths)
    sp = session_paths(k);
    if any(stim.session_path == sp), continue; end
    try
        tr = load_model_trace(char(sp), 'raw', cfg.use_template);   % any cell's trace, just need n_frames
        n_frames = size(tr, 1);
        [mask, had_data] = load_stim_mask(char(sp), n_frames, cfg);
    catch err
        warning('Skipping stim classification for %s: %s', sp, err.message);
        continue;
    end
    frac = mean(mask);
    stim(end+1, :) = {sp, had_data, frac, had_data && frac > 0}; %#ok<AGROW>
    n_new = n_new + 1;
    if mod(n_new, 25) == 0, save(stim_file, 'stim'); end   % resume-safe
end
save(stim_file, 'stim');

fprintf('Stim classification: %d sessions (%d new): %d no-stim, %d has-stim, %d unknown (no stim data found).\n', ...
    height(stim), n_new, sum(~stim.has_stim & stim.had_stim_data), sum(stim.has_stim), sum(~stim.had_stim_data));
end
