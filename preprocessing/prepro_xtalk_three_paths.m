%% prepro_xtalk_three_paths.m
% Local / interactive equivalent of run_headless_xtalk_three.sh.
% Prefer the shell script to submit three concurrent remote MATLAB jobs.
%
% This script calls preprocessing_headless three times sequentially for the
% Rimonabant FOV3 recording (raw + support_with_stim + support_no_stim_model).

clear; close all;

if ismac
    root_path = '/Volumes/fanlab';
elseif isunix
    root_path = '/mnt/fanlab';
elseif ispc
    root_path = 'Z:';
end

session_path = fullfile(root_path, ...
    'Data and Analysis', 'DSI-BTSP', 'CCKBC-to-PC-DSI_CB1pharm', ...
    'cck-ipsp-btsp-w31', '2026-03-05_DSI_2mgkg_Rimonabant', ...
    'slice1', 'FOV3', ...
    '173012_IPSP_AO1.0_200ms-DSI_AO4_500ms_OD1.0');
slmoffFrames = 9696:10030;
prepro = [0 0 0 1 1 0];

% Ensure this folder is on the path when run from MATLAB desktop
addpath(fullfile(root_path, 'Labmembers', 'Erin', 'code'));

fprintf('\n===== [1/3] raw -> template_mask_results =====\n');
preprocessing_headless(false, prepro, '', '', ...
    'session_paths', {session_path}, ...
    'slmoffFrames', slmoffFrames, ...
    'use_ring_bkg', true);

fprintf('\n===== [2/3] support_with_stim =====\n');
preprocessing_headless(true, prepro, 'PC_for_paper', 'support_with_stim', ...
    'session_paths', {session_path}, ...
    'slmoffFrames', slmoffFrames, ...
    'use_ring_bkg', true);

fprintf('\n===== [3/3] support_no_stim_model =====\n');
preprocessing_headless(true, prepro, 'PC_no_stim', 'support_no_stim_model', ...
    'session_paths', {session_path}, ...
    'slmoffFrames', slmoffFrames, ...
    'use_ring_bkg', true);

fprintf('\nDone.\n');
