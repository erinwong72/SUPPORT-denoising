function [start, info] = auto_noise_window(trace, spike_idx, stim_mask, cfg)
%AUTO_NOISE_WINDOW  Choose a representative noise window without user input.
%
%   [start, info] = auto_noise_window(trace, spike_idx, stim_mask, cfg)
%
% Candidates start every cfg.step frames and span cfg.max_len frames (the
% longest length in use, so cfg.noise_len sits inside it and every alt
% length is valid too). A candidate is dropped if it comes within
% cfg.spike_margin of a spike or cfg.stim_margin of a stim/blue-light frame.
%
% Among the survivors:
%   1. keep the half with the least linear drift (|slope*max_len| relative
%      to the detrended std), so slow bleaching/wander doesn't set the noise;
%   2. pick the candidate whose std over the first cfg.noise_len frames is
%      closest to the median of those, i.e. a TYPICAL window, not the quietest
%      one (min-std would cherry-pick and inflate every PSNR).
%
%   3. (optional, off unless cfg.flat_keep_frac < 1) before step 2, keep only
%      the flattest cfg.flat_keep_frac of the low-drift windows -- those whose
%      std is closest to the frame-to-frame noise level, i.e. no slow
%      dips/bumps. info.flat_ratio reports the chosen window's value.
%
% start is NaN if no window survives. info.flag is a ';'-joined string of
% reasons to review this cell by eye ("" = nothing suspicious).
trace = trace(:);
n = numel(trace);
flags = strings(0);

bad = false(n, 1);
bad(round(spike_idx(spike_idx >= 1 & spike_idx <= n))) = true;
bad = conv(double(bad), ones(2*cfg.spike_margin + 1, 1), 'same') > 0;
sb = false(n, 1);
k = min(n, numel(stim_mask));
sb(1:k) = stim_mask(1:k);
bad = bad | conv(double(sb), ones(2*cfg.stim_margin + 1, 1), 'same') > 0;

cum = [0; cumsum(bad)];
starts = (1:cfg.step:n - cfg.max_len + 1)';
starts = starts(cum(starts + cfg.max_len) - cum(starts) == 0);

info = struct('n_valid', numel(starts), 'flag', "", 'noise_std', NaN, 'drift_ratio', NaN);
if isempty(starts)
    start = NaN;
    info.flag = "no_valid_window";
    return
end
if numel(starts) < cfg.min_windows, flags(end+1) = "few_windows"; end

x = (1:cfg.max_len)';
drift = zeros(size(starts));
s_len = zeros(size(starts));
flat = zeros(size(starts));
for j = 1:numel(starts)
    w = trace(starts(j) : starts(j) + cfg.max_len - 1);
    p = polyfit(x, w, 1);
    drift(j) = abs(p(1)) * cfg.max_len / max(std(w - polyval(p, x)), eps);
    wn = w(1:cfg.noise_len);
    s_len(j) = std(wn);
    % flatness: total std over a frame-to-frame noise estimate, std(diff)/sqrt(2).
    % ~1 for white noise, >1 when slow dips/bumps add variance on top.
    flat(j) = s_len(j) / max(std(diff(wn)) / sqrt(2), eps);
end
keep = drift <= median(drift);
starts = starts(keep); drift = drift(keep); s_len = s_len(keep); flat = flat(keep);

% Optional (cfg.flat_keep_frac < 1): of the low-drift windows, keep only the
% flattest fraction, so the noise std isn't set by slow dips/bumps that
% polyfit's linear drift doesn't catch. Still median-std afterwards (not
% min-std), so it stays a typical window among the clean ones.
if isfield(cfg, 'flat_keep_frac') && cfg.flat_keep_frac < 1
    n_keep = max(1, ceil(cfg.flat_keep_frac * numel(starts)));
    [~, order] = sort(flat, 'ascend');
    keep = sort(order(1:n_keep));
    starts = starts(keep); drift = drift(keep); s_len = s_len(keep); flat = flat(keep);
end

[~, j] = min(abs(s_len - median(s_len)));
start = starts(j);
info.noise_std = s_len(j);
info.drift_ratio = drift(j);
info.flat_ratio = flat(j);
info.flag = strjoin(flags, ';');
end
