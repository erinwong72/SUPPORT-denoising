% simple_preprocess.m
% copy of preprocess that takes one session integrated with support for denoising
% good for if you just want to preprocess one directory/saved not in the
% default directory structure
% EW 01/06/2026 based on KS 5/20/2025
% Based on Linlin Fan Scripts:
% 0) SUPPORT
% 1) Motion Correction - Ru n_dir_mov_RMCorre.m
% 2) ICA/PCA - Run_dir_PCA_ICA_RMmov.m
% 3) Spike Thresholding - Run_dir_spikeT_spikeW_FOV.m

clear; close all;

%% Session & FOV Parameters
rng(123, 'twister');
os = 1; % 0 if on Z://, lab computer (windows), 1 if mounted in volumes on mac or loading modified version
if os; root_path = fullfile('/Volumes/fanlab'); else; root_path = fullfile('Z:'); end
is_motion_corr = 1; % 0 if pre-motion correction, 1 if post

%% generating paths
addpath(genpath(fullfile(root_path,'Labmembers','Kohl','Code')));
addpath(genpath(fullfile(root_path,'Computer Code','Image Processing')));
addpath(genpath(fullfile(root_path,'Computer Code','NoRmCorre')));
addpath(genpath(fullfile(root_path,'Computer Code','Fan Lab')));

%% Parameters
% 0 purple, 1 red, 2 yellow, 3 green, 4 blue
process_dir = fullfile(root_path, 'Labmembers', 'Roshni', 'k-fold 3 green test', 'model_50');
%path.save_dir = fullfile(path.root.dataset,'analysis');
[~,~] = mkdir(process_dir);
prepro = [0 0 0 1];%[Movement ICA_pre ICA_choose SpikeThreshold
is_rerun = [0 0 0 1];%extra index for analysis
is_stim = 0;
if is_stim; blueStim = 'AO'; else blueStim = ''; end

%% Parse Directories
target_file = 'denoised.tiff';
fprintf('Processing: %s\n', process_dir);

%% Motion Correction
corrected_output = 'movReg.bin';
if prepro(1) && (~isfile(fullfile(process_dir,corrected_output)) || is_rerun(1))
    disp("Running Motion Correction")
    try
        cd(process_dir);

        % Load parameters
        % fid = fopen('experimental_parameters.txt', 'r');
        % Info = textscan(fid, '%s');
        % fclose(fid);
        % nrow = str2double(Info{1}{6});
        % ncol = str2double(Info{1}{3});

        % Read and process movie
        %[mov, ~] = readBinMov(target_file, nrow, ncol);
        mov = loadtiff(target_file);
        movReg = NoRMCorre2(mov);
        savebin(vm(movReg), corrected_output);

        fprintf('Success: %s\n', process_dir);
    catch ME
        fprintf('Failed: %s\nError: %s\n', process_dir, ME.message);
    end
    close all;
end

%% ICA
if any(prepro(2:3))
    try
        split_subdir = strsplit(process_dir, filesep);
        % if ~isfile(fullfile(process_dir,"experimental_parameters.txt")) || ~isfile(fullfile(process_dir, "AI Data"))
        %     if ~isfile(fullfile(process_dir,"experimental_parameters.txt"))
        %         copyfile(fullfile(cck_process_dir, "experimental_parameters.txt"), process_dir);
        %     end
        %     if ~isfile(fullfile(process_dir, "AI Data"))
        %         copyfile(fullfile(cck_process_dir, "AI Data"), process_dir);
        %     end
        % end

        %ICA Pre
        if (~isfile(fullfile(process_dir,'ICA_PreResults.mat')) && prepro(2)) || is_rerun(2)
            cd(process_dir);
            disp("Running ICA_Pre")
            %Run_PCA_ICA_RMmov_FanLab_function(dt); %something up with directories...
            ICA_Pre_support(is_stim, is_motion_corr);
        end

        %ICA Choose
        
        if (isfile(fullfile(process_dir,'ICA_PreResults.mat')) && ~isfile(fullfile(process_dir,'Fig_intens_ICA.fig')) && prepro(3)) || is_rerun(3)
            cd(process_dir);
            disp("Running ICA_Choose")
            if isfolder(fullfile(cck_process_dir, "matlab wvfm")) && ~isfolder(fullfile(process_dir, "matlab wvfm"))
                copyfile(fullfile(cck_process_dir, "matlab wvfm"), fullfile(process_dir, "matlab wvfm"));
                is_stim=1;
            else
                is_stim = 0;
            end
            ICA_Choose_support(is_stim);
        end
        fprintf('Success: %s\n', process_dir);
    catch ME
        fprintf('Failed: %s\nError: %s\n', process_dir, ME.message);
    end
    close all;
end

%% Spike Thresholding
if prepro(4)
    if (isfile(fullfile(process_dir,'Masks_BestIcaImgs.mat')) && ~isfile(fullfile(process_dir,'inter_spikeT_spikeW.mat')) ) || is_rerun(4)
        disp("Running Spike Thresholding")
        try
            cd(process_dir);
            
            %openfig('Fig_intens_ICA.fig');
            %set(gcf, 'Units', 'Normalized', 'OuterPosition', [0 0 1 1]);
            
            
            ext_spike_T(blueStim); 

            disp(['success at ', fullfile(process_dir)]);
            close all
        catch ME
            disp(['fail at ', fullfile(process_dir)]);
        end
    end
end
