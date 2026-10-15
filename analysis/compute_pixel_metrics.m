function m = compute_pixel_metrics(pixels)
%COMPUTE_PIXEL_METRICS  Single-pixel SNR over the pixels of one cell's footprint.
%
%   m = compute_pixel_metrics(pixels)
%
%   pixels   [nPixels x nFrames] footprint pixel traces of one model's movie (or raw)
%
% The no-ground-truth SNR from the Eom et al. 2023 Methods (Performance metrics), taken
% literally per pixel:  SNR(x) = 10*log10( max(x) / std(x) ), over the whole trace.
% Averaged over the footprint pixels (they report the average single-pixel SNR, Fig. 3d).
% NO baseline correction, detrending or sign flip: traces are used as given, like
% compute_trace_metrics. The paper applies this after baseline correction, so here max(x) is
% the trace maximum including any DC offset, and the values are only comparable between
% models of the same recording, not with the paper's dB.
%
% Outputs
%   m.n_roi_pixels    pixels in the footprint
%   m.snr_db          mean over pixels of the single-pixel SNR, dB (the headline number)
%   m.snr_db_median   median over pixels
%   m.n_nonpositive   pixels with max(x) <= 0 (SNR undefined; left out of the mean and median)
%   m.snr_per_pixel   [nPixels x 1]
arguments
    pixels (:,:) double
end

numPixels = size(pixels, 1);
traceMax = max(pixels, [], 2);
traceStd = std(pixels, 0, 2);
isDefined = traceMax > 0 & traceStd > 0;

snrPerPixel = nan(numPixels, 1);
snrPerPixel(isDefined) = 10 * log10(traceMax(isDefined) ./ traceStd(isDefined));

m.n_roi_pixels = numPixels;
m.snr_db = mean(snrPerPixel, 'omitnan');
m.snr_db_median = median(snrPerPixel, 'omitnan');
m.n_nonpositive = nnz(~isDefined);
m.snr_per_pixel = snrPerPixel;
end
