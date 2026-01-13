% batch_preprocess.m
% copy of preprocess integrated with support for denoising
% EW 01/08/2025 based on KS 5/20/2025
% Based on Linlin Fan Scripts:
% 0) SUPPORT
% 1) Motion Correction - Ru n_dir_mov_RMCorre.m
% 2) ICA/PCA - Run_dir_PCA_ICA_RMmov.m
% 3) Spike Thresholding - Run_dir_spikeT_spikeW_FOV.m

clear; close all;

%% Session & FOV Parameters
rng(123, 'twister');
% Automatically detect OS: Windows uses Z:\, macOS/Linux use /Volumes/fanlab
if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end

% defaults to applying support after motion correction
%motion_corr = 'post-motion'; % 0 if pre-motion correction, 1 if post

%% generating paths
addpath(genpath(fullfile(root_path,'Labmembers','Kohl','Code')));
addpath(genpath(fullfile(root_path,'Labmembers','Erin','code')));
addpath(genpath(fullfile(root_path,'Computer Code','Image Processing')));
addpath(genpath(fullfile(root_path,'Computer Code','NoRmCorre')));
addpath(genpath(fullfile(root_path,'Computer Code','Fan Lab')));

%% setting directories
% custom_raw_roots = containers.Map( ...
%     {'cck-gevi-w03', 'cck-gevi-w05'}, ...
%     { fullfile(root_path,'Data and Analysis','DSI-BTSP','CCK-voltage_KS','cck-gevi-w03'), ...
%       fullfile(root_path,'Labmembers','Kohl','CCK','cck-gevi-w05') } ...
% );

% parent_root = fullfile(root_path,'Labmembers','Kohl','CCK');
path.root.data = fullfile(root_path,'Labmembers','Xingyu', 'CCK-GtACR-BTSP');
custom_raw_roots = path.root.data;
path.anim_ids = {'CCK-GtACR-BTSP-w02'};
path.sess_ids = {'2025-12-23_VR-V-Blue'};
sel_FOVs = [2];
sel_slices = [2];
animal_type = 'cck-gtacr-btsp';
exclude = {'ExpressionCheck'};

%% set which steps for preprocessing to run
prepro = [1, 1, 0, 0, 0]; % 1 if running the step, 0 if not
% 1: Motion Correction
% 2: SUPPORT (generate data for model to run)
% 3: ICA Pre
% 4: ICA Choose
% 5: Spike Thresholding
preprocessed = 0; % if haven't already analyzed raw data and is the first time preprocessing
is_stim = 1;
if is_stim; blueStim = 'AO'; else blueStim = ''; end

%% Preprocessing pipeline on sessions
total_sessions = struct([]);
% will automatically look to see if a sessions file already exists
for a = 1:numel(path.anim_ids)
    new_sessions = discover_sessions(custom_raw_roots, path.anim_ids{a}, path.root.data, preprocessed, exclude);
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
    % make metadata struct with session_path, use_support, motion_corr, is_stim
    metadata = struct('session_path', session_path, 'use_support', prepro(2), 'is_stim', is_stim, 'blueStim', blueStim);
    fprintf('Processing session: %s\n', session_path);
    if prepro(2); save_dir = fullfile(session_path, 'support'); else; save_dir = session_path; end % Set subdir_path for processing

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
            if ~isvarname('movReg')
                Info = textscan(fopen(fullfile(session_path,'experimental_parameters.txt')),'%s');
                nrow = str2num(Info{1,1}{6,1}); ncol = str2num(Info{1,1}{3,1});
                binName = 'movReg.bin';
                [movReg, nframes] = readBinMov(binName, ncol, nrow);
            end
            mov = double(mov);
            options.big = true;
            saveastiff(mov, raw_tiff, options);
        end
    end
end

%% continue after SUPPORT has inferenced on raw data
for s = 1:numel(sel_sessions) 
    %% ICA
    if any(prepro(3:4))
        if prepro(2) && ~isfile(fullfile(session_path, 'support', 'denoised.tiff'))
            continue;
        else
            try
                %ICA Pre
                if prepro(3) && ~isfile(fullfile(save_dir,'ICA_PreResults.mat'))
                    disp("Running ICA_Pre")
                    ICA_Pre_support(metadata);
                end
        
                %ICA Choose
        
                if prepro(4) && isfile(fullfile(save_dir,'ICA_PreResults.mat')) && ~isfile(fullfile(save_dir,'Fig_intens_ICA.fig'))
                    disp("Running ICA_Choose")
                    ICA_Choose_support(metadata);
                end
                fprintf('Success: %s\n', session_path);
            catch ME
                fprintf('Failed: %s\nError: %s\n', session_path, ME.message);
            end
        end
        close all;
    end

    %% Spike Thresholding
    if prepro(5)
        if isfile(fullfile(save_dir,'Masks_BestIcaImgs.mat')) && ~isfile(fullfile(save_dir,'inter_spikeT_spikeW.mat'))
            disp("Running Spike Thresholding")
            try    
                openfig(fullfile(save_dir, 'Fig_intens_ICA.fig'));
                set(gcf, 'Units', 'Normalized', 'OuterPosition', [0 0 1 1]);
    
    
                Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_erin(metadata); 
    
                disp(['success at ', session_path]);
                close all
            catch ME
                disp(['fail at ', session_path]);
            end
        end
    end
end

%% plot for sfn poster - Raw Voltage + Velocity per Cell

%Plotting parameters
is_scalebar = 1;
traceColor = [1 0.549 0.549];
spike_scale_factor = 0.5;
vel_scale_factor = 3/50;

%Get Example Sessions
for i = 1:numel(sessions)
    sessions(i).fr_ratio = sessions(i).fr_run / sessions(i).fr_still;
    sessions(i).mean_run_speed = nanmean(sessions(i).beh.vel)*100;%for scaling
    sessions(i).run_time = nansum(sessions(i).beh.run);
    sessions(i).still_time = nansum(sessions(i).beh.still);
end
sessions = table2struct(sortrows(struct2table(sessions),  {'mean_run_speed','snr'}, {'descend','descend'}));
%Good Sessions but from same cells: '173040_Spon30','170640_Spon30','110145_Spon30','182420_Spon30','173544_Spon30'
sess_ids = {'173002_Spon30','105118_Spon30','165640_Spon30','174802_Spon30'};
sess_fig = sessions(ismember({sessions.session_name},sess_ids));
sessions = table2struct(sortrows(struct2table(sessions),  {'cell_hash'}, {'descend'}));
num_cells = length(unique({sess_fig.cell_hash}));
if num_cells <length(sess_fig)
    fprintf('Find unique cells\n');
end

figure('Position', [100, 100, 2000, 800]);hold on;
for i = 1:length(sess_fig)
    sess = sess_fig(i);

    %Plot Velocity
    vel = sess.beh.vel;
    vel = movmean(vel, 1000);
    vel = (vel-min(vel))*vel_scale_factor;
    plot(sess.beh.ts,vel+(2*i-2),'k','LineWidth',1);

    %Plot Raw Trace
    trace = sess.sub_t.norm.NormIntens;
    trace = (trace-median(trace))*spike_scale_factor;
    plot(sess.spik.ts,trace+(2*i-1),'Color',traceColor,'LineWidth',1.5);

    %text(0,2*i-1,sess.session_name,'Interpreter','none');

end
ylim([-1 2*length(sess_fig)]);
xlabel('Time (s)');

if is_scalebar
    tSec = 5;           % 1-second horizontal bar
    ampVel = 1*10;    % vertical size (in spike height)
    ampTr  = 1;    % vertical size (in cm/s)

    ax = gca; hold on;
    Fs   = 1000;        % Hz  <-- set this to your actual sampling rate
    dx   = max(1, round(tSec*Fs));   % width in samples

    % Axis limits and placement
    xl = xlim(ax); yl = ylim(ax);
    xr0 = xl(1) + 0.02*range(xl);      % left margin
    xr1 = xr0+tSec;%min(xr0 + dx, xl(2) - 1);    % ensure it fits in view

    % Place two bars near the bottom; adjust the y positions as you like
    y0_vel = yl(1) + 0.06*range(yl);   % speed scalebar baseline
    y0_tr  = y0_vel + yl(2)-1.85;             % trace scalebar baseline (stacked above)
    %y0_tr = y0_vel + 0.15 * range(yl); 
    

    % Speed scalebar (black),  s × 1 a.u.
    plot([xr0 xr0], [y0_vel y0_vel+ampVel*vel_scale_factor], 'k', 'LineWidth', 1.5);   % vertical
    plot([xr0 xr1], [y0_vel y0_vel],       'k', 'LineWidth', 1.5);     % horizontal
    text((xr0+xr1)/2, y0_vel - 0.01*range(yl), sprintf('%d s',tSec),'HorizontalAlignment','center', 'VerticalAlignment','top');
    text(xr0 - 0.01*range(xl), y0_vel + (ampVel*vel_scale_factor)/2, sprintf('%d cm/s',ampVel),'Rotation',90, 'HorizontalAlignment','center', 'VerticalAlignment','middle');

    plot([xr0 xr0], [y0_tr y0_tr+ampTr*spike_scale_factor], 'Color', traceColor, 'LineWidth', 1.5);
    plot([xr0 xr1], [y0_tr y0_tr],       'Color', traceColor, 'LineWidth', 1.5);
    text((xr0+xr1)/2, y0_tr - 0.005*range(yl), sprintf('%d s',tSec),'HorizontalAlignment','center', 'VerticalAlignment','top','Color', traceColor);
    text(xr0 - 0.011*range(xl), y0_tr + (ampTr*spike_scale_factor)/2, sprintf('%d%% Spike\nHeight',ampTr*100), 'Rotation',90, 'HorizontalAlignment','center', 'VerticalAlignment','middle','Color', traceColor);

end
title('Voltage imaging of CA1 CCKBCs cells during VR behavior','FontSize',18);

% Save
path.save.example = fullfile(path.save_dir,'CCKBC Firing Examples');
mkdir(path.save.example);
saveas(gcf(), fullfile(path.save.example, sprintf('CCKBC_Firing_Examples.png')));
saveas(gcf(), fullfile(path.save.example, sprintf('CCKBC_Firing_Examples.fig')));
saveas(gcf(), fullfile(path.save.example, sprintf('CCKBC_Firing_Examples.svg')));
%% loading data for analysis
%%% preparing data
sessions_raw = load(fullfile(root_path, 'Labmembers', 'Kohl', 'CCK', 'CCKBC GEVI Analysis','sessions_test.mat'),'sessions');
sessions_support = load(fullfile(root_path, 'Labmembers', 'Kohl', 'Support','cck-gevi','dataset', 'output','pre-motion','sessions.mat'),'sessions');
% Convert paths in loaded sessions structs to match current OS (but don't save)
sessions_raw.sessions = convert_struct_paths(sessions_raw.sessions, root_path);
sessions_support.sessions = convert_struct_paths(sessions_support.sessions, root_path);
% keep only the ones where session_name are the same
names_support = {sessions_support.sessions.session_name};
names_raw = {sessions_raw.sessions.session_name};
[common_names, idx_support, idx_raw] = intersect(names_support, names_raw);
% 
aligned_support = sessions_support.sessions(idx_support);
aligned_raw = sessions_raw.sessions(idx_raw); 

%% Plotting
% SNR raw vs SUPPORT
snr_support = cat(1, aligned_support.snr);
snr_raw = cat(1, aligned_raw.snr);

snr_support_all = snr_support(:);
snr_raw_all = snr_raw(:);
figure;
scatter(snr_raw_all, snr_support_all, 25, 'filled', 'MarkerFaceAlpha', 0.6);
hold on;
xlabel('Raw SNR');
ylabel('Support SNR');
title('SNR: SUPPORT vs undenoised');

lims = [min([snr_raw_all; snr_support_all;]), max([snr_raw_all; snr_support_all;])];
coeffs = polyfit(snr_raw_all, snr_support_all, 1);
x_fit = linspace(lims(1), lims(2), 100);
y_fit = polyval(coeffs, x_fit);
plot(x_fit, y_fit, 'b-', 'LineWidth', 1.5);
plot(lims, lims, 'r--', 'LineWidth', 1);
axis square;
grid on;
[~, p] = ttest(snr_support_all, snr_raw_all);
text(mean(lims), lims(2) - 0.05*(lims(2)-lims(1)), sprintf('p = %.3g', p), ...
    'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');
saveas(gcf(), fullfile(path.save_dir, sprintf('SNR support vs undenoised.png')));

% Firing rate raw vs SUPPORT
fr_support = cat(1, aligned_support.fr);
fr_raw = cat(1, aligned_raw.fr);

fr_support_all = fr_support(:);
fr_raw_all = fr_raw(:);

figure;
scatter(fr_raw_all, fr_support_all, 25, 'filled', 'MarkerFaceAlpha', 0.6);
hold on;
xlabel('Raw FR');
ylabel('Support FR');
title('FR: SUPPORT vs undenoised');

lims = [min([fr_raw_all; fr_support_all;]), max([fr_raw_all; fr_support_all;])];
coeffs = polyfit(fr_raw_all, fr_support_all, 1);
x_fit = linspace(lims(1), lims(2), 100);
y_fit = polyval(coeffs, x_fit);
plot(x_fit, y_fit, 'b-', 'LineWidth', 1.5);
plot(lims, lims, 'r--', 'LineWidth', 1);
axis square;
grid on;
[~, p] = ttest(fr_support_all, fr_raw_all);
text(mean(lims), lims(2) - 0.05*(lims(2)-lims(1)), sprintf('p = %.3g', p), ...
    'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');
saveas(gcf(), fullfile(path.save_dir, sprintf('FR support vs undenoised.png')));

% change in number of spikes vs SNR
delta_spikes = [aligned_support.nspikes] - [aligned_raw.nspikes];
figure;
scatter(snr_raw_all, delta_spikes, 25, 'filled', 'MarkerFaceAlpha', 0.6);
hold on;
xlabel('Raw SNR');
ylabel('Change in nspikes');
title('Change in nspikes vs Raw SNR');
saveas(gcf(), fullfile(path.save_dir, sprintf('change in spiking.png')));
