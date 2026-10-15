function geometry = load_roi_geometry(session_path, movie_size)
%LOAD_ROI_GEOMETRY  ROI polygons and per-cell crop boxes, as ICA_Pre.m builds them.
%
%   geometry = load_roi_geometry(session_path, movie_size)
%
%   session_path  recording folder (holds experimental_parameters.txt; its parent holds Masks.mat)
%   movie_size    size of the movie, [dim1 dim2 ...]
%   geometry      .polygons  {1 x nCell+1} Nx2 [x y] polygons: the cells that have pixels in the
%                            movie, then the corner background box last (the roimask that
%                            ICA_Pre.m passes to subtractRingXtalk)
%                 .crops     [nCell x 1] struct, .rows / .cols: the box ICA_Pre.m cut around the
%                            cell (ROI bounding box + 5 pixels, clipped to the movie), with an odd
%                            last row / column dropped as in ICA_Choose.m. crops(k) is the crop
%                            of IntensOrig column k.
%
% Same polygons and coordinate convention as apply_mask_RMmov_BkgSel_FanLab_withpath.m (pts_list
% from Masks.mat shifted by the camera offsets; x = dim 2, y = dim 1). ROIs with no pixel in the
% movie are dropped, as ICA_Pre.m drops their NaN traces.
cropEdge = 5;        % pixels added around the ROI bounding box in ICA_Pre.m
binFactor = 2;       % crops are trimmed to a multiple of this (ds_factor in ICA_Choose.m)
xOffsetToken = 33;   % positions in experimental_parameters.txt
yOffsetToken = 30;
centerOffset = 288;  % mask clicked on the central quad at 2x2 binning (576 / 2)
cornerBoxX = [1; 30; 30; 1; 1];   % background box, as in apply_mask_RMmov_BkgSel_FanLab_withpath.m
cornerBoxY = [1; 1; 30; 30; 1];

fid = fopen(fullfile(session_path, 'experimental_parameters.txt'));
info = textscan(fid, '%s');
fclose(fid);
xOffset = str2double(info{1}{xOffsetToken}) - centerOffset;
yOffset = str2double(info{1}{yOffsetToken}) - centerOffset;
masksFile = fullfile(fileparts(session_path), 'Masks.mat');
assert(isfile(masksFile), 'Masks.mat not found: %s', masksFile);
ptsList = load(masksFile, 'pts_list').pts_list;

[xGrid, yGrid] = meshgrid(1:movie_size(2), 1:movie_size(1));
polygons = {};
crops = struct('rows', {}, 'cols', {});
for k = 1:numel(ptsList)
    xPoly = ptsList{k}(:, 2) / 2 - xOffset;
    yPoly = ptsList{k}(:, 1) / 2 - yOffset;
    if ~any(inpolygon(xGrid(:), yGrid(:), xPoly, yPoly)), continue; end
    polygons{end+1} = [xPoly, yPoly]; %#ok<AGROW>
    row1 = max(ceil(min(yPoly)) - cropEdge, 1);
    row2 = min(floor(max(yPoly)) + cropEdge, movie_size(1));
    col1 = max(ceil(min(xPoly)) - cropEdge, 1);
    col2 = min(floor(max(xPoly)) + cropEdge, movie_size(2));
    numRows = (row2 - row1 + 1) - mod(row2 - row1 + 1, binFactor);
    numCols = (col2 - col1 + 1) - mod(col2 - col1 + 1, binFactor);
    crops(end+1, 1) = struct('rows', row1:row1 + numRows - 1, 'cols', col1:col1 + numCols - 1); %#ok<AGROW>
end
polygons{end+1} = [cornerBoxX, cornerBoxY];

geometry.polygons = polygons;
geometry.crops = crops;
end
