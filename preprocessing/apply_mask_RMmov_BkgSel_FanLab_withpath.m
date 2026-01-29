function [Fmasks,ROImask]=apply_mask_RMmov_BkgSel_FanLab_withpath(mov, mov_path, mask_title)
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

Fmasks=apply_clicky(ROImask,double(mov), 'yes', mask_title);
end

% modified apply_clicky function to include title
function intens = apply_clicky(roi, movie_in, disp_img, mask_title)
% function intens = apply_clicky(roi, movie_in, disp_img)
% Applies an ROI to a movie_in and returns the intensities at those
% locations.  To display the average image and to plot the intensity trace, set disp_image to 'yes'.  
% To not display the image, but just return the intesities,
% set the disp_img variable to 'No'.  Default disp_img is yes.
%
% Created: 10/16/11 by AEC and JMK
% 11/4/11: JMK added option to display images
%
% 1/8/2017 SLF changes: tovec of movie_in alternative itrace calculation
% to speed up function.
%

if nargin == 2
    disp_img = 'yes';
else
    disp_img = lower(disp_img);
end

[~,nroi] = size(roi);

switch disp_img
    case 'yes'
        nframes = size(movie_in, 3);
        refimg = mean(movie_in, 3);
        movie_in = tovec(movie_in);
        [ysize, xsize] = size(refimg);

        figure
        subplot(1,3,1)
        imshow(refimg, [], 'InitialMagnification', 'fit')
        hold on;
        if isempty(mask_title)
            mask_title = 'Masked ROIs and Intensity Traces';
        end
        title(mask_title);
        
        intens = zeros(nframes, nroi);
        
        
        
        colorindex = 0;
        order = get(gca,'ColorOrder');
        [x, y] = meshgrid(1:xsize, 1:ysize);
        for j = 1:nroi
            xv = roi{j}(:,1);
            yv = roi{j}(:,2);
            inpoly = inpolygon(x,y,xv,yv);
            
            subplot(1,3,1)
            %draw the bounding polygons and label them
            currcolor = order(1+mod(colorindex,size(order,1)),:);
            plot(xv, yv, 'Linewidth', 1,'Color',currcolor);
            text(mean(xv),mean(yv),num2str(colorindex+1),'Color',currcolor,'FontSize',12);
            
%             itrace = squeeze(sum(sum(movie_in.*repmat(inpoly, [1, 1, nframes]))))/sum(inpoly(:));
            itrace = mean(movie_in(inpoly,:))';
            
            
            subplot(1,3,2:3) % plot the trace
            hold on;
            plot(itrace,'Color',currcolor);
            colorindex = colorindex+1;
            
            intens(:,j) = itrace;
        end
        hold off
        
    case 'no'
        [ysize, xsize, nframes] = size(movie_in);
        intens = zeros(nframes, nroi);
        [x, y] = meshgrid(1:xsize, 1:ysize);

        movie_in = tovec(movie_in);
        title(mask_title);
        for j = 1:nroi;
            xv = roi{j}(:,1);
            yv = roi{j}(:,2);
            inpoly = inpolygon(x,y,xv,yv);
            
%             itrace = squeeze(sum(sum(movie_in.*repmat(inpoly, [1, 1, nframes]))))/sum(inpoly(:));
            itrace = mean(movie_in(inpoly,:))';
            intens(:,j) = itrace;
        end
end
end





