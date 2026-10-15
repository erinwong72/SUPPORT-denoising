function reprocessDisagreedICA(opts)
% REPROCESSDISAGREEDICA  Manually re-pick ICA components for every cell
% reviewIntensICA.m marked disagreed (or auto-flagged as "no mask chosen").
%
% reprocessDisagreedICA(opts)
%
% For each entry in the disagreed list, opens ICA_Choose interactively
% (figures visible, use_auto=false) restricted to just that entry's cells
% via cell_subset — cells outside it keep whatever was already decided.
%
% Required (one of):
%   opts.disagreed       the struct returned by reviewIntensICA.m, OR
%   opts.disagreed_file  path to a saved ICA_Review_Disagreed.mat
%                         (default: fullfile(opts.dataset_dir, 'ICA_Review_Disagreed.mat'))
% Optional:
%   opts.use_support, opts.support.dirname   (must match how the sessions were processed)
%   opts.use_template   (default false)
%   opts.start_idx       index into the disagreed array to resume from —
%                         use this to pick up partway through the list
%                         instead of starting over at entry 1. Default 1.
%
% Example:
%   opts = struct('dataset_dir', out_dir, 'use_support', true, ...
%       'support', struct('dirname','support'), 'start_idx', 14);
%   reprocessDisagreedICA(opts)

if ~isfield(opts, 'use_support') || isempty(opts.use_support)
    opts.use_support = false;
end
if opts.use_support
    assert(isfield(opts, 'support') && isfield(opts.support, 'dirname') ...
        && ~isempty(opts.support.dirname), ...
        'opts.support.dirname is required when use_support=true');
    support_dirname = opts.support.dirname;
else
    support_dirname = '';
end
if ~isfield(opts, 'use_template') || isempty(opts.use_template)
    opts.use_template = false;
end
if ~isfield(opts, 'start_idx') || isempty(opts.start_idx)
    start_idx = 1;
else
    start_idx = opts.start_idx;
end

if isfield(opts, 'disagreed') && ~isempty(opts.disagreed)
    disagreed = opts.disagreed;
else
    if ~isfield(opts, 'disagreed_file') || isempty(opts.disagreed_file)
        assert(isfield(opts, 'dataset_dir') && ~isempty(opts.dataset_dir), ...
            'Provide opts.disagreed, opts.disagreed_file, or opts.dataset_dir (to find ICA_Review_Disagreed.mat)');
        opts.disagreed_file = fullfile(opts.dataset_dir, 'ICA_Review_Disagreed.mat');
    end
    assert(isfile(opts.disagreed_file), 'File not found: %s', opts.disagreed_file);
    s = load(opts.disagreed_file, 'disagreed');
    disagreed = s.disagreed;
end

nEntries = numel(disagreed);
assert(start_idx >= 1 && start_idx <= max(nEntries,1), ...
    'opts.start_idx (%d) is out of range for %d disagreed entries', start_idx, nEntries);

fprintf('Reprocessing %d disagreed entr%s, starting at index %d.\n', ...
    nEntries, iff_str(nEntries==1,'y','ies'), start_idx);

for idx = start_idx:nEntries
    d = disagreed(idx);
    fprintf('\n=== %d/%d  %s  cells %s%s ===\n', idx, nEntries, d.session_path, mat2str(d.cells), ...
        iff_str(isempty(d.note), '', [' — ' d.note]));
    ICA_Choose(d.session_path, opts.use_support, support_dirname, opts.use_template, false, false, d.cells);
end

fprintf('\nDone reprocessing disagreed entries %d-%d.\n', start_idx, nEntries);
end

function out = iff_str(cond, a, b)
if cond; out = a; else; out = b; end
end
