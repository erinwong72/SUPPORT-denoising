%% TEMPLATE for preprocessing using new pipeline (optional SUPPORT)

% make a copy of this script in your own Labmembers folder to avoid
% modifying source code
clear; close all;
if ismac || isunix
    root_path = '/Volumes/fanlab-1';
elseif ispc
    root_path = 'Z:';
end

addpath(fullfile(root_path,'Computer Code','SUPPORT-denoising','utils'));
safe_addpath(fullfile(root_path,'Computer Code','SUPPORT-denoising','preprocessing'));

%% defining arguments for the preprocessing function
opts = struct();
opts.source_dir = fullfile(root_path, 'Labmembers','Kohl','CCK');
opts.use_support = true;
opts.anim_id = 'cck-gtacr-w14';
opts.sess_id = '01_22_2026-VR_V_Disinhibit';
opts.sel_FOVs = [];
opts.sel_slices = [];
opts.exclude = {};

% preprocessing steps (1=run, 0=skip)

opts.prepro = [1 1 1 1 1 1];
opts.rerun  = [0 0 0 0 0 0];

% SUPPORT-specific (only used if use_support=true), do not have to define
% if not using SUPPORT
opts.support.username = 'knswift';
% name of the model you want to use: 
% 1. 'CCKBC' for basket cells
% 2. 'PC' for pyramidal cells
opts.support.model = 'CCKBC';
% set equal to 1 if you want to see the progress during denoising
opts.support.background = 0;
% name of directory you want to save outputs to (will create inside the
% session folder where undenoised outputs of preprocessing usually go)
opts.support.dirname = 'support_CCKBC';

% experiment flags
opts.is_stim = true;
opts.use_ring_bkg = false;

%% running preprocessing
batchPreprocess_EW(opts)

% additionally, you can make loops and call batchPreprocess_EW multiple
% times e.g. if you wanted to process multiple sessions or animals