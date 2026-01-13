%% reset
clear; close all;
rng(123);
%% Setup
% Automatically detect OS: Windows uses Z:\, macOS/Linux use /Volumes/fanlab
if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end

%motion_corr = 'post-motion'; 
dataset_type = 'test';
%% generating paths
addpath(genpath(fullfile(root_path,'Labmembers','Kohl','Code')));
addpath(genpath(fullfile(root_path,'Labmembers','Erin','code')));
addpath(genpath(fullfile(root_path,'Computer Code','Image Processing')));
addpath(genpath(fullfile(root_path,'Computer Code','NoRmCorre')));
addpath(genpath(fullfile(root_path,'Computer Code','Fan Lab')));

%% set paths to data
%path.root.support = fullfile(sprintf(root_path), 'Labmembers', 'Erin', 'support_data');
path.root.data = fullfile(root_path, 'Labmembers', 'Xingyu', 'CCK-GtACR-BTSP');
%path.root.kohl_data = fullfile(sprintf(root_path), 'Labmembers', 'Kohl', 'CCK');
%path.root.other_data = fullfile(sprintf(root_path), 'Data and Analysis', 'DSI-BTSP', 'CCK-voltage_KS');

path.root.sess = {path.root.data};
%{path.root.other_data, path.root.other_data, path.root.other_data, path.root.other_data, path.root.other_data,path.root.kohl_data,path.root.kohl_data,path.root.kohl_data,path.root.kohl_data};
path.anim_ids = {'CCK-GtACR-BTSP-w02'};
%{'cck-gevi-w03','cck-gevi-w03','cck-gevi-w03','cck-gevi-w03','cck-gevi-w03', 'cck-gevi-w05','cck-gevi-w05','cck-gevi-w05','cck-gevi-w05'};
path.sess_ids = {'2025-12-23_VR-V-Blue'};
%{'2025-03-27 voltage recording during vr','2025-04-22 voltage record move stop','2025-05-01 voltage during VR','2025-05-07 voltage during VR','2025-05-16 voltage during VR','Running9_15_2025','Running9_19_2025','Running9_23_2025','Running9_26_2025'};
animal_prep = 'cck-gtacr-btsp';
%sel_FOVs = [2];
%sel_slices = [2];
%waveform_stim = {'Spon30', 'EStepV5'};
path.data_dir = path.root.data; %fullfile(path.root.kohl_data,'CCKBC GEVI Analysis');
%path.save_dir = fullfile(path.root.support, animal_prep);%'cck-gevi', 'dataset', 'test', 'post-motion');%'test');
%if ~exist(path.save_dir); [~,~] = mkdir(path.save_dir); end

%load(fullfile(path.data_dir,'sessions_test.mat'),'sessions');

%% setup sessions structure
discovered_sessions = discover_sessions(path.data_dir, animal_prep, path.data_dir, 1);
discovered_sessions = convert_struct_paths(discovered_sessions, root_path);
sessions = discovered_sessions;
%sessions = generate_sessions_struct(discovered_sessions, path, sel_FOVs, sel_slices);

% filter to only include unique sessions, based on session_name
session_names = {sessions.session_name};
[~, unique_idx, ~] = unique(session_names, 'stable');
sessions = sessions(unique_idx);

% save session paths to json file for python to use (as a list)
session_paths = {sessions.session_path};
session_paths_list = sprintf('%s\n', session_paths{:});
fid = fopen(fullfile(path.data_dir,'sessions_for_support.txt'), 'w'); % path.anim_ids{1}, path.sess_ids{1}, 
fwrite(fid, session_paths_list, 'char');
fclose(fid);

%% decided on post motion correction (used to test before or after motion correction)
% if contains(motion_corr, 'pre'); motion_corrected = 0; else; motion_corrected = 1; end
% if motion_corrected; target_file = 'movReg.bin'; else; target_file = 'Sq_camera.bin'; end

target_file = 'movReg.bin';
%% Saving Samples of Masked Recordings
if contains(dataset_type, 'test'); sample = 0; else if contains(dataset_type, 'train'); sample = 1; else; sample = 0; end; end
sel_nframes = 2000;

for sess_i = 1:length(sessions)
    path_to_sess = fullfile(sessions(sess_i).session_path);
    cd(path_to_sess)
    hash_id = sessions(sess_i).cell_hash;
    sess_name = sessions(sess_i).session_name;
    % later remove this, move train to another script (more user friendly)
    if sample; file_path = fullfile(path.save_dir, 'train', sprintf("%s_%s", hash_id, sess_name));
    else; file_path = fullfile(path_to_sess, 'support', 'raw.tiff');
    end
    if ~isfile(file_path)
        target = fullfile(path_to_sess, target_file);
        fid = fopen(fullfile(path_to_sess,'experimental_parameters.txt'), 'r');
        Info = textscan(fid, '%s');
        fclose(fid);
        if motion_corrected;
            ncol = str2double(Info{1}{6});
            nrow = str2double(Info{1}{3});
        else
            nrow = str2double(Info{1}{6});
            ncol = str2double(Info{1}{3});
        end
        [mov, nframes] = readBinMov(target, nrow, ncol);
        
        if sample == 0
            mov = double(mov);
            options.big = true;
            saveastiff(mov, file_path, options);
        else
            starting_idx = int16(rand * (nframes-sel_nframes));
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
            
            i = sessions(sess_i).cell_id;
            x1 = roimask{i}(:,2);
            y1 = roimask{i}(:,1); edge = 5;
            X1 = ceil(min(x1))-edge; if X1<1, X1=1; end
            X2 = floor(max(x1))+edge; if X2>nrow, X2=nrow; end
            Y1 = ceil(min(y1))-edge; if Y1<1, Y1=1; end
            Y2 = floor(max(y1))+edge; if Y2>ncol, Y2=ncol; end
            MaskMov = mov_part(X1:X2,Y1:Y2,:);
            [rows, cols, time] = size(MaskMov);
            sessions(sess_i).nrows = rows; sessions(sess_i).ncols = cols;
            %paddedMov = padarray(MaskMov, [floor((max_row - size(MaskMov, 1))/2), floor((max_col - size(MaskMov, 2))/2)],'replicate', "both");
            %if rows > max_row; max_row = rows; end
            %if cols > max_col; max_col = cols; end
            saveastiff(MaskMov, file_path);
        end
    else; fprintf('Skipping saved file: %s\n', file_path);
    end
end
%save(fullfile(path.root.support, 'cck-gevi', 'sessions_modified.mat'), "sessions")
%sprintf("Max rows: %d, Max cols: %d", max_row, max_col)

%% Functions
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
