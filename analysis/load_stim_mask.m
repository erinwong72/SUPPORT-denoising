function [mask, had_data] = load_stim_mask(session_path, n_frames, cfg)
%LOAD_STIM_MASK  Logical [1 x n_frames], true on stimulated / blue-light frames.
%
% Same recipe as dataset_generation.m: get_stim_protocol(session_path,
% is_btsp, 1) returns the AO trace downsampled to the 1 kHz frame rate, and
% frames above cfg.stim_thresh count as stimulated. Sessions with no
% 'matlab wvfm' data are treated as unstimulated (had_data = false) so the
% caller can flag them.
mask = false(1, n_frames);
had_data = false;
is_btsp = any(contains(session_path, cfg.btsp_roots));
try
    sp = get_stim_protocol(session_path, is_btsp, 1);
    t = sp.trace;
    k = min(numel(t), n_frames);
    mask(1:k) = t(1:k) > cfg.stim_thresh;
    had_data = true;
catch ME
    warning('No stim protocol for %s (%s); treating as unstimulated.', session_path, ME.message);
end
end
