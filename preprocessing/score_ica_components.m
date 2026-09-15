function ic_scores = score_ica_components(icsSpace, icsTime, nrowB, ncolB, template)
% SCORE_ICA_COMPONENTS  Heuristic "cell-likeness" score for each ICA component.
%
% ic_scores = score_ica_components(icsSpace, icsTime, nrowB, ncolB, template)
%
% icsSpace : (nrowB*ncolB) x nIcs  spatial filters (as columns, see toimg)
% icsTime  : T x nIcs              time courses (used only for kurtosis)
% nrowB, ncolB : spatial dims for toimg
% template : the mean-projection ROI image (MaskMov{i} averaged over time)
%
% Returns a 1 x nIcs struct array with fields:
%   score          combined score, higher = more cell-like
%   coherence      0-1, fraction of all above-threshold pixels that belong
%                  to the single biggest blob. The main term: a real signal
%                  (ring or filled) lights up as one coherent shape, while
%                  noise/artifact components fragment into many small
%                  scattered speckles, which tanks this.
%   ringScore      0-1 bonus, how much brighter the blob's rim is than its
%                  own center. A filled, high-contrast blob still scores
%                  well overall without this; ringScore just breaks ties in
%                  favor of true membrane rings (dark middle) over filled
%                  disks, since the indicator here is membrane-localized.
%   solidity       area / convex-hull area of the blob with its hole filled
%                  (so a ring's hole doesn't count against outer-shape
%                  compactness — that's ringScore's job)
%   eccentricity   0 = circular, 1 = line-like
%   areaFrac       filled blob area as a fraction of the whole image
%   templateCorr   2D correlation with the ROI template
%   kurt           excess kurtosis of the time course (sparse/spiky = higher)
%   sign           +1 or -1: which polarity of the component was scored best
%
% This is not a trained classifier, just a fast heuristic gate — tune
% AUTO_SCORE_THR / AUTO_MARGIN_THR in ICA_Choose.m against a batch of
% sessions you've already hand-scored before trusting it broadly.

nIcs = size(icsSpace, 2);

template = double(template);
if ~isequal(size(template), [nrowB, ncolB])
    % Match ICA_Pre: drop an odd last row/col, then 2x2 block-average.
    % imresize uses a different kernel and would keep the dropped edge.
    if mod(size(template, 1), 2), template = template(1:end-1, :); end
    if mod(size(template, 2), 2), template = template(:, 1:end-1); end
    [nr, nc] = size(template);
    template = squeeze(mean(mean(reshape(template, 2, nr/2, 2, nc/2), 1), 3));
end
tRange = max(template(:)) - min(template(:));
if tRange > 0
    template = (template - min(template(:))) / tRange;
end

ic_scores = struct('score', {}, 'coherence', {}, 'ringScore', {}, 'solidity', {}, ...
    'eccentricity', {}, 'areaFrac', {}, 'templateCorr', {}, 'kurt', {}, 'sign', {});

for j = 1:nIcs
    img = toimg(icsSpace(:, j), nrowB, ncolB);

    [scorePos, mPos] = evalPolarity(img, template);
    [scoreNeg, mNeg]  = evalPolarity(-img, template);
    if scorePos >= scoreNeg
        sgn = 1; m = mPos; sc = scorePos;
    else
        sgn = -1; m = mNeg; sc = scoreNeg;
    end

    tr = icsTime(:, j);
    k = kurtosis(tr) - 3; % excess kurtosis; spiky/sparse traces score higher
    % Plateaus early (k=10) and only a small weight: a single huge
    % motion-artifact frame can drive kurtosis far higher than any real
    % spiking activity does, so extreme values shouldn't buy extra credit.
    kNorm = min(max(k, 0), 10) / 10;

    ic_scores(j).score        = sc + 0.05 * kNorm;
    ic_scores(j).coherence    = m.Coherence;
    ic_scores(j).ringScore    = m.RingScore;
    ic_scores(j).solidity     = m.Solidity;
    ic_scores(j).eccentricity = m.Eccentricity;
    ic_scores(j).areaFrac     = m.AreaFrac;
    ic_scores(j).templateCorr = m.templateCorr;
    ic_scores(j).kurt         = k;
    ic_scores(j).sign         = sgn;
end
end

function [sc, m] = evalPolarity(img, template)
x = double(img);
x = x - median(x(:));
x(x < 0) = 0; % keep only the bright side of this polarity

emptyOut = struct('Coherence', 0, 'RingScore', 0, 'Solidity', 0, ...
    'Eccentricity', 1, 'AreaFrac', 0, 'templateCorr', 0);

if max(x(:)) <= 0
    sc = 0; m = emptyOut;
    return
end
x = x / max(x(:));

thr = 0.35; % fraction of this polarity's peak intensity -> "signal" pixels
bw = x >= thr;
bw = bwareaopen(bw, 2); % drop single-pixel speckle

cc = bwconncomp(bw);
if cc.NumObjects == 0
    sc = 0; m = emptyOut;
    return
end

props = regionprops(cc, 'Area', 'Centroid');
areas = [props.Area];
totalBrightPixels = sum(areas);
[biggestArea, biggest] = max(areas);
centroid = props(biggest).Centroid; % [x, y] = [col, row]

% Coherence: how much of the signal sits in one blob vs. scattered across
% many small fragments. A real (ring or filled) component lights up as one
% shape; speckled noise fragments into several small blobs and tanks this.
coherence = biggestArea / totalBrightPixels;

blobMask = false(size(bw));
blobMask(cc.PixelIdxList{biggest}) = true;

% Fill the hole before measuring outer-shape compactness, so a ring's dark
% center doesn't itself count against solidity/eccentricity/area.
filledMask = imfill(blobMask, 'holes');
propsFilled = regionprops(filledMask, 'Area', 'Solidity', 'Eccentricity');
[~, fbig] = max([propsFilled.Area]);
Area         = propsFilled(fbig).Area;
Solidity     = propsFilled(fbig).Solidity;
Eccentricity = propsFilled(fbig).Eccentricity;
AreaFrac     = Area / numel(img);

% Ring/membrane bonus: compare the rim's own brightness (the thresholded
% blob pixels) to the brightness right at the blob's centroid. A filled,
% high-contrast blob already scores well through coherence/solidity/
% templateCorr below; this just tips the balance toward true membrane
% rings (dark middle) over filled disks when both are otherwise coherent.
[rr, ccIdx] = ndgrid(1:size(x, 1), 1:size(x, 2));
distFromCentroid = sqrt((rr - centroid(2)).^2 + (ccIdx - centroid(1)).^2);
equivRadius = sqrt(Area / pi);
centerMask = distFromCentroid <= max(0.5, 0.35 * equivRadius);
centerIntensity = mean(x(centerMask));
rimIntensity = mean(x(blobMask));
RingScore = max(0, rimIntensity - centerIntensity) / (rimIntensity + eps);

% A 3-5 pixel speck is trivially "perfectly solid" (Solidity=1) and often
% comes back with Eccentricity exactly 0 — an artifact of ellipse-fitting
% on a handful of pixels, not evidence of being circular. Left unchecked,
% these tiny artifacts out-score real (but not perfectly round) components.
% Discount solidity/eccentricity by how many pixels actually support them;
% templateCorr and coherence aren't gameable the same way, so they're left
% at full weight regardless of blob size.
sizeConfidence = min(1, Area / 8);

sizePenalty = 0;
if Area < 3
    sizePenalty = 0.4; % effectively a single bright pixel — noise speckle
elseif AreaFrac > 0.4
    sizePenalty = 0.5; % diffuse / covers most of the FOV, not soma-shaped
end

if isequal(size(template), size(img))
    templateCorr = max(corr2(x, template), 0);
else
    templateCorr = 0; % size mismatch (e.g. downsampled template) — skip
end

% templateCorr is the one term that checks the component actually sits
% where the cell is — a scattered/misplaced blob can still look "coherent"
% and even ring-shaped by chance, so low template alignment gates the
% other (shape-only) terms down instead of just being one ingredient among
% several; otherwise a component with near-zero template overlap can still
% win purely on tidy geometry.
shapeScore = 0.20 * coherence ...
    + sizeConfidence * (0.15 * Solidity + 0.05 * (1 - min(Eccentricity, 1))) ...
    + 0.20 * RingScore;
locationTrust = 0.3 + 0.7 * templateCorr; % floor of 0.3 so shape still counts a little when template is imperfect
sc = 0.40 * templateCorr + locationTrust * shapeScore - sizePenalty;

m = struct('Coherence', coherence, 'RingScore', RingScore, 'Solidity', Solidity, ...
    'Eccentricity', Eccentricity, 'AreaFrac', AreaFrac, 'templateCorr', templateCorr);
end
