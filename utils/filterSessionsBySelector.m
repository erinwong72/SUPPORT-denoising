function sessions = filterSessionsBySelector(sessions, sel_sessions, invert)
%FILTERSESSIONSBYSELECTOR  Restrict a total_sessions struct array to
% specific animal/day/FOV/cell combinations. Shared by
% dataset_generation_headless.m and preprocessing_headless.m so both filter
% the same way.
%
% sessions = filterSessionsBySelector(sessions, sel_sessions)
% sessions = filterSessionsBySelector(sessions, sel_sessions, invert)
%
%   sessions      struct array with at least anim_id, session_path, FOV,
%                 cell_id fields (as produced by discover_sessions).
%   sel_sessions  cell array of structs, each with any subset of
%                 anim_id/day/slice/FOV/cell_id/session_name; an omitted/empty field matches
%                 any value for that field, and entries are OR'd together.
%                 "day" matches the date folder name in session_path (the
%                 path segment immediately after anim_id). Empty/{} is a
%                 no-op (returns sessions unchanged, regardless of invert).
%   invert        optional, default false. When true, KEEP sessions that do
%                 NOT match sel_sessions instead — e.g. to process
%                 everything except a set already handled elsewhere
%                 (reusing the exact same sel_sessions used there, so you
%                 don't have to hand-write the complement or regenerate any
%                 session-list file).
%
% e.g.
%   {struct('anim_id','cck-ipsp-btsp-w25','day','2026-03-15_VR_V_Blue_inhDSI','FOV',3,'cell_id',2), ...
%    struct('anim_id','cck-ipsp-btsp-w27','day','2026-03-12_VR_V_Blue_inhDSI','FOV',6,'cell_id',1)}

if nargin < 3
    invert = false;
end
if isempty(sel_sessions)
    return
end

sess_days = arrayfun(@(s) session_day(s.session_path, s.anim_id), sessions, 'UniformOutput', false);
keep = false(1, numel(sessions));
for sel_i = 1:numel(sel_sessions)
    sel = sel_sessions{sel_i};
    match = true(1, numel(sessions));
    if isfield(sel, 'anim_id') && ~isempty(sel.anim_id)
        match = match & strcmpi({sessions.anim_id}, sel.anim_id);
    end
    if isfield(sel, 'day') && ~isempty(sel.day)
        match = match & strcmpi(sess_days, sel.day);
    end
    if isfield(sel, 'FOV') && ~isempty(sel.FOV)
        match = match & ismember([sessions.FOV], sel.FOV);
    end
    if isfield(sel, 'slice') && ~isempty(sel.slice)
        match = match & ismember([sessions.slice], sel.slice);
    end
    if isfield(sel, 'session_name') && ~isempty(sel.session_name)
        match = match & strcmpi(string({sessions.session_name}), string(sel.session_name));
    end
    if isfield(sel, 'cell_id') && ~isempty(sel.cell_id)
        match = match & ismember([sessions.cell_id], sel.cell_id);
    end
    keep = keep | match;
end
if invert
    keep = ~keep;
    fprintf('Restricting to %d/%d sessions NOT matching sel_sessions.\n', sum(keep), numel(sessions));
else
    fprintf('Restricting to %d/%d sessions matching sel_sessions.\n', sum(keep), numel(sessions));
end
sessions = sessions(keep);
if isempty(sessions)
    error('sel_sessions (invert=%d) matched no sessions.', invert);
end
end

function day = session_day(session_path, anim_id)
% Returns the date folder name in session_path, i.e. the path segment
% immediately following anim_id (root/anim_id/day/slice.../FOV.../sess_name).
rest = extractAfter(session_path, [filesep anim_id filesep]);
parts = strsplit(rest, filesep);
day = parts{1};
end
