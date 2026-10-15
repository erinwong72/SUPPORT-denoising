function review_firing_rate_windows(sel_dir, nv)
%REVIEW_FIRING_RATE_WINDOWS  Step 2 of manual window selection: step through
% the ranked windows from rank_firing_rate_windows.m, one recording at a
% time, and accept/reject each window by eye.
%
%   review_firing_rate_windows()                  % looks in ./window_selection
%   review_firing_rate_windows('<...>/<save_str>/window_selection')
%   review_firing_rate_windows(sel_dir, order='rate')   % window by window, highest FR first
%   review_firing_rate_windows(sel_dir, only='stim_overlap')  % only recordings with a window overlapping stim
%
% only='stim_overlap': before opening the figure, checks every non-rejected
% (accepted or undecided) window against its recording's stim protocol and
% shows ONLY the recordings (or, with order='rate', the windows) that overlap
% stim, with the first overlapping window already focused so you can shift it
% with the keys below (or press f to cycle focus, or toggle it to reject it).
% Decisions, shifts and manual windows still save to the same
% window_selection.mat. The second (manual) pass is not triggered in this mode.
%
% order='recording' (default): step through one recording at a time, in order
% of each recording's best-ranked window, with all of that recording's
% candidate windows shown on its trace (keys 1-9 pick which).
% order='rate': step through single windows in global rank order -- highest
% window firing rate first, regardless of recording. Each screen shows that
% window's recording trace with only that window highlighted (zoom below), so
% keys 1/click toggle it, and a/x accept/reject it. The recording's trace is
% only reloaded when consecutive windows come from different recordings.
%
% In 'recording' mode: the top plot is
% the whole raw trace (spikes in red, stim in light red) with every candidate
% window from that recording highlighted and labelled with its global rank
% and rate (the recording's whole-trace average is in the title). The bottom
% plot zooms into the focused window.
%
% Window colours: blue = undecided, green = accepted, red = rejected.
% Black outline = the focused window shown in the zoom plot.
%
% Second pass (manual windows): once you step past the last recording with
% nothing left undecided and still have fewer accepted windows than needed (or
% reopen a finished review that is still short, or press p at any time), the
% recordings are shown again, ordered by their average firing rate OUTSIDE the
% windows already considered (accepted or rejected; whole-recording spike count
% and frames minus those windows), highest first. Press n to add a new window
% to the recording: it is placed at the highest-spike spot that doesn't overlap
% an existing window (or stim, when stim_mode is window_avoid) and starts out
% accepted -- then fix its position with the shift keys below. Each recording
% can hold at most max_windows_per_recording (default 4) non-rejected windows
% including manual ones; recordings already at the cap are skipped. Manual
% windows are marked `manual` in the saved candidates and survive re-opening.
%
% Keys:
%   1-9            toggle window k of this recording (accept <-> reject) and focus it
%   click a window same, with the mouse
%   , / .          shift the focused window left / right by shift_step frames
%   < / >          shift it by 10x shift_step (shift+, / shift+.)
%   f              cycle focus to the next window of this recording (no accept/reject toggle)
%   m              type an exact start frame for the focused window
%   r              reset the focused window to its original position
%   n              (second pass) add a new manual window to this recording
%   p              enter the second pass now
%   a / x          accept all / reject all windows in this recording
%   right / space  next recording          left   previous recording
%   j              jump to the next recording with undecided windows
%   s              save (also autosaves after every decision)
%   q              save and quit (closing the figure also saves)
% Shifting recomputes the window's spike count and firing rate, keeps its
% accept/reject status, and warns in the zoom title if the new position
% overlaps stim or another non-rejected window of the same recording. The
% window's original position is kept in candidates.orig_start; shifted
% positions are saved in `start`, which is what the generation step uses.
% The title tracks accepted vs. the number needed
% (floor(target_frames/window_len)). Rejected windows are simply skipped, so
% keep going down the ranking until the target is reached.
%
% psnr_cutoff=17 (optional): every time you save (s / q / closing the figure)
% also write datasets/<cell_type>/total_sessions_psnr17_training.mat -- the
% final session list for training (see write_training_sessions.m). It can also
% be run on its own afterwards: write_training_sessions('BTSP', 17).
%
% Decisions are autosaved to window_selection.mat in sel_dir (candidates with
% their status, plus `selected_windows` = accepted rows) and a
% selected_windows.csv. Re-running resumes from the saved decisions. Pass
% window_selection.mat to dataset_generation_headless via
% window_selection_file to generate the dataset.
arguments
    sel_dir {mustBeTextScalar} = 'window_selection'
    nv.order {mustBeMember(nv.order, {'recording', 'rate'})} = 'recording'
    nv.shift_step (1,1) double {mustBeNonnegative} = 0
    nv.max_windows_per_recording (1,1) double {mustBePositive, mustBeInteger} = 4
    nv.only {mustBeMember(nv.only, {'all', 'stim_overlap'})} = 'all'
    nv.psnr_cutoff (1,1) double = NaN
end
only_stim = strcmp(nv.only, 'stim_overlap');
by_rate = strcmp(nv.order, 'rate');
sel_dir = char(sel_dir);
if isfile(sel_dir); sel_dir = fileparts(sel_dir); end
cand_file = fullfile(sel_dir, 'window_candidates.mat');
state_file = fullfile(sel_dir, 'window_selection.mat');
assert(isfile(cand_file), 'window_candidates.mat not found in %s (run rank_firing_rate_windows first)', sel_dir);

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'analysis'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing')); % get_stim_protocol

L = load(cand_file, 'candidates', 'params');
params = L.params;
candidates = convert_struct_paths(L.candidates, root_path);
[candidates.orig_start] = candidates.start; % ranked position; `start` may be shifted by hand
[candidates.manual] = deal(false);          % true for windows added in the second pass
n_ranked = numel(candidates);
shift_step = nv.shift_step;
if shift_step == 0
    shift_step = max(1, round(params.window_len / 20));
end
if isfile(state_file)
    R = load(state_file, 'candidates');
    r_orig = [R.candidates.start];
    if isfield(R.candidates, 'orig_start'); r_orig = [R.candidates.orig_start]; end
    % rows beyond the ranked list are manual windows appended in an earlier session
    same = numel(R.candidates) >= n_ranked && ...
        isequal(r_orig(1:n_ranked), [candidates.orig_start]) && ...
        isequal([R.candidates(1:n_ranked).cell_id], [candidates.cell_id]);
    if same
        Rr = R.candidates(1:n_ranked);
        [candidates.status] = Rr.status;
        [candidates.start] = Rr.start;
        [candidates.window_firing_rate_hz] = Rr.window_firing_rate_hz;
        [candidates.window_spikes] = Rr.window_spikes;
        if numel(R.candidates) > n_ranked
            extra = convert_struct_paths(R.candidates(n_ranked+1:end), root_path);
            candidates = [candidates(:); extra(:)];
        end
        fprintf('Resuming from %s (%d accepted so far).\n', state_file, nnz(strcmp({candidates.status}, 'accepted')));
    else
        warning('Saved decisions in %s don''t match window_candidates.mat (re-ranked?); starting fresh.', state_file);
    end
end

% 'recording': group windows by recording, ordered by each recording's best rank
% 'rate': one single-window group per candidate, in global rank order
keys = string({candidates.session_path}) + "|" + string([candidates.cell_id]);
if by_rate
    [~, ord] = sort([candidates.rank]);
    groups = num2cell(ord(:));
else
    [~, ~, grp_of] = unique(keys, 'stable');
    groups = accumarray(grp_of(:), (1:numel(candidates))', [], @(v) {sort(v)});
    best_rank = cellfun(@(v) min([candidates(v).rank]), groups);
    [~, ord] = sort(best_rank);
    groups = groups(ord);
end
n_groups = numel(groups);

if only_stim
    % keep only groups with a non-rejected window overlapping its recording's stim
    fprintf('Checking %d group(s) for windows overlapping stim...\n', n_groups);
    stim_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    keep_g = false(1, n_groups);
    for gi = 1:n_groups
        for ci = groups{gi}(:)'
            if strcmp(candidates(ci).status, 'rejected'); continue; end
            k_ci = char(keys(ci));
            if ~isKey(stim_cache, k_ci)
                stim_cache(k_ci) = read_stim_mask(candidates(ci), candidates(ci).nframes, params.stim_thresh);
            end
            m_ci = stim_cache(k_ci);
            x1 = min(numel(m_ci), candidates(ci).start + candidates(ci).len - 1);
            if any(m_ci(candidates(ci).start:x1)); keep_g(gi) = true; break; end
        end
    end
    groups = groups(keep_g);
    n_groups = numel(groups);
    if n_groups == 0
        fprintf('No accepted/undecided window overlaps stim -- nothing to review.\n');
        return
    end
    fprintf('%d group(s) with a stim-overlapping window.\n', n_groups);
end

g = find(cellfun(@(v) any(strcmp({candidates(v).status}, 'pending')), groups), 1);
finished = isempty(g);
if finished; g = 1; end
focus = 1;
trace = []; spikes = []; is_stim = []; loaded_key = "";
pass2 = false; rate_outside = [];

fig = figure('Color', 'w', 'Name', 'Review firing-rate windows', 'NumberTitle', 'off', ...
    'Position', [60 60 1400 800], 'KeyPressFcn', @on_key, 'CloseRequestFcn', @on_close);
ax1 = axes('Parent', fig, 'Position', [0.06 0.45 0.91 0.45]);
ax2 = axes('Parent', fig, 'Position', [0.06 0.08 0.91 0.25]);
if finished && ~only_stim && nnz(strcmp({candidates.status}, 'accepted')) < params.n_windows_target
    fprintf('All windows already reviewed but short of the target; starting the second (manual) pass.\n');
    if ~enter_pass2(); load_group(); draw(); end
else
    load_group();
    draw();
end
uiwait(fig);

    function load_group()
        idx = groups{g};
        row = candidates(idx(1));
        if loaded_key == keys(idx(1)) && ~isempty(trace)
            focus = min(focus, numel(idx));
            return % same recording as before; keep its trace
        end
        loaded_key = keys(idx(1));
        trace = []; spikes = []; is_stim = [];
        try
            trace = double(load_model_trace(row.session_path, 'raw', false, row.cell_id));
            trace = trace(:);
            [sp, ~, ~] = load_spikes(row.session_path, 'raw', false, row.cell_id);
            spikes = round(sp(sp >= 1 & sp <= numel(trace)));
        catch ME
            fprintf('Could not load trace/spikes for %s_%s cell %d (%s)\n', row.hash_id, row.sess_id, row.cell_id, ME.message);
        end
        n = max(numel(trace), row.nframes);
        is_stim = false(1, n);
        prefix = extractBefore(row.session_path, [filesep row.anim_id filesep]);
        [~, root_folder_name] = fileparts(prefix);
        try
            proto = get_stim_protocol(row.session_path, contains(root_folder_name, 'BTSP', 'IgnoreCase', true), 1);
            k = min(numel(proto.trace), n);
            is_stim(1:k) = proto.trace(1:k) > params.stim_thresh;
        catch
            % no stim protocol
        end
        focus = min(focus, numel(idx));
        if only_stim
            % start on the first non-rejected window that overlaps stim
            for kk = 1:numel(idx)
                ck = candidates(idx(kk));
                if ~strcmp(ck.status, 'rejected') && any(is_stim(ck.start:min(numel(is_stim), ck.start + ck.len - 1)))
                    focus = kk;
                    break
                end
            end
        end
    end

    function draw()
        idx = groups{g};
        row = candidates(idx(1));
        n_acc = nnz(strcmp({candidates.status}, 'accepted'));
        need = params.n_windows_target;
        n_tr = numel(trace);

        % ---- whole trace
        cla(ax1); hold(ax1, 'on');
        if n_tr > 0
            y_lo = min(trace); y_hi = max(trace);
        else
            y_lo = 0; y_hi = 1;
        end
        pad = 0.05 * max(y_hi - y_lo, eps); y_lo = y_lo - pad; y_hi = y_hi + pad;
        for r = stim_ranges(is_stim)'
            patch(ax1, [r(1) r(2) r(2) r(1)], [y_lo y_lo y_hi y_hi], 'r', 'FaceAlpha', 0.12, ...
                'EdgeColor', 'none', 'HitTest', 'off');
        end
        for k = 1:numel(idx)
            c = candidates(idx(k));
            [fc, fa] = status_style(c.status);
            lw = 0.5; ec = 'none';
            if k == focus; lw = 2.5; ec = 'k'; end
            x0 = c.start; x1 = c.start + c.len - 1;
            patch(ax1, [x0 x1 x1 x0], [y_lo y_lo y_hi y_hi], fc, 'FaceAlpha', fa, ...
                'EdgeColor', ec, 'LineWidth', lw, 'ButtonDownFcn', @(~, ~) toggle(k));
            lab = sprintf('[%d] rank %d\n%.2f Hz', k, c.rank, c.window_firing_rate_hz);
            if c.manual; lab = sprintf('[%d] manual\n%.2f Hz', k, c.window_firing_rate_hz); end
            text(ax1, (x0 + x1) / 2, y_hi - 0.02 * (y_hi - y_lo), lab, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontWeight', 'bold', ...
                'HitTest', 'off');
        end
        if n_tr > 0
            plot(ax1, 1:n_tr, trace, 'k', 'HitTest', 'off');
            if ~isempty(spikes)
                plot(ax1, spikes, trace(spikes), 'r.', 'MarkerSize', 7, 'HitTest', 'off');
            end
        end
        ylim(ax1, [y_lo y_hi]); xlim(ax1, [1 max(n_tr, row.nframes)]);
        ylabel(ax1, 'Raw fluorescence (a.u.)'); xlabel(ax1, 'Frame');
        if pass2
            nr = nnz(~strcmp({candidates(idx).status}, 'rejected'));
            t = sprintf('PASS 2 (manual) %d/%d: %s_%s cell %d [%s]   outside-window avg %.3f Hz (whole-trace %.3f Hz)   |   windows %d/%d   |   accepted %d / %d needed   |   n = add window', ...
                g, n_groups, row.hash_id, row.sess_id, row.cell_id, row.recording_type, rate_outside(g), ...
                row.avg_firing_rate_hz, nr, nv.max_windows_per_recording, n_acc, need);
        elseif by_rate
            t = sprintf('Window %d/%d (rank %d, %.2f Hz): %s_%s cell %d [%s]   whole-trace avg %.3f Hz   |   accepted %d / %d needed', ...
                g, n_groups, row.rank, row.window_firing_rate_hz, row.hash_id, row.sess_id, row.cell_id, ...
                row.recording_type, row.avg_firing_rate_hz, n_acc, need);
        else
            t = sprintf('Recording %d/%d: %s_%s cell %d [%s]   whole-trace avg %.3f Hz   |   accepted %d / %d needed', ...
                g, n_groups, row.hash_id, row.sess_id, row.cell_id, row.recording_type, row.avg_firing_rate_hz, n_acc, need);
        end
        if n_acc >= need; t = [t '  -- TARGET REACHED']; end
        title(ax1, t, 'Interpreter', 'none', 'Color', ternary(n_acc >= need, [0 0.5 0], [0 0 0]));

        % ---- zoom on focused window
        cla(ax2); hold(ax2, 'on');
        c = candidates(idx(focus));
        x0 = max(1, c.start); x1 = min(max(n_tr, 1), c.start + c.len - 1);
        if n_tr > 0 && x1 > x0
            seg = trace(x0:x1);
            plot(ax2, x0:x1, seg, 'k');
            sp = spikes(spikes >= x0 & spikes <= x1);
            plot(ax2, sp, trace(sp), 'r.', 'MarkerSize', 9);
            xlim(ax2, [x0 x1]);
            lo = min(seg); hi = max(seg); p = 0.05 * max(hi - lo, eps);
            ylim(ax2, [lo - p hi + p]);
        end
        zt = sprintf('[%d] window %d-%d (%d frames): %.3f Hz, %d spikes, status: %s   (recording avg %.3f Hz)', ...
            focus, c.start, c.start + c.len - 1, c.len, c.window_firing_rate_hz, c.window_spikes, c.status, ...
            c.avg_firing_rate_hz);
        if c.start ~= c.orig_start
            zt = sprintf('%s   SHIFTED %+d from %d', zt, c.start - c.orig_start, c.orig_start);
        end
        warn = overlap_warning(idx(focus));
        zc = [0 0 0];
        if ~isempty(warn); zt = [zt '   !! ' warn]; zc = [0.8 0 0]; end
        title(ax2, zt, 'Interpreter', 'none', 'Color', zc);
        xlabel(ax2, '1-9/click toggle | , . shift (< > x10) | m set start | r reset | a/x all | <- -> prev/next | j next undecided | s save | q quit');
        drawnow;
    end

    function ok = enter_pass2()
        % regroup by recording, ordered by average firing rate outside the
        % windows already considered; skip recordings at the window cap or
        % with no room left
        ok = false;
        keys_now = keys;
        [~, ~, gr] = unique(keys_now, 'stable');
        recs = accumarray(gr(:), (1:numel(candidates))', [], @(v) {sort(v)});
        rate_out = -inf(numel(recs), 1);
        for ri = 1:numel(recs)
            v = recs{ri};
            c0 = candidates(v(1));
            if nnz(~strcmp({candidates(v).status}, 'rejected')) >= nv.max_windows_per_recording
                continue
            end
            try
                [spk, ~, ~] = load_spikes(c0.session_path, 'raw', false, c0.cell_id);
            catch
                continue
            end
            spk = round(spk(spk >= 1 & spk <= c0.nframes));
            covered = false(1, c0.nframes);
            for j = v(:)'
                covered(max(1, candidates(j).start):min(c0.nframes, candidates(j).start + candidates(j).len - 1)) = true;
            end
            out_frames = nnz(~covered);
            if out_frames < c0.len; continue; end
            dt = c0.total_spikes / (c0.nframes * c0.avg_firing_rate_hz); % seconds per frame
            rate_out(ri) = nnz(~covered(spk)) / (out_frames * dt);
        end
        eligible = find(isfinite(rate_out));
        if isempty(eligible)
            fprintf('No recordings left with room for another window.\n');
            return
        end
        [~, o] = sort(rate_out(eligible), 'descend');
        eligible = eligible(o);
        groups = recs(eligible);
        rate_outside = rate_out(eligible);
        n_groups = numel(groups);
        pass2 = true; g = 1; focus = 1;
        fprintf('Second pass: %d recording(s) can take another window, highest outside-window rate first.\n', n_groups);
        load_group();
        draw();
        ok = true;
    end

    function add_window()
        if ~pass2
            fprintf('n adds a manual window in the second pass only (press p to enter it).\n');
            return
        end
        idx = groups{g};
        if nnz(~strcmp({candidates(idx).status}, 'rejected')) >= nv.max_windows_per_recording
            fprintf('This recording already has %d windows (max_windows_per_recording).\n', nv.max_windows_per_recording);
            return
        end
        c0 = candidates(idx(1));
        len = c0.len; nfr = c0.nframes; last_start = nfr - len + 1;
        spk = spikes(spikes >= 1 & spikes <= nfr);
        cum = cumsum([0, accumarray(spk(:), 1, [nfr, 1])']);
        ws = cum(len+1:nfr+1) - cum(1:last_start);
        score = double(ws);
        for j = idx(:)'
            lo = max(1, candidates(j).start - len + 1);
            hi = min(last_start, candidates(j).start + len - 1);
            score(lo:hi) = -inf;
        end
        if strcmp(params.stim_mode, 'window_avoid')
            st = false(1, nfr);
            m = min(nfr, numel(is_stim)); st(1:m) = is_stim(1:m);
            cs = cumsum([0, st]);
            score(cs(len+1:nfr+1) - cs(1:last_start) > 0) = -inf;
        end
        [best, bi] = max(score);
        if ~isfinite(best)
            fprintf('No free spot for another window in this recording.\n');
            return
        end
        nc = c0;
        nc.start = bi; nc.orig_start = bi; nc.len = len;
        nc.window_spikes = ws(bi);
        dt = c0.total_spikes / (c0.nframes * c0.avg_firing_rate_hz);
        nc.window_firing_rate_hz = ws(bi) / (len * dt);
        nc.rank = max([candidates.rank]) + 1;
        nc.rank_in_recording = numel(idx) + 1;
        nc.status = 'accepted';
        nc.manual = true;
        candidates(end+1) = nc;
        keys(end+1) = keys(idx(1));
        groups{g} = [idx(:); numel(candidates)];
        focus = numel(groups{g});
        save_state(false);
        draw();
    end

    function set_start(ci, new_start)
        % move candidate ci to new_start (clamped), recomputing its spike count and rate
        c = candidates(ci);
        new_start = round(max(1, min(c.nframes - c.len + 1, new_start)));
        candidates(ci).start = new_start;
        ws = nnz(spikes >= new_start & spikes <= new_start + c.len - 1);
        dt = c.total_spikes / (c.nframes * c.avg_firing_rate_hz); % seconds per frame
        candidates(ci).window_spikes = ws;
        candidates(ci).window_firing_rate_hz = ws / (c.len * dt);
        save_state(false);
        draw();
    end

    function shift_focus(delta)
        idx = groups{g};
        set_start(idx(focus), candidates(idx(focus)).start + delta);
    end

    function warn = overlap_warning(ci)
        % stim or other non-rejected windows of the same recording overlapping candidate ci
        c = candidates(ci);
        warn = '';
        x0 = c.start; x1 = c.start + c.len - 1;
        if any(is_stim(x0:min(numel(is_stim), x1)))
            warn = 'OVERLAPS STIM';
        end
        same_rec = find(keys == keys(ci) & (1:numel(candidates)) ~= ci);
        for j = same_rec
            o = candidates(j);
            if ~strcmp(o.status, 'rejected') && o.start <= x1 && o.start + o.len - 1 >= x0
                if ~isempty(warn); warn = [warn ' + ']; end %#ok<AGROW>
                warn = [warn sprintf('OVERLAPS window rank %d', o.rank)]; %#ok<AGROW>
                break
            end
        end
    end

    function toggle(k)
        idx = groups{g};
        if k > numel(idx); return; end
        focus = k;
        if strcmp(candidates(idx(k)).status, 'accepted')
            candidates(idx(k)).status = 'rejected';
        else
            candidates(idx(k)).status = 'accepted';
        end
        save_state(false);
        draw();
    end

    function set_all(status)
        for i = groups{g}'
            candidates(i).status = status;
        end
        save_state(false);
        draw();
    end

    function go(newg)
        if newg > n_groups && ~pass2 && ~only_stim && ~any(strcmp({candidates.status}, 'pending')) && ...
                nnz(strcmp({candidates.status}, 'accepted')) < params.n_windows_target
            fprintf('Reached the end with nothing undecided but short of the target; starting the second (manual) pass.\n');
            if enter_pass2(); return; end
        end
        newg = max(1, min(n_groups, newg));
        if newg == g; return; end
        g = newg; focus = 1;
        load_group();
        draw();
    end

    function on_key(~, ev)
        ch = ev.Character;
        if ~isempty(ch) && any(ch == '123456789')
            toggle(str2double(ch));
            return
        end
        switch ch
            case ','; shift_focus(-shift_step); return
            case '.'; shift_focus(shift_step); return
            case '<'; shift_focus(-10 * shift_step); return
            case '>'; shift_focus(10 * shift_step); return
        end
        switch ev.Key
            case {'rightarrow', 'space'}
                go(g + 1);
            case 'leftarrow'
                go(g - 1);
            case 'f'
                idx = groups{g};
                focus = mod(focus, numel(idx)) + 1;
                draw();
            case 'n'
                add_window();
            case 'p'
                if pass2
                    fprintf('Already in the second pass.\n');
                else
                    enter_pass2();
                end
            case 'm'
                idx = groups{g};
                ans_s = inputdlg('Start frame for the focused window:', 'Move window', 1, ...
                    {num2str(candidates(idx(focus)).start)});
                if ~isempty(ans_s) && ~isnan(str2double(ans_s{1}))
                    set_start(idx(focus), str2double(ans_s{1}));
                end
            case 'r'
                idx = groups{g};
                set_start(idx(focus), candidates(idx(focus)).orig_start);
            case 'a'
                set_all('accepted');
            case 'x'
                set_all('rejected');
            case 'j'
                nxt = find(cellfun(@(v) any(strcmp({candidates(v).status}, 'pending')), groups(g+1:end)), 1);
                if isempty(nxt)
                    fprintf('No later %s with undecided windows.\n', ternary(by_rate, 'windows', 'recordings'));
                else
                    go(g + nxt);
                end
            case 's'
                save_state(true);
            case 'q'
                on_close();
        end
    end

    function on_close(~, ~)
        save_state(true);
        delete(fig);
    end

    function save_state(verbose)
        acc = strcmp({candidates.status}, 'accepted');
        selected_windows = candidates(acc); %#ok<NASGU>
        save(state_file, 'candidates', 'selected_windows', 'params');
        if verbose
            if any(acc)
                writetable(struct2table(selected_windows), fullfile(sel_dir, 'selected_windows.csv'));
            end
            if ~isnan(nv.psnr_cutoff) && any(acc)
                try
                    write_training_sessions(params.cell_type, nv.psnr_cutoff, ...
                        save_str=params.save_str, window_selection_file=state_file);
                catch ME
                    warning('Could not write the training session list: %s', ME.message);
                end
            end
            n_acc = nnz(acc);
            fprintf('Saved %d accepted window(s) (%d frames of %d target) to %s\n', n_acc, ...
                n_acc * params.window_len, params.target_frames, state_file);
            if n_acc > params.n_windows_target
                fprintf('  note: %d more than the %d needed -- dataset will exceed target_frames.\n', ...
                    n_acc - params.n_windows_target, params.n_windows_target);
            end
        end
    end
end

function m = read_stim_mask(row, n, stim_thresh)
% logical 1xn stim mask for a candidate's recording (all false if no stim protocol)
m = false(1, n);
prefix = extractBefore(row.session_path, [filesep row.anim_id filesep]);
[~, root_folder_name] = fileparts(prefix);
try
    proto = get_stim_protocol(row.session_path, contains(root_folder_name, 'BTSP', 'IgnoreCase', true), 1);
    k = min(numel(proto.trace), n);
    m(1:k) = proto.trace(1:k) > stim_thresh;
catch
    % no stim protocol
end
end

function [color, alpha] = status_style(status)
switch status
    case 'accepted'; color = [0.15 0.7 0.25]; alpha = 0.35;
    case 'rejected'; color = [0.85 0.3 0.3]; alpha = 0.15;
    otherwise;       color = [0.25 0.45 0.9]; alpha = 0.25;
end
end

function out = ternary(cond, a, b)
if cond; out = a; else; out = b; end
end

function ranges = stim_ranges(mask)
% Nx2 [start, end] frame indices of contiguous true runs (returned so a
% for-loop over the transpose iterates one range per column).
d = diff([0, mask(:)', 0]);
starts = find(d == 1);
ends = find(d == -1) - 1;
ranges = [starts(:), ends(:)];
end
