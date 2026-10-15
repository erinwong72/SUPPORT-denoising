function [start, action, valid_len] = pick_noise_window(trace, spike_idx, cfg, label, stim_mask, current_start, pick_lens)
%PICK_NOISE_WINDOW  Interactive review/pick of one cell's noise window.
%
%   [start, action, valid_len] = pick_noise_window(trace, spike_idx, cfg, label, ...
%                                                  stim_mask, current_start, pick_lens)
%
% Shows the trace with spike ticks, stim frames shaded, and (if given) the
% current window: dark blue = cfg.noise_len, light blue = cfg.max_len.
%   any key / Enter   accept the current window   -> action 'accept'
%   click             pick a new window start, of the length currently selected
%                     (default: the longest in pick_lens, e.g. 1000 frames);
%                     it must be spike-free for that whole length
%                                                  -> action 'manual'
%   l                 switch the length a NEW window must be valid for, cycling
%                     through pick_lens (e.g. 1000 -> 500 -> 1000). Also works
%                     right after a click, to re-check the same start at the
%                     other length without clicking again.
%   n                 mark the cell as having no signal -> action 'no_signal'
%   s                 skip this cell               -> action 'skip'
%   q                 stop reviewing               -> action 'quit'
% With no current_start you must click.
%
%   pick_lens   selectable lengths for a manual pick, frames. Default
%               [cfg.max_len cfg.noise_len] sorted longest first.
%   valid_len   for action 'manual': the length the picked window was checked
%               spike-free for (the caller stores this as the window's
%               valid_len; a 500-frame pick means the 1000-frame alternative
%               is not computed downstream). For 'accept' it is cfg.max_len,
%               the length the existing window was already validated for.
if nargin < 5 || isempty(stim_mask), stim_mask = false(1, numel(trace)); end
if nargin < 6, current_start = NaN; end
if nargin < 7 || isempty(pick_lens)
    pick_lens = [cfg.max_len, cfg.noise_len];
end
pick_lens = sort(unique(pick_lens(:)'), 'descend');
trace = trace(:);
n = numel(trace);
start = current_start;
action = 'accept';
valid_len = cfg.max_len;
req_ix = 1;                                        % index into pick_lens: length a new window needs

while true
    req_len = pick_lens(req_ix);
    fig = figure('Position', [100 100 1500 600]);
    draw_base(trace, spike_idx, stim_mask);
    draw_window(trace, start, cfg.max_len, cfg.noise_len);
    if isfinite(start)
        title(sprintf('%s | window @%d | any key = accept, click = new %d-frame window%s, n = no signal, s = skip, q = quit', ...
            label, start, req_len, other_len_hint(pick_lens, req_ix)), 'Interpreter', 'none');
    else
        title(sprintf('%s | no window - click a %d-frame window%s, or n = no signal', ...
            label, req_len, other_len_hint(pick_lens, req_ix)), 'Interpreter', 'none');
    end
    set(fig, 'CurrentCharacter', char(0));
    try
        w = waitforbuttonpress;                    % 0 = mouse click, 1 = key
    catch
        action = 'quit'; valid_len = NaN; return   % figure closed by user
    end
    if w == 0                                      % click -> propose a new window
        pt = get(gca, 'CurrentPoint');
        clicked = round(pt(1,1));
        accepted = false;
        while true                                 % re-check the same click at each length
            req_len = pick_lens(req_ix);
            new_start = max(1, min(clicked, n - req_len + 1));
            n_in = sum(spike_idx >= new_start & spike_idx <= new_start + req_len - 1);
            clf(fig); draw_base(trace, spike_idx, stim_mask);
            draw_window(trace, new_start, req_len, cfg.noise_len);
            if n_in > 0
                title(sprintf('%d spikes in the %d-frame window - not allowed.%s Any other key = redo', ...
                    n_in, req_len, l_prompt(pick_lens, req_ix)));
            else
                title(sprintf('%d-frame window OK. Any key = accept,%s r = redo', ...
                    req_len, l_prompt(pick_lens, req_ix)));
            end
            set(fig, 'CurrentCharacter', char(0));
            waitforbuttonpress;
            key = lower(get(fig, 'CurrentCharacter'));
            if ~isempty(key) && key == 'l' && numel(pick_lens) > 1
                req_ix = mod(req_ix, numel(pick_lens)) + 1;        % switch length, re-check
                continue
            end
            if n_in == 0 && ~(~isempty(key) && key == 'r')
                accepted = true;
            end
            break
        end
        close(fig);
        if accepted
            start = new_start; action = 'manual'; valid_len = req_len; return
        end
        continue                                   % redo
    end
    key = lower(get(fig, 'CurrentCharacter'));
    close(fig);
    switch key
        case 'n', action = 'no_signal'; valid_len = NaN; return
        case 's', action = 'skip'; valid_len = NaN; return
        case 'q', action = 'quit'; valid_len = NaN; return
        case 'l'
            if numel(pick_lens) > 1, req_ix = mod(req_ix, numel(pick_lens)) + 1; end   % then redraw
        otherwise
            if isfinite(start), action = 'accept'; return; end   % no window to accept
    end
end
end

function draw_base(trace, spike_idx, stim_mask)
n = numel(trace);
plot(trace, 'r'); hold on;
shade_runs(stim_mask, ylim);
plot(spike_idx, trace(min(max(round(spike_idx), 1), n)), 'kv', 'MarkerSize', 4);
end

function draw_window(trace, start, len_long, len_short)
% light blue = the length the window is checked for, dark blue = the PSNR window inside it
if ~isfinite(start), return; end
long_idx = start : min(start + len_long - 1, numel(trace));
plot(long_idx, trace(long_idx), 'Color', [0.6 0.8 1], 'LineWidth', 1.5);
short_idx = start : min(start + min(len_short, len_long) - 1, numel(trace));
plot(short_idx, trace(short_idx), 'b');
end

function s = other_len_hint(pick_lens, req_ix)
if numel(pick_lens) < 2, s = ''; return; end
s = sprintf(' (l = switch to %d)', pick_lens(mod(req_ix, numel(pick_lens)) + 1));
end

function s = l_prompt(pick_lens, req_ix)
if numel(pick_lens) < 2, s = ''; return; end
s = sprintf(' l = try %d frames,', pick_lens(mod(req_ix, numel(pick_lens)) + 1));
end

function shade_runs(mask, yl)
d = diff([0; mask(:); 0]);
on = find(d == 1); off = find(d == -1) - 1;
for k = 1:numel(on)
    patch([on(k) off(k) off(k) on(k)], [yl(1) yl(1) yl(2) yl(2)], [0.5 0.7 1], ...
        'FaceAlpha', 0.25, 'EdgeColor', 'none');
end
end
