function out_file = write_training_sessions(cell_type, psnr_cutoff, nv)
%WRITE_TRAINING_SESSIONS  Final session list for training: one row per
% recording that has at least one hand-accepted window (from
% review_firing_rate_windows.m), saved in the dataset root as
%
%   datasets/<cell_type>/total_sessions_psnr<cutoff>_training.mat
%
% (e.g. total_sessions_psnr17_training.mat for a cutoff of 17 dB; 17.5 ->
% psnr17p5). The variable inside is `total_sessions`, same convention as the
% other total_sessions_*.mat files.
%
%   write_training_sessions('BTSP', 17)
%   write_training_sessions('BTSP', 17, save_str='psnr17')
%
% Each row is the original total_sessions row for that cell (matched by
% cell_hash) plus the windows that were selected from it:
%   window_starts           1xN start frames of the accepted windows
%   window_len              frames per window (window_lens if they differ)
%   window_firing_rates_hz  1xN firing rate of each window
%   n_windows, psnr_db      number of windows; the cell's audited PSNR (NaN if
%                           no audit was found)
% Windows whose cell has an audited PSNR below the cutoff are dropped (so the
% file really is "psnr >= cutoff"); cells missing from the audit are kept with
% a warning.
%
% Name-value options:
%   save_str        folder/list the window selection was made under (default
%                   "psnr<cutoff>", e.g. psnr17): reads
%                   datasets/<cell_type>/<save_str>/window_selection/window_selection.mat
%                   and the session rows from total_sessions_<save_str>.mat.
%   source_save_str save_str of the ORIGINAL list the PSNR audit was run under
%                   (default ""): audit read from
%                   datasets/<cell_type>/<source>/psnr_audit/psnr_audit_summary.mat,
%                   and used as the fallback session list.
%   window_selection_file  override the window_selection.mat path.
%   check_psnr      logical, default true: apply the cutoff against the audit.
arguments
    cell_type {mustBeTextScalar}
    psnr_cutoff (1,1) double
    nv.save_str {mustBeTextScalar} = ""
    nv.source_save_str {mustBeTextScalar} = ""
    nv.window_selection_file {mustBeTextScalar} = ""
    nv.check_psnr (1,1) logical = true
end

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
cell_type_dir = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));

if psnr_cutoff == round(psnr_cutoff)
    cutoff_str = sprintf('%d', psnr_cutoff);
else
    cutoff_str = strrep(sprintf('%g', psnr_cutoff), '.', 'p');
end
save_str = char(nv.save_str);
if isempty(save_str); save_str = ['psnr' cutoff_str]; end
source_save_str = char(nv.source_save_str);

sel_file = char(nv.window_selection_file);
if isempty(sel_file)
    sel_file = fullfile(cell_type_dir, save_str, 'window_selection', 'window_selection.mat');
end
assert(isfile(sel_file), 'window_selection.mat not found: %s', sel_file);
W = load(sel_file, 'selected_windows', 'params');
sw = W.selected_windows;
assert(~isempty(sw), 'No accepted windows in %s', sel_file);

% session rows to pull from: the list the selection was made under, else the original
sessions_mat = fullfile(cell_type_dir, sprintf('total_sessions_%s.mat', save_str));
if ~isfile(sessions_mat)
    sessions_mat = fullfile(cell_type_dir, sprintf('total_sessions_%s.mat', source_save_str));
end
assert(isfile(sessions_mat), 'No session list found (tried total_sessions_%s.mat and total_sessions_%s.mat in %s)', ...
    save_str, source_save_str, cell_type_dir);
T = load(sessions_mat, 'total_sessions');
all_sessions = convert_struct_paths(T.total_sessions, root_path);

% PSNR per window's cell, from the audit
win_hash = string({sw.hash_id});
win_psnr = nan(1, numel(sw));
audit_mat = fullfile(cell_type_dir, source_save_str, 'psnr_audit', 'psnr_audit_summary.mat');
if isfile(audit_mat)
    A = load(audit_mat, 'psnr_summary');
    p = [A.psnr_summary.psnr_db];
    p(imag(p) ~= 0) = NaN;
    [found, loc] = ismember(win_hash, string({A.psnr_summary.hash_id}));
    win_psnr(found) = real(p(loc(found)));
else
    warning('PSNR audit not found (%s); the cutoff is not being verified.', audit_mat);
end
if nv.check_psnr && isfile(audit_mat)
    unknown = isnan(win_psnr);
    below = ~unknown & win_psnr < psnr_cutoff;
    if any(unknown)
        warning('%d selected window(s) have no audited PSNR; keeping them.', nnz(unknown));
    end
    if any(below)
        fprintf('Dropping %d window(s) from cells with PSNR < %g:\n', nnz(below), psnr_cutoff);
        for i = find(below)
            fprintf('  %s_%s cell %d: %.2f dB\n', sw(i).hash_id, sw(i).sess_id, sw(i).cell_id, win_psnr(i));
        end
    end
    keep_win = ~below;
    sw = sw(keep_win); win_hash = win_hash(keep_win); win_psnr = win_psnr(keep_win);
    assert(~isempty(sw), 'No selected windows left after applying the PSNR cutoff of %g.', psnr_cutoff);
end

% one row per recording, in the order recordings first appear in the selection
hashes = unique(win_hash, 'stable');
[found, loc] = ismember(hashes, string({all_sessions.cell_hash}));
if any(~found)
    warning('%d selected cell(s) not found in %s; skipping: %s', nnz(~found), sessions_mat, strjoin(hashes(~found), ', '));
end
hashes = hashes(found);
training_sessions = all_sessions(loc(found));
n_windows_total = 0;
for k = 1:numel(hashes)
    m = win_hash == hashes(k);
    w = sw(m);
    training_sessions(k).window_starts = [w.start];
    if numel(unique([w.len])) == 1
        training_sessions(k).window_len = w(1).len;
    else
        training_sessions(k).window_len = [w.len];
    end
    training_sessions(k).window_firing_rates_hz = [w.window_firing_rate_hz];
    training_sessions(k).n_windows = numel(w);
    training_sessions(k).psnr_db = win_psnr(find(m, 1));
    n_windows_total = n_windows_total + numel(w);
end
total_sessions = training_sessions; %#ok<NASGU>

out_file = fullfile(cell_type_dir, sprintf('total_sessions_psnr%s_training.mat', cutoff_str));
save(out_file, 'total_sessions');
fprintf('Saved %d recording(s) / %d window(s) (PSNR >= %g) to %s\n', numel(training_sessions), n_windows_total, psnr_cutoff, out_file);
if isfield(W, 'params') && isfield(W.params, 'n_windows_target')
    fprintf('  (target was %d window(s))\n', W.params.n_windows_target);
end
end
