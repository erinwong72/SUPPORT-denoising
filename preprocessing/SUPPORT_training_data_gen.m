
% clear
% close all
clc

%% Add these to path if not done already

cd("/Volumes/fanlab/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/NeuroSegmentation/")
addpath("Computer Code/Fan Lab/1extract-voltage-imaging-signal/NoRMCorre-master/")
addpath("Computer Code/Image Processing/","Computer Code/Image Processing/FastICA_25/")
addpath("Computer Code/SUPPORT-denoising/utils");
addpath("Computer Code/SUPPORT-denoising/preprocessing");

%% CHANGE THESE PARAMETERS!

target_file = 'movReg.bin'; % movReg.bin is motion-corrected
data_type = 0; % Set to 0 if extracting testing data, set to 1 for training data
test_maskmov = 0; % If extracting TESTING data, do you want to extract mask movies or whole movie? 0=whole, 1=mask

% This is the folder that contains all data (optogenetics + spontaneous) - change based on Mac or windows
parent_path = ['/Volumes/fanlab/Labmembers/Adrienne/Sert-ChRmine/'];

% What condition are you extracting: SPON or STIM
condition = "SPON";

% Depending on condition and data_type, set where extracting movies should get saved to
switch condition
    case "SPON"
        if data_type % training
            save_mov_path = ['/Volumes/fanlab/Labmembers/Niveda/Training Data_spon'];
        else % testing
            save_mov_path = ['/Volumes/fanlab/Labmembers/Niveda/Testing_SPON/'];
        end
    case "STIM"
        if data_type % training
            save_mov_path = ['/Volumes/fanlab/Labmembers/Niveda/Training Data_stim'];
        else % testing
            save_mov_path = ['/Volumes/fanlab/Labmembers/Niveda/Testing_STIM/'];
        end
end

% Specify how you want extracted movies to be saved
% Example:
%   Suppose file path is "Labmembers/Adrienne/Sert-ChRmine/SertChRmine04/2025-04-15_SertChRmine04_PC/FOV2/163755_Spon30"
%       animalID is "SertChRmine04", identified as coming between end of parent_path and /2025
%       sessID is "163755_Spon30", identified as coming after "FOV_"
%   File will be saved as "SertChRmine04_163755_Spon30_1.tif", where the number before ".tif" is the cell
% These are automatically identified and saved. To change, go to the
% beginning of Section 6.

%% Section 1: Extract all filepaths that contain target_file

disp('Finding file paths...')
% takes ~4 minutes, but would be faster if all files were at a consistent depth 
tic
all_file_paths = fsfind(parent_path,target_file,Depth=Inf);
afp_time = toc;

disp(strcat('File paths found. See all_file_paths. Time elapsed: ',num2str(afp_time)))
clear afp_time

% NOTE: if file structure is constant within a folder, can use:
% fsfind(parent_path, 'movReg.bin', DepthwisePattern={[insert pattern]});

%% Section 2: Exclude files based on certain name/keywords - CHANGE IF NEEDED

% Excludes anything with the label mRNStim that is not a spontaneous or opto recording. Essentially removes mRN stimulation.
mRN_tf = contains(all_file_paths,["mrns", "mrn s", "mrn_s", "00ms", "pulse"],'IgnoreCase', true) .* ~contains(all_file_paths,["spon" "estep"],'IgnoreCase',true);
excl.mRN_Stim = unique(all_file_paths(logical(mRN_tf)));
excl.Usable = unique(all_file_paths(logical(~mRN_tf)));

%% Section 3: Separate files into STIM and SPON (based on 'AI Data' parameters)

Data2Train = excl.Usable; % can set this to all_file_paths if nothing was excluded
filesdiv = struct('SPON', [], 'STIM', []);
disp('Identifying movies with spontaneous activity vs. stimulation ...')

tic
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
sep_time = toc;

disp('Recordings separated into spontaneous activity vs. stimulation. See filesdiv for divided files.')
disp(strcat('To check for overlap, see sorted. Time elapsed:',num2str(sep_time)));

clear sep_time

%% Section 3b: Correct data files if necessary (MANUAL STEP)

% If no corrections needed, can change corr_data.SPON and .STIM to equal filesdiv.SPON and .STIM, respectively.
% Keep corr_data as a variable because it is used later on.
corr_data.SPON = filesdiv.SPON(~contains(filesdiv.SPON, sorted.SPON(1:5)));
corr_data.STIM = filesdiv.STIM;

%% Section 4: Calculate number of cells in each movie.

% number of cells are stored in 2nd column of each
%if data_type==1
    disp('Calculating number of cells in each movie...')
    tic
    corr_data.SPON = cellCounter(corr_data.SPON); 
    totalcells.SPON = sum(double(corr_data.SPON(:,2)));
    frames.SPON = ceil((300000/totalcells.SPON)/25)*25; % rounded to nearest 25
    
    corr_data.STIM = cellCounter(corr_data.STIM);
    totalcells.STIM = sum(double(corr_data.STIM(:,2)));
    frames.STIM = 1000;
    dispt = toc;
    disp(strcat("Done calculating. Time elapsed: ", num2str(dispt)))
    clear dispt
%end

%% Section 5: Calculate number of frames per movie/number of movies necessary to train
% Only applicable if extracting training dataset.

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
% condition = "STIM"; % change this accordingly
% data_type=1; % set to 1 if generating training data, set to 0 for test data
disp('Calculating number of frames/movies needed for training...')
tic

if data_type==1 % training
    switch condition
        case "SPON"
            folder2extract = corr_data.SPON;
            sel_nframes = frames.SPON;
          %  save_mov_path = fullfile(root_path,'Labmembers/Niveda/Training Data_spon');

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
                stim_i = randperm(length(allSTIMcell), 300);
                STIMsubset_int = allSTIMcell(stim_i);
                for n = 1:length(STIMsubset_int)
                   corr_data.STIMsubset(n,1) = extractBefore(STIMsubset_int(n), strlength(STIMsubset_int(n))-1);
                   corr_data.STIMsubset(n,2) = extract(STIMsubset_int(n), strlength(STIMsubset_int(n)));
                end
            end
            folder2extract = corr_data.STIMsubset;
            sel_nframes = frames.STIM;
          %  save_mov_path = fullfile(root_path,'Labmembers/Niveda/Training Data_stim');
    end
elseif data_type==0 % testing
    switch condition
        case "SPON"
            
            % this is just for testing dataset:
          spon_i = randperm(length(corr_data.SPON), 50);
          corr_data.SPONsubset = corr_data.SPON(spon_i,:);
          folder2extract = corr_data.SPONsubset;
        case "SPIN"
            folder2extract = corr_data.STIM;
    end
end

dispt = toc;
disp(strcat("Done calculating. Time elapsed: ", num2str(dispt)))
clear dispt


%% Section 6: Now extract movies from either SPON or STIM

% data_type = 0;
if target_file=='movReg.bin'
    motion_corrected=1;
elseif target_file=='Sq_camera.bin'
    motion_corrected=0;
end
savedfiles = [];

disp('Extracting movies and saving as .tif files...')
for z = 1:length(folder2extract)
    if condition=="SPON" && data_type==1
        upperlim = 1:double(folder2extract(z,2)); % all cells
    elseif condition=="STIM" && data_type==1
        upperlim = double(folder2extract(z,2)); % single cell number
    elseif data_type==0
        upperlim = double(folder2extract(z,2)); % single cell number
    end
    
    for k = upperlim
        % edit file names accordingly
        animalID = extractBetween(folder2extract(z,1), parent_path, '/2');
        sessID = extractBetween(folder2extract(z,1), regexp(folder2extract(z,1), 'FOV\d+/','match'), '/mov');
        FOV = extract(folder2extract(z,1), regexp(folder2extract(z,1), 'FOV\d+','match'));
        file_name_FOV = sprintf('%s_%s_%s_%s.tif', animalID, FOV, sessID, num2str(k)); % last number is the cell #
        file_path_FOV = fullfile(save_mov_path,file_name_FOV);

        if ~isfile(file_path_FOV)
            tmp = extractBefore(folder2extract(z,1), "/movReg.bin");
            cd(tmp)
            fid = fopen('experimental_parameters.txt', 'r');
            Info = textscan(fid, '%s');
            fclose(fid);
            if motion_corrected
                ncol = str2double(Info{1}{6});
                nrow = str2double(Info{1}{3});
            else
                nrow = str2double(Info{1}{6});
                ncol = str2double(Info{1}{3});
            end
            [mov, nframes] = readBinMov(folder2extract(z,1), nrow, ncol);

            if data_type == 0 && test_maskmov == 0
                mov = double(mov);
                options.big = true;
                saveastiff(mov, file_path_FOV, options);
            else
                MaskMov = splitMOV(mov, tmp, condition, data_type, nframes, sel_nframes, ...
                    Info, motion_corrected, k, nrow, ncol);
                saveastiff(MaskMov, file_path_FOV);
                savedfiles = [savedfiles; folder2extract(z,1)];
            end
        else
            fprintf('Skipping saved file: %s\n', file_path_FOV);
            % savedfiles = [savedfiles; folder2extract(z,:)];
        end
    end
end

cd(save_mov_path)
save("dataset_paths", "folder2extract", "corr_data", "savedfiles")

%% Functions

% Calculates how many cells are present in each .bin file
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
% based off of apply_mask_RMmov_BkgSel_FanLab.m
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

% Function to find starting index when extracting training movies
function starting_idx = find_start_I(tmp, condition, nframes, sel_nframes)
    switch condition
        case "SPON"
            starting_idx = int16(rand * (nframes-sel_nframes));
        case "STIM"
            if contains(tmp,'estep','IgnoreCase',true)
                starting_idx = int16((1000 * randi([0 11]))+1);
            elseif contains(tmp,'spon','IgnoreCase',true)
                int_AI = load('AI Data');
                idx = unique(round(find(int_AI(5,:)>0.5)/10)); % dividing by 10 and rounding bc the AI Data sampling rate is 10x more than framerate
                stim_gap = find(diff(idx)~=1); % break between stimulations             
                num_stim = length(stim_gap) + 1; % number of total stimulation events
                stim_onset = [min(idx), idx(stim_gap + 1)]; % start of stimulation events
                stim_end = [idx(stim_gap), max(idx)]; % end of stimulation events
                stimi = randi(num_stim); % pick a random stimulation event to data_type from for training movie
                length_stim = stim_end(stimi) - stim_onset(stimi); % length of stimulation
                                
                if length_stim<=500 % most likely for SponAO recordings
                    % take the midpoint of the stimulation and have movie go 500ms before and after
                    mid = round((stim_end(stimi) + stim_onset(stimi))/2);
                    if mid<501; starting_idx=1; else; starting_idx = mid-500; end
                elseif length_stim>500 % including this just in case, to avoid error
                    % choose either the beginning or end of stimulation and take 500ms of stim + 500ms of nonstim
                    tf=randi([0 1]); % choose either beginning or end of stim
                    if tf==1 % beginning of stim
                        % if the beginning of stimulation is too close to the time=0 to get 500ms before stim, just take the end of stimulation
                        if stim_onset(stimi)>=501; starting_idx = stim_onset(stimi)-500; else; starting_idx = stim_end(stimi)-500; end
                    elseif tf==0 % end of stim
                        % if the end of stimualtion is too close to end of recording, to get 500ms after stim, just take the beginning of the stim
                        if stim_end(stimi)+500 > length(int_AI)/10 % if the end of stim is too close to the end of recording, take beginning of stim
                            starting_idx = stim_onset(stimi)-500;
                        elseif stim_end(stimi)+500 < length(int_AI)/10 % otherwise, take the end of stim as planned
                            starting_idx = stim_onset(stimi)-500;
                        end
                    end
                end
            end
    end
end


% Function to split into MaskMov if extracting training movies OR if
% separating testing movies into cell-specific movies
function MaskMov = splitMOV(mov, tmp, condition, data_type, nframes, sel_nframes, Info, motion_corrected, k, nrow, ncol)
    if data_type==1 % training data
        starting_idx = find_start_I(tmp, condition, nframes, sel_nframes);
        starting_idx = round(starting_idx);
        mov_part = double(mov(:, :, starting_idx:starting_idx+sel_nframes-1));
    elseif data_type==0 % testing data
        mov_part = double(mov); 
    end
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
    %mov2 = mov_part - repmat(reshape(sbkg,[1,1,nframes]),[nrow, ncol,1]);
    
    x1 = roimask{k}(:,2);
    y1 = roimask{k}(:,1); edge = 5;
    X1 = ceil(min(x1))-edge; if X1<1, X1=1; end
    X2 = floor(max(x1))+edge; if X2>nrow, X2=nrow; end
    Y1 = ceil(min(y1))-edge; if Y1<1, Y1=1; end
    Y2 = floor(max(y1))+edge; if Y2>ncol, Y2=ncol; end
    MaskMov = mov_part(X1:X2,Y1:Y2,:);
end
