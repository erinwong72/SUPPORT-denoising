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

tinkering = 1; % if editing in labmembers directory before pushing changes
%motion_corr = 'post-motion'; 
%dataset_type = 'train';
%% generating paths
if ~tinkering
    code_path = fullfile(root_path,'Computer Code');
else
    code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
end
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));
safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));
%% set paths to data
% look through all of these parent folders for sessions
path.root.data = {fullfile(root_path, 'Labmembers', 'Kohl', 'CCK'), ...
                  fullfile(root_path, 'Labmembers', 'Xingyu', 'CCK-GtACR-BTSP')};
path.cell_type = fullfile(code_path, 'SUPPORT-denoising', 'datasets', 'PC');
custom_raw_roots = path.root.data;

% TODO add functionality to select specific animals/sessions
path.anim_ids = {};
path.sess_ids = {};
sel_FOVs = [];
sel_slices = [];
animal_type = '';
exclude = {'Expression', 'nobeh', 'CCKBC', 'cck-gevi', 'wkEC', 'check'};
min_spikes = 0; 
snr_min = 5;
saveStr = sprintf("minSNR_%d", snr_min);
path.save_dir = fullfile(path.cell_type, saveStr);
%% setup sessions structure
if ~exist(path.save_dir, 'dir')
    mkdir(path.save_dir); end
if exist(fullfile(path.cell_type, sprintf("total_sessions_%s.mat", saveStr)), 'file')
    load(fullfile(path.cell_type, sprintf("total_sessions_%s.mat", saveStr)), 'total_sessions');
else
    total_sessions = struct([]);
    % skip any directories that contain the strings in exclude
    skip_func = @(folder) any( ...
        cellfun(@(e) contains(folder, e, 'IgnoreCase', true), exclude) ...
    );
    % finding all analyzed data to filter for fr, snr, etc.
    all_matching_files = fsfind(path.root.data, 'sessions\.mat', Depth=5, SkipFolderFcn=skip_func);
    % get rid of duplicates
    all_matching_files = unique(all_matching_files);
    for file_i = 1:length(all_matching_files)
        sess_path = all_matching_files{file_i};
        loaded_sess = load(sess_path, 'sessions');
        % only keep certain fields
        keep_fields = {'anim_id','session_path','session_name','FOV','cell_id','fov_num_cells','cell_hash', 'fr', 'snr', 'nspikes'};
        sess_struct = loaded_sess.sessions;
        sess_struct = rmfield(sess_struct, setdiff(fieldnames(sess_struct), keep_fields));
        total_sessions = [total_sessions, sess_struct]; %#ok<AGROW>
    end
    remove_fields = {'fr', 'snr', 'nspikes'};
    total_sessions = curateSessions(total_sessions, min_spikes, snr_min, true, remove_fields);
    total_sessions = convert_struct_paths(total_sessions, root_path);
    % make sure each session_path exists
    valid_paths = arrayfun(@(s) isfolder(s.session_path), total_sessions);
    total_sessions = total_sessions(valid_paths);
    % keep sessions with unique session_paths
    save(fullfile(path.cell_type, sprintf("total_sessions_%s.mat", saveStr)), 'total_sessions');
end
%% filter total sessions
nsessions = 350; %number of sessions to randomly keep
if length(total_sessions) > nsessions
    rand_indices = randperm(length(total_sessions), nsessions);
    total_sessions = total_sessions(rand_indices);
end

save(fullfile(path.cell_type, 'dataset_sessions.mat'), 'total_sessions');
dataset_sessions = total_sessions;
sessions = convert_struct_paths(dataset_sessions, root_path);
nsessions = length(sessions);
% decided on post motion correction (used to test before or after motion correction)

%% Saving Samples of Masked Recordings
target_file = 'movReg.bin';
%if contains(dataset_type, 'test'); sample = 0; else if contains(dataset_type, 'train'); sample = 1; else; sample = 0; end; end
sel_nframes = ceil(300000/nsessions); % selecting enough to make a 300,000 frame dataset

for sess_i = 1:length(sessions)
    path_to_sess = char(fullfile(sessions(sess_i).session_path));
    try % sometimes path doesn't exist
        cd(path_to_sess);
    catch
        fprintf('Skipping missing session path: %s\n', path_to_sess);
        continue;
    end
    hash_id = sessions(sess_i).cell_hash;
    sess_name = sessions(sess_i).session_name;
    sess_id = strsplit(sess_name, '_');
    sess_id = sess_id{1};
    filename = hash_id + "_" + sess_id + ".tiff";
    file_path = fullfile(path.save_dir, filename);
    if ~isfile(file_path)
        target = fullfile(path_to_sess, target_file);
        fid = fopen(fullfile(path_to_sess,'experimental_parameters.txt'), 'r');
        Info = textscan(fid, '%s');
        fclose(fid);
        ncol = str2double(Info{1}{6});
        nrow = str2double(Info{1}{3});
        [mov, nframes] = readBinMov(target, nrow, ncol);
        
        starting_idx = int16(rand * (nframes-sel_nframes));
        mov_part = double(mov(:, :, starting_idx:starting_idx+sel_nframes-1));
        nframes = size(mov_part, 3);
        [Fmasks, roimask] = apply_mask_RMmov_BkgSel_nodisp(mov_part, Info);
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
        options.big = true;
        saveastiff(MaskMov, char(file_path), options);
    else; fprintf('Skipping saved file: %s\n', file_path);
    end
end
%save(fullfile(path.root.support, 'cck-gevi', 'sessions_modified.mat'), "sessions")
%sprintf("Max rows: %d, Max cols: %d", max_row, max_col)

%% Functions
% copied from apply_mask_RMmov_BkgSel_FanLab.m
function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_nodisp(mov, info)
path = cd;
xoffset = str2num(info{1,1}{33,1})-288; yoffset = str2num(info{1,1}{30,1})-288;
cd('../'); load Masks; cd(path);%load EVmask; cd(path);
num_masks=length(pts_list);
ROI=cell(1,num_masks);
for i=1:num_masks
    x1=pts_list{i}(:,2)/2-xoffset; y1=pts_list{i}(:,1)/2-yoffset;
    ROImask{i}=[x1,y1];
end

xbk=[1;30;30;1;1]; ybk = [1;1;30;30;1] + 0;
ROImask{num_masks+1} = [xbk,ybk];

Fmasks=apply_clicky(ROImask,double(mov), 'no');
end
