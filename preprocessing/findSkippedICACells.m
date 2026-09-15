function skippedIdx = findSkippedICACells(save_dir, use_template)
% FINDSKIPPEDICACELLS  Cell indices left undecided by an unattended
% ICA_Choose run (use_auto=true, auto_skip_flagged=true).
%
% skippedIdx = findSkippedICACells(save_dir, use_template)
%
% A skipped cell has its IntensOrig column entirely NaN. Feed the result
% straight back into ICA_Choose as cell_subset to pick just those cells
% interactively — previously-decided cells are preserved automatically.
%
% Example:
%   save_dir = fullfile(session_path, support_dirname);
%   skipped = findSkippedICACells(save_dir, false);
%   if ~isempty(skipped)
%       ICA_Choose(session_path, use_support, support_dirname, 0, false, false, skipped);
%   end

if nargin < 2
    use_template = false;
end
if use_template
    trace_file = fullfile(save_dir, 'Masks_BestIcaTrace_template.mat');
else
    trace_file = fullfile(save_dir, 'Masks_BestIcaTrace.mat');
end

if ~isfile(trace_file)
    skippedIdx = [];
    return
end

s = load(trace_file, 'IntensOrig');
skippedIdx = find(all(isnan(s.IntensOrig), 1));
end
