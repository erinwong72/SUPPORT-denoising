function sessions = generate_sessions_struct(discovered_sessions, path, sel_FOVs, sel_slices, save_flag)
% Inputs:
%   discovered_sessions - struct array from discover_sessions.m with fields:
%                           anim_id, session_path, session_name, FOV, cell_id,
%                           fov_num_cells, date, slice, cell_hash
%   path           - struct with fields:
%                       path.save_dir
%                       path.anim_id
%                       path.sess_id
%   sel_FOVs        - vector of FOV indices to include (empty = include all)
%   sel_slices     - cell array of slice names or vector of slice indices to include (empty = include all)
%   waveform_stim  - string or cell array of strings used to filter session directories (empty = include all)
%   save_flag      - logical flag for whether or not to save the generated session

% Output:
%   sessions       - struct array with fields:
%                       anim_id
%                       session_path
%                       session_name
%                       FOV
%                       cell_id
%                       fov_num_cells
%                       cell_hash

%% Try loading cached sessions
% if nargin >= 2 && isstruct(path) && isfield(path, 'save_dir') && ~isempty(path.save_dir)
%     sessions_file = fullfile(path.save_dir, 'sessions.mat'); %'sessions_modified.mat'
    
%     if exist(sessions_file, 'file')
%         load(sessions_file, 'sessions');
        
%         return
%     end
% end

%% Filter discovered sessions based on criteria

% Initialize filter mask (true = keep, false = exclude)
keep_mask = true(size(discovered_sessions));

% filter by session id (path.sess_ids)
if nargin >= 2 && isstruct(path) && isfield(path, 'sess_id') && ~isempty(path.sess_id)
    % get session id from session_path
    session_ids = {discovered_sessions.session_path};
    % extract session id from session_path using strsplit
    session_ids = cellfun(@(x) strsplit(x, filesep), session_ids, 'UniformOutput', false);
    session_ids = cellfun(@(x) x{end-3}, session_ids, 'UniformOutput', false);
    % check if path.sess_ids is in session_ids
    keep_mask = keep_mask & ismember(session_ids, path.sess_id);
end

% Filter by FOV
if nargin >= 3 && ~isempty(sel_FOVs)
    fov_values = [discovered_sessions.FOV];
    keep_mask = keep_mask & ismember(fov_values, sel_FOVs);
end

% Filter by slice
if nargin >= 4 && ~isempty(sel_slices)
    % Handle both cell array of strings and numeric array
    % create new field 'slice' in discovered_sessions from path in discovered_sessions
    for i = 1:numel(discovered_sessions)
        path_parts = strsplit(discovered_sessions(i).session_path, filesep);
        discovered_sessions(i).slice = path_parts{end-2};
    end

    if iscell(sel_slices)
        % sel_slices is cell array of slice names
        slice_names = {discovered_sessions.slice};
        keep_mask = keep_mask & ismember(slice_names, sel_slices);
    elseif isnumeric(sel_slices) || islogical(sel_slices)
        slice_names = {discovered_sessions.slice};
        slice_nums = NaN(size(slice_names));
        for i = 1:numel(slice_names)
            num_match = regexp(slice_names{i}, '\d+', 'match');
            if ~isempty(num_match)
                slice_nums(i) = str2double(num_match{1});
            end
        end
        keep_mask = keep_mask & ismember(slice_nums, sel_slices);
    else
        % Single string
        slice_names = {discovered_sessions.slice};
        keep_mask = keep_mask & strcmp(slice_names, sel_slices);
    end
end

% Filter by waveform_stim (session name must contain at least one of the strings)
% if nargin >= 5 && ~isempty(waveform_stim)
%     session_names = {discovered_sessions.session_name};
%     if iscell(waveform_stim)
%         stim_mask = false(size(session_names));
%         for i = 1:numel(waveform_stim)
%             stim_mask = stim_mask | contains(session_names, waveform_stim{i});
%         end
%         keep_mask = keep_mask & stim_mask;
%     elseif ischar(waveform_stim) || isstring(waveform_stim)
%         keep_mask = keep_mask & contains(session_names, waveform_stim);
%     end
% end

% Apply filter
sessions = discovered_sessions(keep_mask);

% Save if requested
if nargin >= 6 && save_flag && isstruct(path) && isfield(path, 'save_dir') && ~isempty(path.save_dir)
    save(fullfile(path.save_dir, 'sessions'), "sessions");
end
