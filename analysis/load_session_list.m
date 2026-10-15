function sessions = load_session_list(root_path, code_path, sessions_file, sel_sessions, invert_sel, dataset_names)
%LOAD_SESSION_LIST  One entry per cell from the headless session list, with
% session_path converted to THIS machine's fanlab root via convert_struct_paths
% (handles Windows Z:\, a UNC path, or a Linux /mnt/fanlab-saved path -
% whichever machine last wrote the sessions file - not just Z:\).
%
% Sessions whose session_path directory has no support_* subfolder yet
% (i.e. SUPPORT processing hasn't finished) are dropped.
%
%   sessions = load_session_list(root_path, code_path)
%   sessions = load_session_list(root_path, code_path, sessions_file)
%   sessions = load_session_list(root_path, code_path, sessions_file, sel_sessions, invert_sel, dataset_names)
%
% sessions_file may be a cellstr (one file per dataset, cfg.sessions_file with several datasets): the lists are
% pooled, keeping only the fields they share, and a cell that appears in more than one list is kept once (first
% one wins). Every session gets a `dataset` field (dataset_names{i}, or '' when no names are given).
% sel_sessions / invert_sel (cfg.sel_sessions, cfg.invert_sel_sessions): optional
% subset by animal/day/slice/FOV/cell/session_name, see filterSessionsBySelector.m.
if nargin < 3 || isempty(sessions_file)
    sessions_file = fullfile(code_path, 'SUPPORT-denoising/datasets/w25_w27_specific/total_sessions_.mat');
end
if nargin < 6, dataset_names = {}; end
files = cellstr(sessions_file);
if numel(dataset_names) ~= numel(files)
    if ~isempty(dataset_names) && numel(files) == 1, dataset_names = dataset_names(1); else, dataset_names = repmat({''}, 1, numel(files)); end
end
parts = cell(1, numel(files));
for i = 1:numel(files)
    f = files{i};
    if ~isfile(f), f = to_local_path(f, root_path); end   % saved as another OS's path
    if ~isfile(f) && isfile(fullfile(code_path, f))
        f = fullfile(code_path, f);   % relative to the code folder
    end
    sl = load(f);
    part = convert_struct_paths(sl.total_sessions, root_path);
    part = part(:)';
    [part.dataset] = deal(char(dataset_names{i}));
    parts{i} = part;
end
if numel(parts) == 1
    sessions = parts{1};
else
    common = fieldnames(parts{1});
    for i = 2:numel(parts), common = intersect(common, fieldnames(parts{i}), 'stable'); end
    for i = 1:numel(parts), parts{i} = rmfield(parts{i}, setdiff(fieldnames(parts{i}), common)); end
    sessions = [parts{:}];
    [~, first] = unique(string({sessions.cell_hash}), 'stable');
    if numel(first) < numel(sessions)
        fprintf('load_session_list: %d cell(s) appear in more than one dataset; keeping the first.\n', numel(sessions) - numel(first));
    end
    sessions = sessions(sort(first));
    fprintf('load_session_list: pooled %d cells from %d datasets (%s).\n', numel(sessions), numel(files), strjoin(dataset_names, ', '));
end
if nargin >= 4 && ~isempty(sel_sessions)
    if nargin < 5, invert_sel = false; end
    sessions = filterSessionsBySelector(sessions, sel_sessions, invert_sel);
end

is_processed = false(numel(sessions), 1);
for k = 1:numel(sessions)
    is_processed(k) = ~isempty(dir(fullfile(sessions(k).session_path, 'support_*')));
end
if any(~is_processed)
    fprintf('load_session_list: skipping %d/%d sessions not yet fully processed (no support_* folder).\n', ...
        sum(~is_processed), numel(sessions));
end
sessions = sessions(is_processed);
end
