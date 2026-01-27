function [sessions, stats] = curateSessions(sessions, min_spikes, snr_min, verbose, remove_fields)
%CURATESESSIONS Remove low-quality sessions by spike count and SNR.
%   [SESSIONS, STATS] = CURATESESSIONS(SESSIONS, MIN_SPIKES, SNR_MIN, VERBOSE)
%   applies filters and returns the pruned struct array and summary stats.

if nargin < 2 || isempty(min_spikes), min_spikes = 5; end
if nargin < 3 || isempty(snr_min),    snr_min    = 1.0; end
if nargin < 4, verbose = true; end
if nargin < 5, remove_fields = {}; end

% Pre-stats
num_recordings = numel(sessions);
num_anim = numel(unique({sessions.anim_id}));
num_cells = numel(unique({sessions.cell_hash}));

if verbose
    fprintf('Before Curation: %d Unique Cells from %d Sessions and %d Animals\n', ...
        num_cells, num_recordings, num_anim);
end

% --- (optional) post-hoc correction placeholder ---
% for k = 1:numel(sessions)
%     sessions(k).beh.vel = sessions(k).beh.vel/50;
%     % sessions(k).beh.still = sessions(k).beh.vel < 1 & sessions(k).beh.vel > -1;
% end

% Remove: no/low spikes
orig_num_cells = num_cells;
no_spikes = [sessions.nspikes] <= min_spikes;
sessions = sessions(~no_spikes);
num_cells = numel(unique({sessions.cell_hash}));
if verbose
    fprintf('Removed %1.0f Sessions and %1.0f Cells: <= %1.0f Spikes\n', ...
        sum(no_spikes), orig_num_cells - num_cells, min_spikes);
end

% Remove: low SNR
orig_num_cells = num_cells;
low_snr = [sessions.snr] < snr_min;
sessions = sessions(~low_snr);
num_cells = numel(unique({sessions.cell_hash}));

if verbose
    fprintf('Removed %1.0f Sessions and %1.0f Cells: SNR < %g\n', ...
        sum(low_snr), orig_num_cells - num_cells, snr_min);
end

% keep relevant fields
if ~isempty(remove_fields)
    sessions = rmfield(sessions, intersect(fieldnames(sessions), remove_fields));
end

% Post-stats
num_recordings = numel(sessions);
num_anim = numel(unique({sessions.anim_id}));
num_sess = numel(unique({sessions.session_path}));
num_cells = numel(unique({sessions.cell_hash}));

if verbose
    fprintf('After Curation: %d Unique Cells from %d Sessions and %d Animals\n', ...
        num_cells, num_recordings, num_anim);
end

stats = struct('num_recordings', num_recordings, ...
               'num_anim', num_anim, ...
               'num_sess', num_sess, ...
               'num_cells', num_cells);
end
