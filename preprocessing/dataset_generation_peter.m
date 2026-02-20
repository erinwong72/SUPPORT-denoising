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
dataset_type = 'testing';
%% generating paths
if ~tinkering
    code_path = fullfile(root_path,'Computer Code');
else
    code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
end

% Don't have to change this path: this is a NEW session struct (kohl did some reorganizing so some of the
% paths are different and there are more sessions, should be 322 when you
% load it)
S = load(fullfile(root_path, "Labmembers", "Kohl", "CCK", "sessions_cck-gevi_inventory_020526.mat"));
sessions = S.sessions;
nsessions = length(sessions);

fprintf("Sessions successfully loaded.\n");

addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'));
addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));
safe_addpath(fullfile(root_path, 'Computer Code', 'DLab', 'RMCorre', 'NoRMCorre-master'))

% just change this part to where you want tiffs to be saved
path.save_dir = fullfile(root_path, "Labmembers", "Erin", "support_data", "cck-gevi", "test_for_peter");

%% Saving Samples of Masked Recordings
target_file = 'movReg.bin';
if contains(dataset_type, 'test'); sample = 0; elseif contains(dataset_type, 'train'); sample = 1; else; sample = 0; end;
if sample; sel_nframes = ceil(300000/nsessions); end % selecting enough to make a 300,000 frame dataset

for sess_i = 1:length(sessions)
    fprintf('Processing session %d of %d\n', sess_i, length(sessions));
    % print statement that allows you to see which session is being
    % processed

    path_to_sess = char(fullfile(sessions(sess_i).session_path));
    try % sometimes path doesn't exist
        cd(path_to_sess);
    catch
        fprintf('Skipping missing session path: %s\n', path_to_sess);
        continue;
    end
    anim_id = sessions(sess_i).anim_id;
    sess_path = sessions(sess_i).session_path;
    path_parts = strsplit(sess_path, filesep);
    date = path_parts{end-3};
    filename = anim_id + "_" + date + "_" + sprintf("FOV%d", sessions(sess_i).FOV) + "_" + ".tiff";
    file_path = fullfile(path.save_dir, filename);

    if ~isfile(file_path)
        target = fullfile(path_to_sess, target_file);
        fid = fopen(fullfile(path_to_sess,'experimental_parameters.txt'), 'r');
        Info = textscan(fid, '%s');
        fclose(fid);
        
        % testing
        if strcmp(dataset_type,'testing')
            Info = textscan(fopen(fullfile(path_to_sess,'experimental_parameters.txt')),'%s');
            nrow = str2double(Info{1}{6});
            ncol = str2double(Info{1}{3});
            [movReg,~] = readBinMov(fullfile(path_to_sess,'movReg.bin'),ncol,nrow);
            opts.overwrite = true; opts.big = true;
            saveastiff(movReg, char(file_path), opts);
            % sanity check open up the tiff (showing 10th frame of movie)
            imshow(movReg(:,:,10), []); % after you've checked that one works I'd comment this out 
                                        % bc it will take a long time if you visualize each one
                   
        elseif strcmp(dataset_type, "training")
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
end


fprintf("End of script reached!!.\n");
%% Functions
% copied from apply_mask_RMmov_BkgSel_FanLab.m

%{
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
%}