function ringMask = generateRingMaskFromROI(roimask, imgSize, ringWidth, gap)
% generateRingMaskFromROI: generate a ring mask at a distance from multiple ROI polygons
%
% Inputs:
%   roimask   - cell array of polygons, each is Nx2 array of [x, y] coordinates
%   imgSize   - [height, width] of the image
%   ringWidth - width (in pixels) of the ring
%   gap       - number of pixels to separate ring from ROI
%
% Output:
%   ringMask  - binary image mask with the ring regions set to 1

    combinedMask = false(imgSize);  % initialize empty mask
    
    for i = 1:numel(roimask)
        polygon = roimask{i};
        if ~isempty(polygon)
            mask = poly2mask(polygon(:,1), polygon(:,2), imgSize(1), imgSize(2));
            combinedMask = combinedMask | mask;
        end
    end

    % Step 1: Dilate with (gap + ringWidth)
    se_outer = strel('disk', gap + ringWidth);
    dilated_outer = imdilate(combinedMask, se_outer);

    % Step 2: Dilate with (gap) only
    se_inner = strel('disk', gap);
    dilated_inner = imdilate(combinedMask, se_inner);

    % Step 3: Ring = outer minus inner
    ringMask = dilated_outer & ~dilated_inner;
end
