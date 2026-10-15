function tr = load_model_trace(session_path, model, use_template, cell_id)
%LOAD_MODEL_TRACE  IntensOrig for one cell. model = 'raw' reads the session
% root; anything else reads <session_path>/<model>.
if strcmp(model, 'raw'), d = session_path; else, d = fullfile(session_path, model); end
if use_template
    f = fullfile(d, 'template_mask_results', 'Masks_BestIcaTrace_template.mat');
else
    f = fullfile(d, 'Masks_BestIcaTrace.mat');
end
assert(isfile(f), 'trace file not found: %s', f);
tr = load(f, 'IntensOrig').IntensOrig;
if nargin > 3 && ~isempty(cell_id), tr = tr(:, cell_id); end
end
