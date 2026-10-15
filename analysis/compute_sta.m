function sta = compute_sta(trace, spike_idx, spike_w, half_win, asy)
%COMPUTE_STA  Spike-triggered average of the spike-removed, height-normalized trace.
%
%   sta = compute_sta(trace, spike_idx, spike_w, half_win, asy)
%
%   trace      [nFrames x 1] trace for one cell (raw or one model)
%   spike_idx  spike frame indices (sorted; shared across models)
%   spike_w    per-spike widths from THIS trace's inter_spikeT_spikeW.mat
%   half_win   frames either side of each spike (1000)
%   asy        asymmetry used by the interpolation window (3)
%
%   sta        [1 x 2*half_win+1], units of spike height (1 = mean spike peak)
%
% Mirrors prep_norm_and_snr.m + load_voltage.m (spik.sta): spikes are removed
% by linear interpolation over [t-width+asy, t+width], the trace is shifted so
% the spike-removed value at spike times is 0 and scaled so the mean spike
% peak is 1, then snippets around every spike are averaged (NaN-padded at the
% recording edges).
arguments
    trace (:,1) double
    spike_idx (:,1) double
    spike_w (:,1) double
    half_win (1,1) double = 1000
    asy (1,1) double = 3
end

n = numel(trace);
ok = spike_idx >= 1 & spike_idx <= n;
spike_idx = round(spike_idx(ok));
spike_w = spike_w(ok);
ns = numel(spike_idx);
if ns < 1
    sta = nan(1, 2*half_win + 1);
    return
end

% spike removal by local linear interpolation
rm = trace;
for j = 1:ns
    width = round(spike_w(j)) + asy;
    front = spike_idx(j) - width + asy;
    back  = spike_idx(j) + width;
    if isnan(width) || front < 2 || back > n - 1, continue; end
    if j < ns && back >= spike_idx(j+1) - round(spike_w(j+1)/2)
        back = back - 1;                      % don't run into the next spike
    end
    rm(front:back) = interp1([front-1, back+1], [trace(front-1), trace(back+1)], front:back);
end

% normalize: 0 = baseline under the spikes, 1 = mean spike peak
base = mean(rm(spike_idx));
spike_h = max(mean(trace(spike_idx)) - base, eps);
norm_rm = (rm - base) / spike_h;

padded = [nan(half_win, 1); norm_rm; nan(half_win, 1)];
sta = mean(padded(spike_idx + half_win + (-half_win:half_win)), 1, 'omitnan');
end
