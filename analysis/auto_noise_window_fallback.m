function [start, info] = auto_noise_window_fallback(get_trace, spike_idx, stim_mask, cfg)
%AUTO_NOISE_WINDOW_FALLBACK  auto_noise_window with fallbacks when nothing is valid.
%
%   [start, info] = auto_noise_window_fallback(get_trace, spike_idx, stim_mask, cfg)
%
%   get_trace   @(source) trace for 'raw' or one of cfg.models (loaded lazily)
%
% Order: at the full required length (cfg.max_len) try the raw trace, then, if
% cfg.fallback_to_cleaned, each cleaned (SUPPORT) trace. If none has a valid window,
% shorten the required length (cfg.noise_len, then down by cfg.shorten_step to
% cfg.min_noise_len) and repeat raw -> cleaned at each length.
%
% NOTE: whether a candidate is valid depends only on the spike times and the stim
% mask (both shared by every trace), so the cleaned-trace attempt can only change
% WHICH valid window is chosen, never whether one exists. In practice the
% shortening is what rescues cells.
%
% info (from auto_noise_window) plus
%   info.valid_len  length the window is guaranteed spike- and stim-free for
%   info.len        noise-window length to use for the metrics (min(cfg.noise_len, valid_len))
%   info.source     trace the window was picked on ("raw" or a model)
% info.flag gains "short_window" (len < cfg.noise_len) and "picked_on_<model>".
lens = [cfg.max_len, cfg.noise_len:-cfg.shorten_step:cfg.min_noise_len, cfg.min_noise_len];
lens = unique(lens(lens >= cfg.min_noise_len), 'stable');
sources = {'raw'};
if cfg.fallback_to_cleaned, sources = [sources, cfg.models]; end
traces = cell(1, numel(sources)); loaded = false(1, numel(sources));

start = NaN;
info = struct('n_valid', 0, 'flag', "no_valid_window", 'noise_std', NaN, 'drift_ratio', NaN, ...
    'valid_len', NaN, 'len', NaN, 'source', "");
for L = lens
    c = cfg; c.max_len = L; c.noise_len = min(cfg.noise_len, L);
    for s = 1:numel(sources)
        if ~loaded(s)
            loaded(s) = true;
            try, traces{s} = get_trace(sources{s}); catch, traces{s} = []; end
        end
        if isempty(traces{s}), continue; end
        [st, inf_] = auto_noise_window(traces{s}, spike_idx, stim_mask, c);
        if isnan(st), continue; end
        start = st; info = inf_;
        info.valid_len = L; info.len = c.noise_len; info.source = string(sources{s});
        flags = string(info.flag); flags = flags(strlength(flags) > 0);
        if c.noise_len < cfg.noise_len, flags(end+1) = "short_window"; end %#ok<AGROW>
        if s > 1, flags(end+1) = "picked_on_" + string(sources{s}); end %#ok<AGROW>
        info.flag = strjoin(flags, ';');
        return
    end
end
end
