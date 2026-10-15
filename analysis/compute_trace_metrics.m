function m = compute_trace_metrics(trace, spike_idx, noise_start, opts)
%COMPUTE_TRACE_METRICS  Per-trace metrics for one cell of one recording.
%
%   m = compute_trace_metrics(trace, spike_idx, noise_start, opts)
%
%   trace        [nFrames x 1] denoised or raw trace for one cell
%   spike_idx    spike frame indices (shared across models)
%   noise_start  first frame of the spike-free noise window (shared across models)
%   opts         .snippet_len  half-width of spike snippets, frames (500)
%                .noise_len    length of noise window, frames (500)
%                .alt_noise_lens  other window lengths for a sensitivity
%                              check, e.g. [300 1000]; same start frame
%                .valid_len    length the noise window was validated spike/stim-free
%                              for (alt lengths beyond it are NaN); optional
%                .baseline_win unused now (was the movmedian window); only the disabled
%                              paper SNR would have used it
%
% NO baseline correction: the noise window and spike snippets are cut from the trace
% as given (slow / subthreshold dynamics kept, no constant subtracted), identically
% for raw and every model.
%
% Outputs
%   m.psnr_db      20*log10(peak of mean spike waveform / std of noise window),
%                  both cut from the trace as given (no detrending)
%   m.psnr_db_bc   identical to psnr_db (baseline correction is now always on);
%                  kept so existing tables/plots keep working
%   m.psnr_alt     same PSNR for each opts.alt_noise_lens; NaN when that
%                  window runs off the trace or contains a spike
%   m.snr_paper_db DISABLED (see below) - left as NaN. Was 10*log10(max(bc)/std(bc))
%                  on the movmean(baseline_win)-corrected trace (Eom et al.
%                  2023 no-ground-truth SNR). Superseded by psnr_db.
%   m.spike_height, m.noise_std, m.waveform, m.n_valid_spikes
arguments
    trace (:,1) double
    spike_idx (:,1) double
    noise_start (1,1) double
    opts struct
end

L = opts.snippet_len;
n = numel(trace);

% no baseline correction (see header); everything below is cut from x
x = trace;

% noise window
noise_idx = noise_start : min(noise_start + opts.noise_len - 1, n);
m.noise_std = std(x(noise_idx));
m.noise_std_bc = m.noise_std;

% average spike waveform; NaN when the cell has no usable spikes
valid = spike_idx(spike_idx > L & spike_idx < n - L);
m.n_valid_spikes = numel(valid);
% reshape: with exactly one spike, x(row index) comes back as a column and
% mean(...,1) would collapse it to a scalar
m.waveform = mean(reshape(x(valid(:) + (-L:L)), numel(valid), 2*L + 1), 1);
m.spike_height = max(m.waveform);
m.psnr_db = 20 * log10(m.spike_height / m.noise_std);
m.psnr_db_bc = m.psnr_db;

% sensitivity to window length (same start frame)
m.psnr_alt = nan(1, numel(opts.alt_noise_lens));
for a = 1:numel(opts.alt_noise_lens)
    last = noise_start + opts.alt_noise_lens(a) - 1;
    if isfield(opts, 'valid_len') && opts.alt_noise_lens(a) > opts.valid_len, continue; end   % not validated stim-free
    if last > n || any(spike_idx >= noise_start & spike_idx <= last), continue; end
    m.psnr_alt(a) = 20 * log10(m.spike_height / std(x(noise_start:last)));
end

% paper-style SNR (Eom et al. 2023) - disabled, using psnr_db instead. Column
% kept (as NaN) so old code/tables that still read snr_paper_db don't break.
% bc = trace - movmean(trace, opts.baseline_win);
% m.snr_paper_db = 10 * log10(max(bc) / std(bc));
m.snr_paper_db = NaN;
end
