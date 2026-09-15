%% TEMPLATE for preprocessing using new pipeline (optional SUPPORT)
%
% Make a copy of this script in your own Labmembers folder (e.g.
% Labmembers/<you>/code/preprocessing.m) to avoid modifying source code.
% See also reviewIntensICA.m / findSkippedICACells.m for post-auto-ICA review.

clear; close all;
if ismac || isunix
    root_path = '/Volumes/fanlab';
elseif ispc
    root_path = 'Z:';
end

% Set tinkering=1 to use your Labmembers/.../code checkout of SUPPORT-denoising;
% set tinkering=0 to use the shared Computer Code copy.
tinkering = 1;
if ~tinkering
    code_path = fullfile(root_path, 'Computer Code');
else
    code_path = fullfile(root_path, 'Labmembers', 'YOURNAME', 'code'); % fill this in with wherever you cloned the directory to
end
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));

%% defining arguments for the preprocessing function
opts = struct();

% --- Session selection ---
% Option A: discover under source_dir (filter with anim_id / sess_id / etc.)
% opts.source_dir = fullfile(root_path, 'Labmembers', 'Kohl', 'CCK');
% opts.anim_id = 'cck-gtacr-w14';
% opts.sess_id = '01_22_2026-VR_V_Disinhibit';

% Option B: pass a curated session list (skips discovery; source_dir not needed)
% but run dataset_generation.m first to generate the total_sessions.mat file, and replace the path below with the correct path to the file
opts.session_list = load(fullfile(code_path, ...
    'SUPPORT-denoising', 'datasets', 'PC_no_stim', 'total_sessions_.mat')).total_sessions;
% opts.session_list = convert_struct_paths(opts.session_list); % if paths need remapping
% After reviewIntensICA, you can re-run just the disagreed recordings:
% opts.session_list = load(...'ICA_Review_Disagreed.mat').disagreed; % adapt fields as needed

% Optional filters (apply in discovery mode and/or to narrow session_list)
% opts.sel_slices = [2];
% opts.sel_FOVs = [3];
% opts.sel_recs = {}; % e.g. {'Spon30','VR1'} — specific recording folder names
opts.exclude = {};

% struct_save [1x3]:
%   (1) re-run discovery instead of loading cached session struct
%   (2) reserved / re-save session struct
%   (3) overwrite sessions_for_support.txt
opts.struct_save = [1 0 0];

% preprocessing steps (1=run, 0=skip)
%   1 Motion correction (NoRMCorre -> movReg.bin)
%   2 SUPPORT raw.tiff generation - no need to do this anymore
%   3 Running SUPPORT inference on the server
%   4 ICA Pre
%   5 ICA Choose
%   6 Spike thresholding
opts.prepro = [0 0 1 0 0 0]; % only change the last four values to 1 if you want to run the steps
opts.rerun  = [0 0 0 0 0 0];

% --- SUPPORT (only used when use_support=true) --- will need to create an ssh key and add it to the server
opts.use_support = true;
opts.support.username = 'knswift'; % enter your own username
% Model name, e.g. 'CCKBC', 'PC', 'PC_no_stim'
opts.support.model = 'CCKBC';
% 1 = show progress during denoising on the server
opts.support.background = 0;
% Output subfolder created inside each session folder
opts.support.dirname = 'support_CCKBC';

% --- Experiment / ICA flags ---
opts.is_stim = true;
opts.use_ring_bkg = true;
% Auto-select confident ICs in ICA_Choose (score_ica_components.m)
opts.use_auto_ica = false;
% When true with use_auto_ica: never prompt — flag ambiguous cells and leave
% them undecided (NaN). Review later with reviewIntensICA / findSkippedICACells.
opts.auto_skip_ica = false;

%% running preprocessing
batchPreprocess_EW(opts)

%% reviewing automated ICA (optional; after a use_auto_ica batch)
% Opens Fig_intens_ICA once per unique session_path; enter accepted cell #s.
disagreed = reviewIntensICA(opts);

% Additionally, you can loop and call batchPreprocess_EW multiple times,
% e.g. for several animals or to re-run only disagreed sessions.
