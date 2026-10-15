function n_kept = filter_sessions_by_metric(cell_type, metric_field, cutoff, nv)
%FILTER_SESSIONS_BY_METRIC  Build a new cached session list containing only
% cells that pass a cutoff on a metric from a previous audit, matched by
% cell_hash. Lets you chain audits/generation without hand-building a
% sel_sessions list: save the filtered list under a new save_str, then point
% a later psnr_audit_headless / firing_rate_audit_headless /
% dataset_generation_headless call's save_str at it with use_cache=true.
%
%   filter_sessions_by_metric('BTSP_no_stim', 'psnr_db', 15, new_save_str='psnr15')
%   filter_sessions_by_metric('BTSP_no_stim', 'avg_firing_rate_hz', 0.5, new_save_str='fr0p5')
%
% Required:
%   cell_type     dataset name (same as used for the audits)
%   metric_field  field in the audit summary struct to threshold on:
%                 'psnr_db' (from psnr_audit_summary.mat), or
%                 'avg_firing_rate_hz' / 'max_firing_rate_hz' (from
%                 firing_rate_audit.mat)
%   cutoff        keep rows where metric_field >= cutoff. NaN rows (e.g. no
%                 valid PSNR window, or no stim-free window for max rate)
%                 are dropped automatically since NaN >= cutoff is false.
%
% Name-value:
%   new_save_str     (required) save_str for the filtered session list --
%                    both its filename suffix (total_sessions_<new_save_str>.mat)
%                    and the output subdirectory a later audit/generation
%                    call with this save_str will use.
%   source_save_str  save_str the ORIGINAL total_sessions_<save_str>.mat and
%                    the audit were produced under. Default "".
%   audit_mat_path   override the audit .mat path directly instead of
%                    inferring it from metric_field + source_save_str (default
%                    inference: psnr_db -> <source>/psnr_audit/psnr_audit_summary.mat;
%                    *firing_rate_hz -> <source>/firing_rate_audit/firing_rate_audit.mat).
%
% Chaining example -- re-audit firing rate on only the cells that passed a
% PSNR cutoff, without generating anything yet:
%   filter_sessions_by_metric('BTSP_no_stim', 'psnr_db', 15, new_save_str='psnr15')
%   firing_rate_audit_headless(root_dirs, 'BTSP_no_stim', save_str='psnr15', use_cache=true)
arguments
    cell_type {mustBeTextScalar}
    metric_field {mustBeTextScalar}
    cutoff (1,1) double
    nv.new_save_str {mustBeTextScalar}
    nv.source_save_str {mustBeTextScalar} = ""
    nv.audit_mat_path {mustBeTextScalar} = ""
end

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
cell_type_dir = fullfile(code_path, 'SUPPORT-denoising', 'datasets', char(cell_type));
source_save_str = char(nv.source_save_str);
save_dir = fullfile(cell_type_dir, source_save_str);

audit_mat_path = char(nv.audit_mat_path);
if isempty(audit_mat_path)
    metric_field_c = char(metric_field);
    if strcmp(metric_field_c, 'psnr_db')
        audit_mat_path = fullfile(save_dir, 'psnr_audit', 'psnr_audit_summary.mat');
    elseif ismember(metric_field_c, {'avg_firing_rate_hz', 'max_firing_rate_hz'})
        audit_mat_path = fullfile(save_dir, 'firing_rate_audit', 'firing_rate_audit.mat');
    else
        error('Cannot infer audit_mat_path for metric_field "%s"; pass audit_mat_path explicitly.', metric_field_c);
    end
end
assert(isfile(audit_mat_path), 'Audit file not found: %s', audit_mat_path);

S = load(audit_mat_path);
vn = fieldnames(S);
summary = S.(vn{1});
assert(isfield(summary, metric_field), 'Field "%s" not found in %s (variable "%s").', ...
    metric_field, audit_mat_path, vn{1});
assert(isfield(summary, 'hash_id'), '%s has no hash_id field to match against total_sessions.cell_hash.', audit_mat_path);

vals = [summary.(metric_field)];
mask = vals >= cutoff; % NaN rows naturally excluded: NaN >= cutoff is false
fprintf('%d/%d cells pass %s >= %g (from %s)\n', nnz(mask), numel(summary), metric_field, cutoff, audit_mat_path);
keep_hashes = string({summary(mask).hash_id});

orig_sessions_mat = fullfile(cell_type_dir, sprintf('total_sessions_%s.mat', source_save_str));
assert(isfile(orig_sessions_mat), 'Original session cache not found: %s', orig_sessions_mat);
T = load(orig_sessions_mat, 'total_sessions');
total_sessions = T.total_sessions;
keep = ismember(string({total_sessions.cell_hash}), keep_hashes);
fprintf('%d/%d sessions in %s matched by cell_hash.\n', nnz(keep), numel(total_sessions), orig_sessions_mat);
total_sessions = total_sessions(keep); %#ok<NASGU>

new_save_str = char(nv.new_save_str);
new_cell_type_dir_save = fullfile(cell_type_dir, new_save_str);
if ~exist(new_cell_type_dir_save, 'dir'); mkdir(new_cell_type_dir_save); end
new_sessions_mat = fullfile(cell_type_dir, sprintf('total_sessions_%s.mat', new_save_str));
save(new_sessions_mat, 'total_sessions');
n_kept = nnz(keep);
fprintf('Saved %d filtered session(s) to %s\n', n_kept, new_sessions_mat);
fprintf('Point a later call at this list with: save_str=''%s'' use_cache=true\n', new_save_str);
end
