function [sp, sw, dt] = load_spikes(session_path, model, use_template, cell_id)
%LOAD_SPIKES  Spike frame indices and widths for one cell. 'raw' always reads the
% curated spike file at the session root (<session_path>/inter_spikeT_spikeW.mat),
% even in template mode: that is the file the models' spike times are copied from
% (applyRawSpikesToDenoised.m), so raw and models always share the same spikes.
% A model reads <session_path>/<model>[/template_mask_results] (spike times are
% the raw ones, widths there are recomputed on the model's own trace).
if strcmp(model, 'raw')
    d = session_path;
else
    d = fullfile(session_path, model);
    if use_template, d = fullfile(d, 'template_mask_results'); end
end
f = fullfile(d, 'inter_spikeT_spikeW.mat');
assert(isfile(f), 'spike file not found: %s', f);
S = load(f, 'C', 'dt');
sp = unwrap_vector(S.C(cell_id).spikeT);
sw = unwrap_vector(S.C(cell_id).spikeW);
dt = S.dt;
end

function v = unwrap_vector(x)
% spikeT / spikeW are saved as {vector} (1x1 cell; {[]} when a cell has no
% spikes). Return a plain double column either way.
if iscell(x)
    if isempty(x), x = []; else, x = x{1}; end
end
v = double(x(:));
end
