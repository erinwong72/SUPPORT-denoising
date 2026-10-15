function [mov2, ringSignal, ringMask] = subtractRingXtalk(mov, roimask, imgSize, varargin)
%SUBTRACTRINGXTALK  Remove scattered-light crosstalk via a ring around cell ROIs.
%
% Ring mean intensity per frame is subtracted from every pixel (same approach
% as Run_xtalk_PCA_ICA_RMmov_FanLab_function_automask.m / Manual_xtalk_*).
%
% Inputs:
%   mov       - [H x W x T] movie (already cropped of leading nremove frames)
%   roimask   - cell array of ROI polygons; last entry is typically the
%               corner background ROI and is excluded
%   imgSize   - [H W] matching size(mov,1:2), usually [ncol, nrow]
%
% Name-value (optional):
%   ringWidth - default 3
%   gap       - default 4
%   save_dir  - if non-empty, save RingMaskAndSignal.fig there
%
% Outputs:
%   mov2       - crosstalk-subtracted movie
%   ringSignal - [T x 1] mean ring intensity per frame
%   ringMask   - binary ring mask

p = inputParser;
addParameter(p, 'ringWidth', 3, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'gap', 4, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'save_dir', '', @(x) ischar(x) || isstring(x) || isempty(x));
parse(p, varargin{:});
ringWidth = p.Results.ringWidth;
gap       = p.Results.gap;
save_dir  = char(p.Results.save_dir);

nframes = size(mov, 3);
% Exclude last ROI (background clicky box)
cell_rois = roimask(1:end-1);
ringMask  = generateRingMaskFromROI(cell_rois, imgSize, ringWidth, gap);

mov2       = zeros(size(mov), 'like', mov);
ringSignal = zeros(nframes, 1);
for t0 = 1:nframes
    frame = mov(:,:,t0);
    ringSignal(t0) = mean(frame(ringMask));
    mov2(:,:,t0)   = frame - ringSignal(t0);
end

if ~isempty(save_dir)
    figure;
    subplot(1,2,1); imshow(ringMask); title('Ring Mask');
    subplot(1,2,2); plot(1:nframes, ringSignal);
    xlabel('Frame'); ylabel('Mean Ring Intensity');
    title('Ring Signal Over Time');
    saveas(gcf, fullfile(save_dir, 'RingMaskAndSignal.fig'));
end
end
