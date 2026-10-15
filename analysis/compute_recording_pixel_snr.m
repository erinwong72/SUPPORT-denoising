function [own, rawfp] = compute_recording_pixel_snr(session_path, models, cell_ids, wanted, expected_frames, cfg)
%COMPUTE_RECORDING_PIXEL_SNR  Single-pixel SNR for the cells of one recording, all models.
%
%   [own, rawfp] = compute_recording_pixel_snr(session_path, models, cell_ids, wanted, expected_frames, cfg)
%
%   models           {1 x nModels} 'raw' and/or model dirnames
%   cell_ids         [1 x nCells] cell ids (IntensOrig columns)
%   wanted           logical [nModels x nCells]: which model x cell results to compute
%   expected_frames  [1 x nCells] trace length of each cell (movie frames after skipping must match)
%   cfg              cfg.pixel_skip_frames
%   own, rawfp       {nModels x nCells} compute_pixel_metrics structs ([] where not computed or
%                    failed): footprint of that model's own template / of the raw movie's template
%
% Per model, the movie goes through the same steps as in ICA_Pre.m / ICA_Choose.m ('T' branch) up
% to the point where pixels are collapsed into one trace; the pixels are then used for the
% single-pixel SNR instead (compute_pixel_metrics):
%   1. drop the first cfg.pixel_skip_frames frames, double          (ICA_Pre)
%   2. background subtraction: ring or corner box                   (ICA_Pre, preprocess_roi_movie)
%   3. crop around the cell                                         (ICA_Pre, load_roi_geometry)
%   4. template footprint = crop mean image, min-max normalized, values below 0.4 zeroed;
%      footprint pixels = nonzero                                   (ICA_Choose 'T')
%   5. photobleaching correction of the crop, pblc(vm(crop))        (ICA_Choose applyMask2Movie)
% Not done, because they act on the aggregated trace: weighting by the template, z-scoring,
% high-pass, SLM-off frame filling.
%
% Each footprint is checked against the stored ICAImgs in Masks_BestIcaImgs_template.mat (its
% 2x2 block average must match); a cell that does not match is skipped with a warning.
% The raw footprint comes from the raw movie, which is therefore always processed first.
ensure_preprocessing_paths();
numModels = numel(models);
numCells = numel(cell_ids);
own = cell(numModels, numCells);
rawfp = cell(numModels, numCells);
rawFootprints = cell(1, numCells);   % crop-sized logical, from the raw movie; [] if unavailable

processOrder = [{'raw'}, models(~strcmp(models, 'raw'))];
for po = 1:numel(processOrder)
    model = processOrder{po};
    mi = find(strcmp(models, model), 1);
    if isempty(mi), mi = 0; end
    if mi > 0 && ~any(wanted(mi, :)) && ~strcmp(model, 'raw'), continue; end
    try
        [mov2, geometry] = preprocess_roi_movie(session_path, model, cfg.pixel_skip_frames);
    catch err
        warning('Pixel SNR: cannot preprocess %s / %s: %s', session_path, model, err.message);
        continue;
    end
    for ci = 1:numCells
        isWanted = mi > 0 && wanted(mi, ci);
        if ~isWanted && ~strcmp(model, 'raw'), continue; end
        cellId = cell_ids(ci);
        try
            assert(cellId <= numel(geometry.crops), 'cell_id %d but only %d ROIs in the movie', cellId, numel(geometry.crops));
            crop = mov2(geometry.crops(cellId).rows, geometry.crops(cellId).cols, :);
            weights = template_weights(crop);
            check_against_stored(weights, session_path, model, cellId);
            footprint = weights > 0;
            if strcmp(model, 'raw'), rawFootprints{ci} = footprint; end
            if ~isWanted, continue; end
            assert(size(mov2, 3) == expected_frames(ci), ...
                'movie has %d frames after skipping %d, trace has %d', size(mov2, 3), cfg.pixel_skip_frames, expected_frames(ci));
            bleached = double(pblc(vm(crop)));
            flat = reshape(bleached, [], size(bleached, 3));
            own{mi, ci} = compute_pixel_metrics(flat(footprint(:), :));
            if ~isempty(rawFootprints{ci})
                rawfp{mi, ci} = compute_pixel_metrics(flat(rawFootprints{ci}(:), :));
            end
        catch err
            warning('Pixel SNR failed for %s / cell %d / %s: %s', session_path, cellId, model, err.message);
        end
    end
    clear mov2
end
end

function weights = template_weights(crop)
% template weights of ICA_Choose.m ('T' branch): mean image, min-max normalized, small values zeroed
thresholdFraction = 0.4;
weights = mean(crop, 3);
weights = (weights - min(weights(:))) / (max(weights(:)) - min(weights(:)));
weights(weights < thresholdFraction * max(weights(:))) = 0;
end

function check_against_stored(weights, session_path, model, cell_id)
% the rebuilt weights, block-averaged 2x2 as applyMask2Movie does, must equal the stored ICAImgs
binFactor = 2;
tolerance = 1e-3;   % a differently thresholded pixel changes a block by >= 0.1
if strcmp(model, 'raw'), modelDir = session_path; else, modelDir = fullfile(session_path, model); end
imgsFile = fullfile(modelDir, 'template_mask_results', 'Masks_BestIcaImgs_template.mat');
assert(isfile(imgsFile), 'stored template footprint not found: %s', imgsFile);
stored = load(imgsFile, 'ICAImgs').ICAImgs{cell_id};
[numRows, numCols] = size(weights);
binned = squeeze(mean(mean(reshape(weights, binFactor, numRows / binFactor, binFactor, numCols / binFactor), 1), 3));
assert(isequal(size(binned), size(stored)), ...
    'rebuilt footprint is %dx%d binned, stored one is %dx%d (%s)', size(binned, 1), size(binned, 2), ...
    size(stored, 1), size(stored, 2), imgsFile);
maxDiff = max(abs(binned(:) - stored(:)));
assert(maxDiff < tolerance, ['rebuilt footprint differs from the stored one (max block difference %.3g): ' ...
    'hand-redrawn ROI, or a different movie than the template was built from (%s)'], maxDiff, imgsFile);
end
