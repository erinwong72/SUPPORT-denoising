function flagged = reviewFlaggedICA(save_dirs)
% REVIEWFLAGGEDICA  Collect the ICA cells flagged for manual review across sessions.
%
% flagged = reviewFlaggedICA(save_dirs)
%
% save_dirs : cell array of save_dir paths (the folders ICA_Choose.m wrote
%             ICA_AutoSelect_Log.mat into — session_path or session_path/
%             support_dirname, matching what was passed to ICA_Choose).
%
% Returns a table of every logged decision with Confident==false, sorted by
% score ascending (worst/most uncertain first), and prints it. For each row
% you can reopen the saved figures directly:
%   openfig(fullfile(row.SessionPath, [num2str(row.Cell) 'ICAImg.fig']))
%   openfig(fullfile(row.SessionPath, [num2str(row.Cell) 'ICATrace.fig']))
% (paths saved by ICA_Choose are relative to save_dir, not session_path, when
% use_support is true — pass the matching save_dir list.)

allLogs = table();
for k = 1:numel(save_dirs)
    log_file = fullfile(save_dirs{k}, 'ICA_AutoSelect_Log.mat');
    if ~isfile(log_file)
        continue
    end
    s = load(log_file, 'autoLog');
    allLogs = [allLogs; s.autoLog]; %#ok<AGROW>
end

if isempty(allLogs)
    warning('No ICA_AutoSelect_Log.mat files found under the given save_dirs.');
    flagged = allLogs;
    return
end

flagged = allLogs(~allLogs.Confident, :);
flagged = sortrows(flagged, 'Score', 'ascend');

fprintf('%d / %d logged cells flagged for review (%.0f%% auto-accepted).\n', ...
    height(flagged), height(allLogs), 100*(1 - height(flagged)/height(allLogs)));
disp(flagged);
end
