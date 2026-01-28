function [sessions, stats] = filterSessions(sessions, varargin)
%FILTERSESSIONS Flexible filtering and curation of session structs.
%
%   SESSIONS = FILTERSESSIONS(SESSIONS, 'field', value, ...)
%   filters a struct array of sessions using arbitrary field-based criteria.
%   Filters are specified as name–value pairs, where the name corresponds to
%   a field in the sessions struct.
%
%   [SESSIONS, STATS] = FILTERSESSIONS(...) also returns summary statistics
%   describing the filtered sessions.
%
%   FILTER TYPES
%   Each filter value may be one of the following:
%
%   1) Numeric or logical array
%        Keeps sessions whose field value is a member of the array.
%        Example:
%           'FOV', [1 2 3]
%        if the parameter is 'snr', 'nspikes', or 'fr', it keeps sessions with
%        field values greater than the specified numeric threshold.
%        Example:
%           'snr', 1.0 --> keeps sessions with snr > 1.0
%
%   2) Cell array (typically of strings)
%        Keeps sessions whose field value matches one of the entries.
%        Example:
%           'slice', {'slice1','slice2'}
%
%   3) String or char array
%        Keeps sessions whose field value exactly matches the string.
%        Example:
%           'session_name', 'Spon30'
%
% --- more complicated, don't worry about these ---
%   4) Function handle (field-level rule)
%        Applies a user-defined predicate to the field value of each session.
%        The function must return a logical scalar.
%        Example:
%           'snr', @(x) x > 1.0
%
%   5) Rule object (session-level rule)
%        Applies a user-defined predicate to the entire session struct,
%        enabling cross-field and complex logic.
%        Rule objects are created using the RULE constructor.
%        Example:
%           'quality', rule(@(s) s.snr > 1.5 & s.nspikes > 20)
%
%   LOGICAL BEHAVIOR
%   All filters are combined using logical AND. A session is kept only if it
%   satisfies all specified filters. OR and NOT logic may be expressed within
%   individual function handles or rule objects.
%
%   OPTIONAL PARAMETERS
%       'verbose'        - Logical flag to print summary information before
%                          and after filtering (default: false)
%
%       'remove_fields'  - Cell array of field names to remove from the output
%                          sessions struct after filtering
%
%   OUTPUTS
%       sessions - Filtered struct array of sessions
%
%       stats    - Struct containing summary statistics:
%                    .num_recordings
%                    .num_anim
%                    .num_sess
%                    .num_cells
%
%   EXAMPLES
%       % Simple field matching
%       sessions = filterSessions(sessions, 'FOV', [1 2], 'slice', {'slice1'});
%       
%       % Threshold-based filtering
%       sessions = filterSessions(sessions, 'snr', @(x) x >= 1.0);
%
%       % Cross-field logic using a rule object
%       sessions = filterSessions( ...
%           sessions, ...
%           'quality', rule(@(s) s.snr > 1.5 & s.nspikes > 10), ...
%           'verbose', true);
%
%   See also: RULE (rule.m in utils folder)

% ---------------- Defaults ----------------
verbose       = false;
remove_fields = {};

% ---------------- Parse name-value pairs ----------------
assert(mod(numel(varargin),2)==0, 'Arguments must be name-value pairs');

filters = struct();
for i = 1:2:numel(varargin)
    key = varargin{i};
    val = varargin{i+1};

    switch key
        case 'verbose'
            verbose = logical(val);
        case 'remove_fields'
            remove_fields = val;
        otherwise
            filters.(key) = val;
    end
end

% ---------------- Pre-stats ----------------
num_recordings = numel(sessions);
num_anim = numel(unique({sessions.anim_id}));

if verbose
    if isfield(sessions, 'cell_hash')
        num_cells = numel(unique({sessions.cell_hash}));
        fprintf('Before Curation: %d Unique Cells from %d Sessions and %d Animals\n', ...
        num_cells, num_recordings, num_anim);
    else
        fprintf('Before Curation: %d Sessions and %d Animals\n', ...
        num_recordings, num_anim);
    end
end

% ---------------- Filtering ----------------
keep = true(size(sessions));

filter_names = fieldnames(filters);

for f = 1:numel(filter_names)
    field = filter_names{f};
    value = filters.(field);

    % assert(isfield(sessions, field), ...
    %     'Field "%s" not found in sessions struct', field);
    % --- skipping empty filters
    if isempty(value)
        continue
    end
    if isfield(sessions, field)
        field_data = {sessions.(field)};
    end
    % ---- custom rule object (rule.m)
    if isstruct(value) && isfield(value,'type') && strcmp(value.type,'rule')
        mask = arrayfun(@(s) value.fcn(s), sessions);
    % ---- function handle (single field)
    elseif isa(value, 'function_handle')
        mask = cellfun(@(x) value(x), field_data);

    % ---- numeric
    elseif isnumeric(value) || islogical(value)
        
        if contains(lower(field), 'snr') || contains(lower(field), 'nspikes') || contains(lower(field), 'fr') % most common use case is setting lower bound
            mask = cellfun(@(x) x > value, field_data);
        else
            mask = ismember([sessions.(field)], value);
        end

    % ---- cell array
    elseif iscell(value)
            mask = ismember(field_data, value);

    % ---- string / char
    elseif isstring(value) || ischar(value)
        if contains(lower(field), 'sess_id')
            session_ids = {sessions.session_path};
            % extract session id from session_path using strsplit
            session_ids = cellfun(@(x) strsplit(x, filesep), session_ids, 'UniformOutput', false);
            session_ids = cellfun(@(x) x{end-3}, session_ids, 'UniformOutput', false);
            mask = ismember(session_ids, value);
        else
            mask = strcmp(field_data, value);
        end
    else
        error('Unsupported filter type for field "%s"', field);
    end

    keep = keep & mask;
end

sessions = sessions(keep);

% ---------------- Remove fields ----------------
if ~isempty(remove_fields)
    sessions = rmfield(sessions, ...
        intersect(fieldnames(sessions), remove_fields));
end

% ---------------- Post-stats ----------------
num_recordings = numel(sessions);
num_anim = numel(unique({sessions.anim_id}));
num_sess = numel(unique({sessions.session_path}));
if isfield(sessions, 'cell_hash')
    num_cells = numel(unique({sessions.cell_hash}));
    stats = struct('num_recordings', num_recordings, ...
                   'num_anim', num_anim, ...
                   'num_sess', num_sess, ...
                   'num_cells', num_cells);
    if verbose
        fprintf('After filtering: %d sessions, %d cells, %d animals\n', ...
            stats.num_recordings, ...
            stats.num_cells, ...
            stats.num_anim);
    end
else
    stats = struct('num_recordings', num_recordings, ...
                   'num_anim', num_anim, ...
                   'num_sess', num_sess);
    if verbose
        fprintf('After filtering: %d sessions, %d animals\n', ...
            stats.num_recordings, ...
            stats.num_anim);
    end
end



end
