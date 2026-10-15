function [mov2, geometry] = preprocess_roi_movie(session_path, model, skip_frames)
%PREPROCESS_ROI_MOVIE  The movie as ICA_Pre.m has it right before the cell crops are cut.
%
%   [mov2, geometry] = preprocess_roi_movie(session_path, model, skip_frames)
%
%   model        'raw' (movReg.bin) or a model dirname (denoised.tiff), see load_roi_movie
%   skip_frames  leading frames dropped (ICA_Pre.m: nremove = 10 ms)
%   mov2         double [dim1 x dim2 x nFrames], background-subtracted
%   geometry     see load_roi_geometry
%
% Background subtraction as ICA_Pre.m did for this movie, told apart by the figure it saves:
%   RingMaskAndSignal.fig present in the movie's folder -> ring (scattered-light) subtraction,
%       subtractRingXtalk.m (use_ring_bkg = true; the headless default)
%   otherwise -> the corner-box mean trace subtracted from every pixel (use_ring_bkg = false)
% Both subtract one number per frame from the whole frame.
ensure_preprocessing_paths();

mov2 = load_roi_movie(session_path, model, skip_frames);
geometry = load_roi_geometry(session_path, size(mov2));

if strcmp(model, 'raw'), modelDir = session_path; else, modelDir = fullfile(session_path, model); end
useRing = isfile(fullfile(modelDir, 'RingMaskAndSignal.fig'));
if useRing
    mov2 = subtractRingXtalk(mov2, geometry.polygons, [size(mov2, 1), size(mov2, 2)]);
else
    cornerPolygon = geometry.polygons{end};
    [xGrid, yGrid] = meshgrid(1:size(mov2, 2), 1:size(mov2, 1));
    cornerMask = inpolygon(xGrid, yGrid, cornerPolygon(:, 1), cornerPolygon(:, 2));
    flat = reshape(mov2, [], size(mov2, 3));
    cornerTrace = mean(flat(cornerMask(:), :), 1);
    mov2 = mov2 - reshape(cornerTrace, 1, 1, []);
end
end
