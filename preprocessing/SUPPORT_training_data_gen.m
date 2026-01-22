
clear
close all
clc

%% Add these to path if not done already

cd("/Volumes/fanlab/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/NeuroSegmentation/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/NoRMCorre-master/")
addpath("Computer Code/Image Processing/","Computer Code/Image Processing/FastICA_25/")
addpath("Labmembers/Niveda/Code")

%% Specify target file + initial setup

target_file = 'movReg.bin'; % depending on pre- vs post-motion correction
motion_corrected = 1;
sample = 1; % set to 0 if processing testing data

% this is from Erin's code--automatically detects Mac vs Windows
if ismac || isunix
    root_path = ['/Volumes/fanlab'];
elseif ispc
    root_path = ['Z:'];
end

% this is the folder that contains all data (optogenetics + spontaneous)
parent_path = fullfile(root_path,'Labmembers/Adrienne/Sert-ChRmine'); 

%% Extract all filepaths that contain data (.bin file)

% takes ~4 minutes, but would be faster if all files were at a consistent depth 
tic
all_file_paths = fsfind(parent_path,target_file,Depth=Inf);
toc  

% NOTE: if file structure is constant within a folder, can use 
% fsfind(parent_path, 'movReg.bin', DepthwisePattern={[insert pattern]});

%% Exclude certain files based on certain name

% Excludes anything with the label mRNStim that is not a spontaneous or opto recording. Essentially removes mRN stimulation.
mRN_tf = contains(all_file_paths,["mrns", "mrn s", "mrn_s", "00ms", "pulse"],'IgnoreCase', true) .* ~contains(all_file_paths,["spon" "estep"],'IgnoreCase',true);
excl.mRN_Stim = unique(all_file_paths(logical(mRN_tf)));
excl.Usable = unique(all_file_paths(logical(~mRN_tf)));

%% Separate files based on 'AI Data' parameters (only distinguishes between stim and no stim)

Data2Train = excl.Usable; % can set this to anything if needed
filesdiv = struct('SPON', [], 'STIM', []);

for i = 1:length(Data2Train)
    tmp_dir = extractBefore(Data2Train(i), "/movReg.bin");
    cd(tmp_dir)
    aiData_tmp = load('AI Data');
    check_tf(i) = sum(aiData_tmp(5,:)>0.5)>0; % checks if aiData_tmp has stim at any point
    if check_tf(i)
        filesdiv.STIM = [filesdiv.STIM; Data2Train(i)]; % if check==1 (file has stimulation)
    else
        filesdiv.SPON = [filesdiv.SPON; Data2Train(i)];
    end
end

% Check that there is no/minimal overlap in file names and sorted categories
sorted.SPON = filesdiv.SPON(contains(filesdiv.SPON(:,1), 'estep','IgnoreCase', true));
sorted.STIM = filesdiv.STIM(contains(filesdiv.STIM(:,1), 'spon','IgnoreCase', true));

%% Correct data files if necessary (manual step)

corr_data.SPON = filesdiv.SPON(~contains(filesdiv.SPON, sorted.SPON(1:5)));
corr_data.STIM = filesdiv.STIM;

%% Calculate number of cells (needed to calculate # of frames to use for spon training)

corr_data.SPON = cellCounter(corr_data.SPON); 
totalcells.SPON = sum(double(corr_data.SPON(:,2)));
frames.SPON = ceil((300000/totalcells.SPON)/25)*25; % rounded to nearest 25

corr_data.STIM = cellCounter(corr_data.STIM);
totalcells.STIM = sum(double(corr_data.STIM(:,2)));
frames.STIM = 1000;

%% Based on stim vs. spon, number of frames per movie + number of movies will differ

% For SPON, code is calculating the number of frames based on total number of
% movies. For STIM, I am having 1000-frame movies that will capture both
% stimulated and resting cell activity. For STIM, frames will be chosen
% from 300 random movies.

% This section sets up parameters needed to actually extract movies
%       condition: change to SPON or STIM
%       folder2extract: folder that contains file directories to extract movies from
%       sel_nframes: number of frames each movie should have
%       save_mov_path: file location to save extracted movies

rng(123)
condition = "STIM"; % change this accordingly
sample=1; % set to 1 if generating training data, set to 0 for test data

switch condition
    case "SPON"
        folder2extract = corr_data.SPON;
        sel_nframes = frames.SPON;
        save_mov_path = fullfile(root_path,'Labmembers/Niveda/Training Data_spon');
    case "STIM"
        if length(fields(corr_data)) < 3
            allSTIMcell = [];
            for j = 1:length(corr_data.STIM)
                for k = 1:double(corr_data.STIM(j,2))
                    tmp_dir = corr_data.STIM(j,1);
                   % tmp_dir = extractBefore(corr_data.STIM(j,1),"/movReg.bin");
                    withCell = strcat(tmp_dir,"_", num2str(k)); % k is the cell
                    allSTIMcell = [allSTIMcell; withCell];
                end
            end
            % randomly pick 300 movies from all stim movies
            stim_i = randi(length(allSTIMcell), [300, 1]);
            STIMsubset_int = allSTIMcell(stim_i);
            for n = 1:length(STIMsubset_int)
               corr_data.STIMsubset(n,1) = extractBefore(STIMsubset_int(n), strlength(STIMsubset_int(n))-1);
               corr_data.STIMsubset(n,2) = extract(STIMsubset_int(n), strlength(STIMsubset_int(n)));
            end
        end
        folder2extract = corr_data.STIMsubset;
        sel_nframes = frames.STIM;
        save_mov_path = fullfile(root_path,'Labmembers/Niveda/Training Data_stim');
end

%% Now extract small movies from either SPON or STIM

sample = 0;
folder2extract = support_test;
save_mov_path = fullfile(root_path,'Labmembers/Niveda/Testing/Noisy_Test/');
condition = "SPON";

for z = 1:length(folder2extract)
    if condition=="SPON"
        upperlim = 1:double(folder2extract(z,2)); % all cells
    elseif condition=="STIM"
        upperlim = double(folder2extract(z,2)); % single cell number
    end
    
    for k = upperlim
        % edit file names accordingly
        animalID = extractBetween(folder2extract(z,1), 'Sert-ChRmine/', '/2');
        sessID = extractBetween(folder2extract(z,1), regexp(folder2extract(z,1), 'FOV\d+/','match'), '/mov');
        file_name = sprintf('%s_%s_%s.tif', animalID, sessID, num2str(k)); % last number is the cell #
        file_path = fullfile(save_mov_path,file_name);

        if ~isfile(file_path)
            tmp = extractBefore(folder2extract(z,1), "/movReg.bin");
            cd(tmp)
            fid = fopen('experimental_parameters.txt', 'r');
            Info = textscan(fid, '%s');
            fclose(fid);
            if motion_corrected;
                ncol = str2double(Info{1}{6});
                nrow = str2double(Info{1}{3});
            else
                nrow = str2double(Info{1}{6});
                ncol = str2double(Info{1}{3});
            end
            [mov, nframes] = readBinMov(folder2extract(z,1), nrow, ncol);

            if sample == 0
                mov = double(mov);
                options.big = true;
                saveastiff(mov, file_path, options);
            else
                switch condition
                    case "SPON"
                        starting_idx = int16(rand * (nframes-sel_nframes));
                    case "STIM"
                        %if contains(tmp,'estep')
                        starting_idx = int16(1000 * randi([0 11]));
                       % elseif contains(tmp,'spon')
                       %     int_AI = load('AI Data');
                       %     indx = find(int_AI>0.5); 
                       %     

                       % end
                end
                mov_part = double(mov(:, :, starting_idx:starting_idx+sel_nframes-1));
                nframes = size(mov_part, 3);
                [Fmasks, roimask] = apply_mask_RMmov_BkgSel_nodisp(mov_part, Info, motion_corrected);
                Fmask2 = zeros(nframes,1); outrangecell = zeros(1);
                for i = 1:length(roimask)
                    if ~isnan(Fmasks(1,i))
                        Fmask2 = [Fmask2, Fmasks(:,i)];
                    else
                        outrangecell = [0,i];
                    end
                end
                Fmask2(:,1) = []; outrangecell(1) = []; roimask(:,outrangecell) = [];
                % Background subtraction
                bkg = Fmask2(:,end);
                sbkg = bkg;
                mov2 = mov_part - repmat(reshape(sbkg,[1,1,nframes]),[nrow, ncol,1]);

                x1 = roimask{k}(:,2);
                y1 = roimask{k}(:,1); edge = 5;
                X1 = ceil(min(x1))-edge; if X1<1, X1=1; end
                X2 = floor(max(x1))+edge; if X2>nrow, X2=nrow; end
                Y1 = ceil(min(y1))-edge; if Y1<1, Y1=1; end
                Y2 = floor(max(y1))+edge; if Y2>ncol, Y2=ncol; end
                MaskMov = mov_part(X1:X2,Y1:Y2,:);
                [rows, cols, time] = size(MaskMov);
                
                saveastiff(MaskMov, file_path);
            end
        else
            fprintf('Skipping saved file: %s\n', file_path);
        end

    end
end


%% Functions

function data_folder = cellCounter(data_folder)
    for z = 1:length(data_folder) % can change this to pull from a different dataset 
            tmp = extractBefore(data_folder(z,1), "/movReg.bin"); % replace first 1 with i
            cd(tmp)
            cd('../') % should be in FOV folder
            load Masks
            nCell = length(pts_list);
            data_folder(z,2) = nCell;
     end
end


% Copy and pasted from support_dataset_generation.m located in
% /Volumes/fanlab/Labmembers/Erin/code/SUPPORT-denoising/preprocessing
% copied from apply_mask_RMmov_BkgSel_FanLab.m
function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_nodisp(mov, info, motion_corr)
path = cd;
if motion_corr
    xoffset = str2num(info{1,1}{33,1})-288; yoffset = str2num(info{1,1}{30,1})-288;
else
    yoffset = str2num(info{1,1}{33,1})-288; xoffset = str2num(info{1,1}{30,1})-288;
end
cd('../'); load Masks; cd(path);%load EVmask; cd(path);
num_masks=length(pts_list);
ROI=cell(1,num_masks);
for i=1:num_masks
    if motion_corr; x1=pts_list{i}(:,2)/2-xoffset; y1=pts_list{i}(:,1)/2-yoffset;
    else; x1=pts_list{i}(:,1)/2-xoffset; y1=pts_list{i}(:,2)/2-yoffset;
    end
    ROImask{i}=[x1,y1];
end

xbk=[1;30;30;1;1]; ybk = [1;1;30;30;1] + 0;
ROImask{num_masks+1} = [xbk,ybk];

Fmasks=apply_clicky(ROImask,double(mov), 'no');
end

