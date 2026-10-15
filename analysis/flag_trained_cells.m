function trained = flag_trained_cells(tbl, cfg, root_path)
%FLAG_TRAINED_CELLS  Which rows of a cell x model table were in a model's training data.
%
%   trained = flag_trained_cells(tbl, cfg, root_path)
%
%   tbl   table with session_path, cell_id and model (e.g. metrics, one row per cell x model)
%   cfg   cfg.training_windows: N x 2 cell, {model_dirname, selected_windows_csv}; the model
%         name '*' applies the csv to every model. Empty / missing = nothing flagged.
%         The csv is the dataset's window_selection/selected_windows.csv; a cell counts as
%         trained-on when it has at least one row there (columns session_path, cell_id).
%   trained  logical column; raw rows and models without an entry are false.
%
% Cells are matched on session_path (mapped to this machine's fanlab root) + cell_id.
trained = false(height(tbl), 1);
if ~isfield(cfg, 'training_windows') || isempty(cfg.training_windows) || isempty(tbl), return; end
tw = cfg.training_windows;
keys = local_key(tbl.session_path, tbl.cell_id, root_path);
for i = 1:size(tw, 1)
    csv_file = to_local_path(char(tw{i, 2}), root_path);
    if ~isfile(csv_file), csv_file = fullfile(root_path, 'Labmembers', 'Erin', 'code', csv_file); end   % relative to the code folder
    assert(isfile(csv_file), 'training_windows csv not found: %s', csv_file);
    w = readtable(csv_file, 'TextType', 'string');
    train_keys = unique(local_key(w.session_path, w.cell_id, root_path));
    in_set = ismember(keys, train_keys);
    if ~strcmp(tw{i, 1}, '*') && ~any(tbl.model == string(tw{i, 1}))
        warning('training_windows: model "%s" is not in the table (models: %s) - nothing flagged for it.', ...
            tw{i, 1}, strjoin(unique(tbl.model(tbl.model ~= "raw"))', ', '));
    end
    if strcmp(tw{i, 1}, '*')
        sel = tbl.model ~= "raw";
    else
        sel = tbl.model == string(tw{i, 1});
    end
    trained = trained | (sel & in_set);
    fprintf('training_windows: %s -> %d trained cells in the csv, %d of them found in this analysis (%s)\n', ...
        tw{i, 1}, numel(train_keys), numel(intersect(train_keys, keys)), csv_file);
end
end

function k = local_key(session_path, cell_id, root_path)
sp = string(session_path(:));
for j = 1:numel(sp), sp(j) = string(to_local_path(char(sp(j)), root_path)); end
k = sp + "|" + string(cell_id(:));
end
