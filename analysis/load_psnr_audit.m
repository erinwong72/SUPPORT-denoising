function audit = load_psnr_audit(cfg, root_path, code_path)
%LOAD_PSNR_AUDIT  Noise windows from an earlier PSNR audit (psnr_audit_headless.m), if there is one.
%
%   audit = load_psnr_audit(cfg, root_path, code_path)
%
% Looks for psnr_audit_summary.mat (struct array `psnr_summary`) or .csv in cfg.psnr_audit_dir
% (default SUPPORT-denoising/datasets/{dataset}/psnr_audit, relative to the code folder unless
% absolute). Returns an empty table when cfg.reuse_psnr_audit is false or no audit is found.
%
% Columns: cell_hash (= the audit's hash_id), session_path, cell_id, noise_start (frame, whole
% recording, same coordinates as noise_regions.mat), noise_len_used, noise_std, flag, and
% ok = the audit found a valid window for that cell.
audit = table();
if ~cfg.reuse_psnr_audit, return; end
dirs = cellstr(cfg.psnr_audit_dir);          % one per dataset when several datasets are pooled
for k = 1:numel(dirs)
    a = read_one(dirs{k}, root_path, code_path);
    if ~isempty(a), audit = [audit; a]; end %#ok<AGROW>
end
if ~isempty(audit)
    [~, first] = unique(audit.cell_hash, 'stable');   % a cell in two audits: keep the first
    audit = audit(sort(first), :);
end
end

function audit = read_one(d, root_path, code_path)
audit = table();
if isempty(d), return; end
if ~isfolder(d), d = fullfile(code_path, d); end
d = to_local_path(d, root_path);
f_mat = fullfile(d, 'psnr_audit_summary.mat');
f_csv = fullfile(d, 'psnr_audit_summary.csv');
if isfile(f_mat)
    t = struct2table(load(f_mat, 'psnr_summary').psnr_summary);
elseif isfile(f_csv)
    t = readtable(f_csv, 'TextType', 'string');
else
    fprintf('No PSNR audit found in %s - choosing noise windows automatically.\n', d);
    return
end
audit = table(string(t.hash_id), string(t.session_path), t.cell_id, double(t.noise_start), ...
    double(t.noise_len_used), double(t.noise_std), string(t.flag), logical(t.has_valid_window), ...
    'VariableNames', {'cell_hash', 'session_path', 'cell_id', 'noise_start', 'noise_len_used', 'noise_std', 'flag', 'has_valid_window'});
audit.ok = audit.has_valid_window & isfinite(audit.noise_start) & audit.noise_start >= 1 & audit.noise_len_used >= 1;
fprintf('PSNR audit: %d cells (%d with a valid noise window) from %s\n', height(audit), nnz(audit.ok), d);
end
