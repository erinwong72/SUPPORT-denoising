function [disagreed, reviewLog] = reviewIntensICA(opts)
% REVIEWINTENSICA  Step through Fig_intens_ICA.fig per unique recording and
% sanity-check ICA_Choose results (SUPPORT vs pre-SUPPORT when available).
%
% [disagreed, reviewLog] = reviewIntensICA(opts)
%
% Duplicate session_path rows (multiple cells on the same recording) are
% collapsed so the figure opens once. You then enter which cell mask(s) to
% accept; any affiliated cell not listed is recorded as disagreed.
%
% Required:
%   opts.session_list   struct array with session_path (optional cell_id)
% Optional:
%   opts.use_support, opts.support.dirname, opts.save_dir, opts.start_idx
%
% Keys while reviewing:
%   Enter / y     accept ALL cells for this recording
%   1 3           accept only those cell #s (others disagreed)
%   n             disagree ALL cells
%   s             skip (no mark)
%   q             quit early

assert(isfield(opts, 'session_list') && ~isempty(opts.session_list), ...
    'opts.session_list is required');
assert(isfield(opts.session_list, 'session_path'), ...
    'opts.session_list must have a session_path field');

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
if ~isfield(opts, 'save_dir') || isempty(opts.save_dir)
    out_dir = pwd;
else
    out_dir = opts.save_dir;
end
if ~isfield(opts, 'start_idx') || isempty(opts.start_idx)
    start_idx = 1;
else
    start_idx = opts.start_idx;
end

sel_sessions = opts.session_list;
paths = string({sel_sessions.session_path});
[uniquePaths, ~, pathIdx] = unique(paths, 'stable');
nUnique = numel(uniquePaths);

disagreed = struct('session_path', {}, 'save_dir', {}, 'cells', {}, ...
    'list_idx', {}, 'note', {}, 'timestamp', {});
reviewLog = struct('session_path', {}, 'save_dir', {}, 'all_cells', {}, ...
    'accepted_cells', {}, 'disagreed_cells', {}, 'list_idx', {}, ...
    'note', {}, 'timestamp', {});
missing = {};

fprintf('Reviewing %d unique recording(s) from %d list row(s) (start=%d).\n', ...
    nUnique, numel(sel_sessions), start_idx);
fprintf('  Enter/y = accept all   ''1 3'' = accept those cells   n = none   s = skip   q = quit\n\n');

for u = start_idx:nUnique
    session_path = char(uniquePaths(u));
    members = find(pathIdx == u);
    if opts.use_support
        save_dir = fullfile(session_path, support_dirname);
    else
        save_dir = session_path;
    end

    all_cells = affiliatedCells(sel_sessions, members, save_dir);
    support_fig = fullfile(save_dir, 'Fig_intens_ICA.fig');
    raw_fig = fullfile(session_path, 'Fig_intens_ICA.fig');

    fprintf('=== %d/%d  (%d list row(s))  %s ===\n', u, nUnique, numel(members), session_path);
    fprintf('  cells: %s\n', mat2str(all_cells));

    if ~isfile(support_fig)
        fprintf('  MISSING: %s\n', support_fig);
        missing{end+1} = session_path; %#ok<AGROW>
        continue
    end

    % Open native .figs full-screen halves so scaling stays readable
    figs = gobjects(0);
    if opts.use_support && isfile(raw_fig)
        hRaw = openfig(raw_fig, 'new', 'visible');
        set(hRaw, 'Units', 'normalized', 'Position', [0.0 0.05 0.5 0.9], ...
            'Name', sprintf('pre-SUPPORT %d/%d', u, nUnique), 'NumberTitle', 'off');
        figs(end+1) = hRaw; %#ok<AGROW>
        hSup = openfig(support_fig, 'new', 'visible');
        set(hSup, 'Units', 'normalized', 'Position', [0.5 0.05 0.5 0.9], ...
            'Name', sprintf('SUPPORT (%s) %d/%d', support_dirname, u, nUnique), ...
            'NumberTitle', 'off');
        figs(end+1) = hSup; %#ok<AGROW>
    else
        if opts.use_support && ~isfile(raw_fig)
            fprintf('  (no pre-SUPPORT fig — opening SUPPORT only)\n');
        end
        hSup = openfig(support_fig, 'new', 'visible');
        set(hSup, 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.9], ...
            'Name', sprintf('Fig_intens_ICA %d/%d', u, nUnique), 'NumberTitle', 'off');
        figs(end+1) = hSup; %#ok<AGROW>
    end
    drawnow;

    prompt = sprintf('  Accept which cell mask(s)? [Enter=all %s / n=none / s / q]: ', mat2str(all_cells));
    ansStr = strtrim(input(prompt, 's'));
    close(figs(isgraphics(figs)));

    note = '';
    if isempty(ansStr) || strcmpi(ansStr, 'y')
        accepted = all_cells;
        bad = [];
        fprintf('  accepted all: %s\n', mat2str(accepted));
    elseif strcmpi(ansStr, 'n')
        accepted = [];
        bad = all_cells;
        note = strtrim(input('  Optional note (Enter to skip): ', 's'));
        fprintf('  disagreed all: %s\n', mat2str(bad));
    elseif strcmpi(ansStr, 's')
        fprintf('  skipped\n');
        continue
    elseif strcmpi(ansStr, 'q')
        fprintf('  quit at recording %d/%d\n', u, nUnique);
        break
    else
        accepted = str2num(ansStr); %#ok<ST2NM>
        if isempty(accepted)
            fprintf('  unrecognized input — skipped\n');
            continue
        end
        accepted = intersect(accepted(:)', all_cells, 'stable');
        bad = setdiff(all_cells, accepted, 'stable');
        if ~isempty(bad)
            note = strtrim(input('  Optional note for disagreed cells (Enter to skip): ', 's'));
        end
        fprintf('  accepted %s | disagreed %s\n', mat2str(accepted), mat2str(bad));
    end

    reviewLog(end+1) = struct( ... %#ok<AGROW>
        'session_path', session_path, ...
        'save_dir', save_dir, ...
        'all_cells', all_cells, ...
        'accepted_cells', accepted, ...
        'disagreed_cells', bad, ...
        'list_idx', members, ...
        'note', note, ...
        'timestamp', datetime('now'));

    if ~isempty(bad)
        disagreed(end+1) = struct( ... %#ok<AGROW>
            'session_path', session_path, ...
            'save_dir', save_dir, ...
            'cells', bad, ...
            'list_idx', members, ...
            'note', note, ...
            'timestamp', datetime('now'));
        fprintf('  marked DISAGREED cells %s (%d recordings so far)\n', ...
            mat2str(bad), numel(disagreed));
    end
end

out_file = fullfile(out_dir, 'ICA_Review_Disagreed.mat');
save(out_file, 'disagreed', 'reviewLog', 'missing', 'opts');
fprintf('\nDone. %d recording(s) with disagreed cells, %d missing figs.\nSaved: %s\n', ...
    numel(disagreed), numel(missing), out_file);
if ~isempty(disagreed)
    disp(struct2table(disagreed));
end
end

function cells = affiliatedCells(sel_sessions, members, save_dir)
% Prefer cell_id from the session list; else 1:nCell from ICA results.
cells = [];
if isfield(sel_sessions, 'cell_id')
    cells = [sel_sessions(members).cell_id];
    cells = unique(cells(:)', 'stable');
end
if isempty(cells)
    pre = fullfile(save_dir, 'ICA_PreResults.mat');
    if isfile(pre)
        s = load(pre, 'nCell');
        if isfield(s, 'nCell')
            cells = 1:s.nCell;
            return
        end
    end
    cells = 1; % fallback
end
end
