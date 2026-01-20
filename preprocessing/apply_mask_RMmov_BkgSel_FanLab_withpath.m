function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_FanLab_withpath(mov, mov_path)
Info=textscan(fopen(fullfile(mov_path, 'experimental_parameters.txt')),'%s');
xoffset = str2num(Info{1,1}{33,1})-288; % assuming mask was clicked on the central quad 2x2 binning - 256 --> 288 576/2
yoffset = str2num(Info{1,1}{30,1})-288; % assuming mask was clicked on the central quad 2x2 binning - 256 --> 288 
%cd('../'); load Masks; cd(path);%load EVmask; cd(path);
parent_dir = fileparts(mov_path);
mask_path = fullfile(parent_dir, 'Masks.mat');
load(mask_path);
%sprintf(fullfile(mov_path, '../', 'Masks.mat'));
num_masks=length(pts_list);
ROI=cell(1,num_masks);
for i=1:num_masks;
    x1=pts_list{i}(:,2)/2-xoffset;
    y1=pts_list{i}(:,1)/2-yoffset;
    ROImask{i}=[x1,y1];
end

xbk=[1;30;30;1;1]; ybk = [1;1;30;30;1] + 0;
ROImask{num_masks+1} = [xbk,ybk];

Fmasks=apply_clicky(ROImask,double(mov));
end

