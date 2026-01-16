% batch_preprocess.m
% copy of preprocess integrated with support for denoising
% EW 01/13/2025 based on KS 5/20/2025
% Based on Linlin Fan Scripts:
% 0) SUPPORT
% 1) Motion Correction - Ru n_dir_mov_RMCorre.m
% 2) ICA/PCA - Run_dir_PCA_ICA_RMmov.m
% 3) Spike Thresholding - Run_dir_spikeT_spikeW_FOV.m

clear; close all;

%% Session & FOV Parameters

% Automatically detect OS: Windows uses Z:\, macOS/Linux use /Volumes/fanlab
if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end

% defaults to applying support after motion correction
%motion_corr = 'post-motion'; % 0 if pre-motion correction, 1 if post

%% generating paths
addpath(fullfile(root_path,'Labmembers','Erin', 'code', 'SUPPORT-denoising', 'utils'));
safe_addpath(fullfile(root_path,'Labmembers','Kohl','Code'));
safe_addpath(fullfile(root_path,'Labmembers','Erin','code'));
safe_addpath(fullfile(root_path,'Computer Code','Image Processing'));
safe_addpath(fullfile(root_path,'Computer Code','NoRmCorre'));
safe_addpath(fullfile(root_path,'Computer Code','Fan Lab'));

%% setting directories
% custom_raw_roots = containers.Map( ...
%     {'cck-gevi-w03', 'cck-gevi-w05'}, ...
%     { fullfile(root_path,'Data and Analysis','DSI-BTSP','CCK-voltage_KS','cck-gevi-w03'), ...
%       fullfile(root_path,'Labmembers','Kohl','CCK','cck-gevi-w05') } ...
% );

path.root.data = fullfile(root_path,'Labmembers','Kohl','CCK');
%path.root.data = fullfile(root_path,'Labmembers','Xingyu', 'CCK-GtACR-BTSP');
custom_raw_roots = path.root.data;
path.anim_ids = {'cck-inhDSI-w08'};
path.sess_ids = {'2026-01-13-VR-V_blue'};
sel_FOVs = [];
sel_slices = [3];
animal_type = 'cck-inhDSI';
exclude = {};

%% set which steps for preprocessing to run
prepro = [1 1 1 1 1 1]; % 1 if running the step, 0 if not
% 1: Motion Correction
% 2: SUPPORT (generate data for model to run)
% 3: SUPPORT inference (apply trained model on data)
% 4: ICA Pre
% 5: ICA Choose
% 6: Spike Thresholding
%preprocessed = 0; % if haven't already analyzed raw data and is the first time preprocessing
use_support = 1;
is_stim = 1;
if is_stim; blueStim = 'AO'; else blueStim = ''; end

%% Preprocessing pipeline on sessions
total_sessions = struct([]);
% will automatically look to see if a sessions file already exists
for a = 1:numel(path.anim_ids)
    new_sessions = discover_sessions(custom_raw_roots, path.anim_ids{a}, path.root.data, exclude);
    total_sessions = [total_sessions, new_sessions];
end
% Convert paths in sessions struct to match current OS (but don't save)
sessions_all = convert_struct_paths(total_sessions, root_path);
sel_sessions = generate_sessions_struct(sessions_all, path, sel_FOVs, sel_slices);

% save session paths to json file for python to use (as a list)
session_paths = {sel_sessions.session_path};
session_paths_list = sprintf('%s\n', session_paths{:});
fid = fopen(fullfile(path.root.data, path.anim_ids{1}, path.sess_ids{1}, 'sessions_for_support.txt'), 'w');
fwrite(fid, session_paths_list, 'char');
fclose(fid);

%% Preprocessing pipeline on sessions
% target_file = "denoised.tiff";
% % check if support sessions file exists, if so, load so that later don't need to filter
% if use_support
%     if isfile(fullfile(parent_root, sprintf('support_sessions_%s.mat', animal_preps{1})))
%         load(fullfile(parent_root, sprintf('support_sessions_%s.mat', animal_preps{1})), 'support_sessions');
%         support_sessions = convert_struct_paths(support_sessions, root_path);
%     else
%         % filter sessions for support
%         support_sessions = filter_sessions_for_support(sessions_all, motion_corr);
%         save(fullfile(parent_root, sprintf('support_sessions_%s.mat', animal_preps{1})), 'support_sessions');
%     end
%     sessions = support_sessions;
% end
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    fprintf('Processing session: %s\n', session_path);
    if use_support; save_dir = fullfile(session_path, 'support'); else; save_dir = session_path; end % Set subdir_path for processing

    %% Motion Correction
    motion_corr_output = 'movReg.bin';
    if prepro(1) && (~isfile(fullfile(session_path,motion_corr_output)))
        disp("Running Motion Correction")
        try
            fid = fopen(fullfile(session_path,'experimental_parameters.txt'), 'r');
            Info = textscan(fid, '%s');
            fclose(fid);
            nrow = str2double(Info{1}{6});
            ncol = str2double(Info{1}{3});

            % Read and process movie
            [mov, ~] = readBinMov(fullfile(session_path, 'Sq_camera.bin'), nrow, ncol);
            movReg = NoRMCorre2(mov);
            savebin(vm(movReg), fullfile(session_path, motion_corr_output));

            fprintf('Success: %s\n', subdir_path);
            fprintf('Success: %s\n', session_path);
        catch ME
            fprintf('Failed: %s\nError: %s\n', session_path, ME.message);
        end
        close all;
    end

    %% generate tiff files for support
    if prepro(2)
        raw_tiff = fullfile(session_path, 'support', 'raw.tiff');
        denoised_tiff = fullfile(session_path, 'support', 'denoised.tiff');
        if ~isfile(raw_tiff) && ~isfile(denoised_tiff)
            if ~exist('movReg','var')
                Info = textscan(fopen(fullfile(session_path,'experimental_parameters.txt')),'%s');
                nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
                binName = fullfile(session_path,'movReg.bin');
                [movReg, nframes] = readBinMov(binName, ncol, nrow);
            end
            movReg = double(movReg);
            options.big = true;
            saveastiff(movReg, raw_tiff, options);
        end
    end
end
% make function run_inference.m that logs into server & runs inference.sh
% given user credentials and the model that you want to use

% KEEP GOING! YOU'RE DOING GREAT :D
% make sure you have SSH key set up for compute server, refer to README for instructions
if prepro(3)
    username = 'knswift';
    model = 'cck-gevi';
    background=0; % stream into matlab command window

    for a = 1:numel(path.anim_ids)
        for s = 1:numel(path.sess_ids)
            data_path = fullfile(path.root.data, path.anim_ids{a}, path.sess_ids{s});
            % changing path to be compatible for the server
            data_path = replace(data_path, root_path, '/mnt/fanlab');
            run_inference(username, data_path, model, background);
        end
    end
end
%% continue after SUPPORT has inferenced on raw data
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    fprintf('Processing session: %s\n', session_path);
    if use_support; save_dir = fullfile(session_path, 'support'); else; save_dir = session_path; end % Set subdir_path for processing
    %% ICA
    if any(prepro(4:5))
        if use_support && ~isfile(fullfile(session_path, 'support', 'denoised.tiff'))
            continue;
        else
            try
                %ICA Pre
                if prepro(3) && ~isfile(fullfile(save_dir,'ICA_PreResults.mat'))
                    disp("Running ICA_Pre")
                    ICA_Pre(is_stim, use_ring_bkg, session_path, use_support);
                end
        
                %ICA Choose
        
                if prepro(4) && isfile(fullfile(save_dir,'ICA_PreResults.mat')) && ~isfile(fullfile(save_dir,'Fig_intens_ICA.fig'))
                    disp("Running ICA_Choose")
                    ICA_Choose(session_path, use_support);
                end
                fprintf('Success: %s\n', session_path);
            catch ME
                fprintf('Failed: %s\nError: %s\n', session_path, ME.message);
            end
        end
        close all;
    end
    
    % SO CLOSE, YOU'RE NEARLY DONE! KEEP IT UP!
    %% Spike Thresholding
    if prepro(5)
        if isfile(fullfile(save_dir,'Masks_BestIcaImgs.mat')) && ~isfile(fullfile(save_dir,'inter_spikeT_spikeW.mat'))
            disp("Running Spike Thresholding")
            try    
                openfig(fullfile(save_dir, 'Fig_intens_ICA.fig'));
                set(gcf, 'Units', 'Normalized', 'OuterPosition', [0 0 1 1]);
    
    
                Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_withpath(blueStim, session_path, use_support); 
    
                disp(['success at ', session_path]);
                close all
            catch ME
                disp(['fail at ', session_path]);
            end
        end
    end
end                                                                                                   