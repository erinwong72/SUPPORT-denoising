function noise = select_noise_windows(sessions_file, config)
%SELECT_NOISE_WINDOWS  Automatic noise-window pick for every cell (headless-safe).
%
%   noise = select_noise_windows()
%   noise = select_noise_windows(sessions_file, config)   % [] = default; config: see load_analysis_config.m
%
% Skips cells that already have a row, so it is safe to re-run and resumes
% after an interruption. Cells that need a human look (flagged, or no valid
% window) are reported; review them with review_noise_windows.m.
%
% Table columns: cell_hash, session_path, cell_id, start, status
% (auto / confirmed / manual / needs_manual), flag, n_valid, noise_std,
% no_signal (set by you in review_noise_windows.m; the comparison can skip these),
% valid_len (frames the window is spike/stim-free for), source (trace it was picked on).
%
% Cells with no valid window at the full length fall back (auto_noise_window_fallback.m):
% cleaned traces, then shorter windows down to cfg.min_noise_len. Rows still marked
% needs_manual are retried on every run. If stim is on for >= cfg.continuous_stim_frac of the
% recording (shutter open the whole time), the stim rule is dropped for that cell.

if nargin < 2, config = []; end
[root_path, code_path] = setup_analysis_paths();
cfg = load_analysis_config(config);
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
if ~exist(save_dir, 'dir'), mkdir(save_dir); end
noise_file = fullfile(save_dir, 'noise_regions.mat');
if nargin < 1 || isempty(sessions_file), sessions_file = cfg.sessions_file; end
if isempty(sessions_file)
    sessions_file = fullfile(code_path, 'SUPPORT-denoising/datasets/optoCCKBC-activation_BTSP/total_sessions_.mat');
    fprintf('Using default sessions file: %s\n', sessions_file);
else
    fprintf('Using sessions file(s): %s\n', strjoin(cellstr(sessions_file), ', '));
end
sessions = load_session_list(root_path, code_path, sessions_file, cfg.sel_sessions, cfg.invert_sel_sessions, cfg.dataset_list);

noise = load_noise_table(noise_file, cfg);

% cells that previously had no valid window (and that you haven't marked no_signal) get another go
% with the fallbacks in auto_noise_window_fallback.m
retry = noise.status == "needs_manual" & ~noise.no_signal;
noise = noise(~retry, :);
n_retry = nnz(retry);

% noise windows from an earlier PSNR audit (psnr_audit_headless.m), reused instead of picking new ones so
% PSNR matches the audit exactly. Reviewed cells (confirmed / manual / no_signal) keep your own window.
audit = load_psnr_audit(cfg, root_path, code_path);
use_audit = ~isempty(audit);
n_audit = 0;
if use_audit
    for i = 1:height(noise)
        if noise.status(i) ~= "auto" || noise.no_signal(i), continue; end
        j = find(audit.cell_hash == noise.cell_hash(i) & audit.ok, 1);
        if isempty(j) || (noise.start(i) == audit.noise_start(j) && noise.valid_len(i) == audit.noise_len_used(j)), continue; end
        noise(i, :) = audit_row(noise.cell_hash(i), noise.session_path(i), noise.cell_id(i), audit(j, :));
        n_audit = n_audit + 1;
    end
end

n_new = 0;
for k = 1:numel(sessions)
    s = sessions(k);
    if any(noise.cell_hash == string(s.cell_hash)), continue; end
    if use_audit
        j = find(audit.cell_hash == string(s.cell_hash) & audit.ok, 1);
        if ~isempty(j)
            noise(end+1, :) = audit_row(string(s.cell_hash), string(s.session_path), s.cell_id, audit(j, :)); %#ok<AGROW>
            n_new = n_new + 1; n_audit = n_audit + 1;
            continue;
        end
    end
    try
        n_fr = size(load_model_trace(s.session_path, 'raw', cfg.use_template, s.cell_id), 1);
        sp = load_spikes(s.session_path, 'raw', cfg.use_template, s.cell_id);
        [stim, had_stim] = load_stim_mask(s.session_path, n_fr, cfg);
    catch err
        warning('Skipping noise pick for %s: %s', s.cell_hash, err.message);
        continue;
    end
    continuous = had_stim && mean(stim) >= cfg.continuous_stim_frac;
    if continuous, stim = false(size(stim)); end     % light on the whole recording: only the spike rule can apply
    get_trace = @(src) load_model_trace(s.session_path, src, cfg.use_template, s.cell_id);
    [start, info] = auto_noise_window_fallback(get_trace, sp, stim, cfg);
    flag = string(info.flag);
    if continuous && ~isnan(start)
        flag = strjoin([flag(strlength(flag) > 0), "continuous_stim"], ';');   % informational, not a review reason
    end
    if ~had_stim
        flag = strjoin([flag(strlength(flag) > 0), "no_stim_data"], ';');
    end
    status = "auto";
    if isnan(start), status = "needs_manual"; end
    noise(end+1, :) = {string(s.cell_hash), string(s.session_path), s.cell_id, start, ...
        status, flag, info.n_valid, info.noise_std, false, info.valid_len, info.source}; %#ok<AGROW>
    n_new = n_new + 1;
    if mod(n_new, 25) == 0, save(noise_file, 'noise'); end   % resume-safe
end
save(noise_file, 'noise');

% continuous_stim is informational; every other flag (and needs_manual) asks for a look
n_review = sum((strlength(erase(noise.flag, ["continuous_stim", "psnr_audit"])) > 0 | noise.status == "needs_manual") & ~noise.no_signal);
n_cont = sum(contains(noise.flag, "continuous_stim"));
fprintf('Noise windows: %d cells (%d new), %d confirmed/manual, %d no_signal, %d flagged or need review.\n', ...
    height(noise), n_new, sum(ismember(noise.status, ["confirmed", "manual"])), sum(noise.no_signal), n_review);
n_short = sum(contains(noise.flag, "short_window"));
n_clean = sum(contains(noise.flag, "picked_on_"));
n_left = sum(noise.status == "needs_manual" & ~noise.no_signal);
fprintf('  %d cells retried; %d windows shorter than %d frames, %d picked on cleaned data, %d under continuous stim (stim rule dropped); %d cells still have no valid window.\n', ...
    n_retry, n_short, cfg.noise_len, n_clean, n_cont, n_left);
if use_audit
    fprintf('  %d windows taken from the PSNR audit (flag psnr_audit).\n', n_audit);
end
if n_review > 0
    fprintf('  -> run review_noise_windows.m interactively to check them.\n');
end
end

function row = audit_row(cell_hash, session_path, cell_id, a)
% noise_regions.mat row (same columns as the picker's rows) from one PSNR-audit row
row = {cell_hash, session_path, cell_id, a.noise_start, "auto", "psnr_audit", NaN, a.noise_std, false, ...
    a.noise_len_used, "raw"};
end
