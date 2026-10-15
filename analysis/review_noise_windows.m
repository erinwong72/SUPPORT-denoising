function review_noise_windows(config)
% review_noise_windows.m
% Usage: review_noise_windows()  or  review_noise_windows('my_config')  - config = name of a
% config file in configs/analysis (see load_analysis_config.m).
% Interactive review of the automatically chosen noise windows
% (like ICA_Choose: auto first, you confirm or fix). Run interactively.
%
% Works through cells in this order: needs_manual, then flagged 'auto',
% then (if review_all) the remaining unreviewed 'auto' cells. Each decision
% is saved immediately, so you can quit (q) and resume.
%
%   status     auto | confirmed | manual | needs_manual
%   no_signal  true if you pressed n: the cell has no usable signal.
%              support_model_comparison.m leaves these out (cfg.exclude_no_signal).
%              To undo: noise.no_signal(idx) = false; save(noise_file, 'noise')
%
% Picking a new window: click its start. It must be spike-free for the selected
% length, 1000 frames by default (valid for both the PSNR window and the
% 1000-frame alternative). Press l to switch to 300 frames (cfg.pick_lens), e.g.
% when a clean 1000-frame stretch doesn't exist; the 1000-frame alternative is
% then left out for that cell. l also re-checks the same click at the other length.
%
% After reviewing, re-run support_model_comparison.m: rows whose window
% changed are recomputed automatically.
arguments
    config = []   % name of a config in configs/analysis (required if there are several) or a cfg struct
end
close all;
review_all = true;      % false: only look at needs_manual + flagged cells

[root_path, ~] = setup_analysis_paths();
cfg = load_analysis_config(config);
save_dir = fullfile(root_path, cfg.save_subdir, cfg.filestr);
noise_file = fullfile(save_dir, 'noise_regions.mat');
assert(isfile(noise_file), 'No noise_regions.mat yet - run select_noise_windows.m first.');
noise = load_noise_table(noise_file);
noise = convert_struct_paths(noise, root_path);

% review order
pri = 3 * ones(height(noise), 1);
pri(noise.status == "auto" & strlength(erase(noise.flag, ["continuous_stim", "psnr_audit"])) > 0) = 2;   % continuous_stim alone isn't a reason to flag
pri(noise.status == "needs_manual") = 1;
todo = find(noise.status ~= "confirmed" & noise.status ~= "manual" & ~noise.no_signal);
if ~review_all, todo = todo(pri(todo) < 3); end
[~, o] = sort(pri(todo)); todo = todo(o);
fprintf('%d cells to review (%d needs_manual, %d flagged)\n', numel(todo), ...
    sum(pri(todo) == 1), sum(pri(todo) == 2));

for t = 1:numel(todo)
    i = todo(t);
    row = noise(i, :);
    try
        tr = load_model_trace(row.session_path, cfg.pick_noise_on, cfg.use_template, row.cell_id);
        sp = load_spikes(row.session_path, 'raw', cfg.use_template, row.cell_id);
        stim = load_stim_mask(char(row.session_path), numel(tr), cfg);
    catch err
        warning('Skipping %s: %s', row.cell_hash, err.message);
        continue;
    end
    label = sprintf('[%d/%d] %s  flag: %s', t, numel(todo), row.cell_hash, row.flag);
    cfg_row = cfg;                                   % show / require the length this window was validated for
    if isfinite(row.valid_len)
        cfg_row.max_len = row.valid_len; cfg_row.noise_len = min(cfg.noise_len, row.valid_len);
    end
    % lengths you can pick a NEW window for (press l in the picker): cfg.pick_lens, plus this
    % cell's own validated length if it was rescued at something else
    pick_lens = sort(unique([cfg.pick_lens, cfg_row.max_len]), 'descend');
    [start, action, valid_len] = pick_noise_window(tr, sp, cfg_row, label, stim, row.start, pick_lens);
    switch action
        case 'accept', noise.status(i) = "confirmed";
        case 'manual', noise.status(i) = "manual"; noise.start(i) = start;
            noise.valid_len(i) = valid_len; noise.source(i) = "manual";
        case 'no_signal', noise.no_signal(i) = true;
        case 'skip',   continue
        case 'quit',   break
    end
    save(noise_file, 'noise');
end
save(noise_file, 'noise');
fprintf('Done. status counts:\n'); disp(groupsummary(noise, 'status'));
end
