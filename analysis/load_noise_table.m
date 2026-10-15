function noise = load_noise_table(noise_file, cfg)
%LOAD_NOISE_TABLE  Load the per-cell noise-window table, or an empty one.
% Adds columns introduced after the file was first saved (no_signal,
% valid_len, source), so older noise_regions.mat files keep working.
if isfile(noise_file)
    noise = load(noise_file, 'noise').noise;
else
    noise = table('Size', [0 11], ...
        'VariableTypes', {'string','string','double','double','string','string','double','double','logical','double','string'}, ...
        'VariableNames', {'cell_hash','session_path','cell_id','start','status','flag','n_valid','noise_std','no_signal','valid_len','source'});
end
if ~ismember('no_signal', noise.Properties.VariableNames)
    noise.no_signal = false(height(noise), 1);
end
% valid_len: length the window is guaranteed spike/stim-free for; source: trace it was picked on.
% Older rows were all picked on the raw trace at the full length.
if ~ismember('valid_len', noise.Properties.VariableNames)
    if nargin < 2, cfg = load_analysis_config(); end
    noise.valid_len = repmat(cfg.max_len, height(noise), 1);
    noise.valid_len(isnan(noise.start)) = NaN;
    noise.source = repmat("raw", height(noise), 1);
end
end
