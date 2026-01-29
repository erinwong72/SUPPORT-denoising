%% IMPORTANT!!! Change variables/file paths at line 62 BEFORE RUNNING!

%clear
close all
clc

sort = 0; % change this to 1 if need to sort denoised files
ICA_PCA = 0; % change to 1 if you want to run ICA/PCA (instead of just calculating metrics)
metrics = 0; % change to 1 if you want to run metrics
end_idx = 2; % keep at 2 if just comparing pre/post SUPPORT
big_plot = 1; % plot all metrics in one graph (haven't verified that this works, but the option is there)
psnr_compare = 0; % plot a comparison of psnr values before and after SUPPORT

type = {'raw', 'SUPPORT'};  % keep this if plotting big plot


%% Add these to path

if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end


addpath(fullfile(root_path,"Computer Code/Fan Lab/1extract-voltage-imaging-signal/"))
addpath(fullfile(root_path,"Computer Code/Fan Lab/1extract-voltage-imaging-signal/NeuroSegmentation/"))
addpath(fullfile(root_path, "Computer Code/Fan Lab/1extract-voltage-imaging-signal/NoRMCorre-master/"))
addpath(fullfile(root_path,'Computer Code', 'SUPPORT-denoising', 'utils'));
addpath(fullfile(root_path,'Computer Code', 'SUPPORT-denoising', 'preprocessing'));
addpath(fullfile(root_path,'Computer Code', 'Image Processing'));
addpath(fullfile(root_path,'Computer Code', 'Image Processing','FastICA_25'));

%% Sort denoised data into appropriate folders  - only if necessary
% Can comment out if not needed, but it will not do anything if files are
% already sorted.

if sort
% Get names of all files
parent = '/Volumes/fanlab/Labmembers/Niveda/Testing_SPON'; % aka save_mov_path from SUPPORT_dataset_gen
cd(parent)
dirs = dir;
dir_files = [];
for i = 1:length(dirs)
    tf = isfile(dirs(i).name) && ~contains(dirs(i).name, '.mat');
    if tf; dir_files = [dir_files; convertCharsToStrings(dirs(i).name)]; disp("File sorted")
    else disp(strcat("No file found to sort"))
    end
end

% make folders & store folder names in dir_folders
dir_folders = [];
for i = 1:length(dir_files)
    tmp = dir_files(i);
    if ~contains(tmp,'denoised','IgnoreCase',true)
        uniqueID = extractBefore(tmp, '.tif');
        dir_folders = [dir_folders; uniqueID];
    end
    if ~exist(uniqueID); 
        mkdir(uniqueID)
    else
        disp(strcat("Folder already exists: ",uniqueID))
    end
end

% move files if they have names matching the folder name
for i = 1:length(dir_files)
    cd(parent)
    tmp_file = dir_files(i);
    if isfile(tmp_file)
        for j = 1:length(dir_folders)
            tmp_folder = dir_folders(j);
            if contains(tmp_file, tmp_folder)
                movefile(tmp_file, tmp_folder)
            end
        end
    else
        disp(strcat("File previously sorted: ",tmp_file))
    end
end
end

%% IMPORTANT!!! Change variables here!!!

parent = '/Volumes/fanlab/Labmembers/Niveda/Testing_SPON'; % aka save_mov_path from SUPPORT_dataset_gen
cd(parent)

is_stim = 0; % logical, whether to get stimulation protocol
use_ring_bkg = 0; % 0 = background box subtraction, 1 = circular ring-based subtraction
use_support = 1;
blueStim = 'AI';
dir_folders = [];
dirs = dir;

if isempty(dir_folders)
    disp('Creating variable dir_folders, an nx1 string array of folder names inside parent directory.')
    for i = 1:length(dirs)
        if isfolder(dirs(i).name) && ~strcmp(dirs(i).name, '.') && ~strcmp(dirs(i).name, '..')
            dir_folders = [dir_folders; convertCharsToStrings(dirs(i).name)]; 
        end
    end
end

%% Double check file paths here before running!!

% session_path = where the raw data is stored (.bin file, AI Data, experimental_parameters.txt files, etc)
% denoised_path = where the denoised .tif file is stored
% save_path = where the newly computed ICA/PCA of the denoised data should be saved 

% If SUPPORT_data_gen was run, all session paths are stored in
% folder2extract, and a1ll files that were processed are stored in savedfiles

cd(parent) % directory where all denoised data is stored (even after sorting)
load('dataset_paths.mat');
cont_outer = 0;

% loop through each of the folders containing denoised data and run ICA/PCA
for i = 1:length(dir_folders)-1
    denoised_path = dir_folders(i);
        title_parts = strsplit(denoised_path, '_');
        animalID = title_parts(1);
        FOV = title_parts(2);
        session_title = strcat(title_parts(3),'_', title_parts(4));
        total_cells = double(title_parts(5));
    session_path_full = savedfiles(logical(contains(savedfiles,animalID).*contains(savedfiles,FOV).*contains(savedfiles,session_title)));
    session_path = extractBefore(session_path_full, '/movReg.bin');
    save_path = denoised_path;

    % Storing names in a new variable called sessions, which will be called many times
    sessions(i).raw_path = session_path;
    sessions(i).denoised_path = denoised_path;
    sessions(i).animalID = animalID;
    sessions(i).FOV = FOV;
    sessions(i).session_title = session_title;
    sessions(i).nCell = total_cells;

end

%% Running ICA/PCA analysis

if ICA_PCA
for sess_i = 1:length(sessions)
    % only extract information from traces that have spikes
    % use the 
    if ~exist(fullfile(sessions(sess_i).raw_path,'inter_spikeT_spikeW.mat'))
        disp("spikes not calculated for initial dataset; continuing to next file.")
        continue
    else
        load(fullfile(sessions(sess_i).raw_path,'inter_spikeT_spikeW.mat'),'C');
         for c = 1:length(C)
             sessions(sess_i).nspike(1,c) = C(c).nspike;
             spikes_tf = sum(sessions(sess_i).nspike);
             if spikes_tf==0
                 disp("no spikes detected; continuing to next file.")
                 cont_outer = 1;
                 continue
             else
                 sessions(sess_i).raw_spikes{c} = C(c).spikeT{1,1};
             end
         end
    end

    if cont_outer
        cont_outer=0;
        continue
    end

    % First run ICA/PCA and spike identification on denoised data
    [nCell, t, icsTime_all, icsTimeOrig_all, icsSpace_all, CellImgs, MaskMov] = ICA_Pre_diffpaths(session_path,denoised_path,save_path,is_stim,use_ring_bkg,use_support);
    ICA_Choose_diffpaths(session_path, denoised_path, save_path, use_support)
  %  Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_diffpaths(blueStim, session_path, denoised_path, save_path, use_support)
end
end

%% Calculate metrics

if metrics
for sess_i = 1:length(sessions)

    % extract information from traces that have spikes
    if ~exist(fullfile(sessions(sess_i).raw_path,'inter_spikeT_spikeW.mat'))
        disp("spikes not calculated for initial dataset; continuing to next file.")
        continue
    else
        load(fullfile(sessions(sess_i).raw_path,'inter_spikeT_spikeW.mat'),'C');
         for c = 1:length(C)
             sessions(sess_i).nspike(1,c) = C(c).nspike;
             spikes_tf = sum(sessions(sess_i).nspike);
             if spikes_tf==0
                 disp("no spikes detected; continuing to next cell in file.")
                 cont_outer = 1;
                 continue
             else
                 sessions(sess_i).raw_spikes{c} = C(c).spikeT{1,1};
             end
         end
    end
    if cont_outer; cont_outer=0; continue; end
    load(fullfile(sessions(sess_i).raw_path,'Masks_BestIcaTrace.mat'));
    sessions(sess_i).trace{1} = IntensOrig;
    clear C IntensOrig

    if ~exist(fullfile(sessions(sess_i).denoised_path,'Masks_BestIcaTrace.mat'))
        disp('ICA not calculated for this file. Continuing to next')
        continue
    else
        load(fullfile(sessions(sess_i).denoised_path,'Masks_BestIcaTrace.mat'));
        sessions(sess_i).trace{2} = IntensOrig;
        clear C IntensOrig
    end

  % Calculate noise level in denoised trace
    dt = 1;
    noise_region = zeros(1,sessions(sess_i).nCell);
    clear SNR
    nCell = sessions(sess_i).nCell; % total number of cells
    for k = 1:nCell % which cell's trace we're looking at
        dFTraces = sessions(sess_i).trace{2};
        trace = dFTraces(:,k);
            while true
                fig = figure('Position', [100 100 1500 600]);plot(trace,'r');
                title('Right-click to select start of baseline noise region')
                hold on;
                [x, ~] = ginput(1);
                period1 = uint16(x);
                period = [period1:period1+300];
                plot(period,trace(period),'b');
                % allow for redo
                text(double(period1), trace(period1), ...
                    ' Press any key to accept, or press "r" to redo', ...
                    'VerticalAlignment','bottom','Color','k');
                w = waitforbuttonpress;
                key = get(fig, 'CurrentCharacter');
                if lower(key) ~= 'r'
                    noise_region(k) = period1;
                    saveas(fig, fullfile(save_path, sprintf('NoiseRegion_%d_%d.png', nCell, k)));
                    savefig(fig, fullfile(save_path, sprintf('NoiseRegion_%d_%d.fig', nCell, k)));
                    close(fig);
                    break
                end
                close(fig);
            end
    end
    sessions(sess_i).noise_regions = noise_region; % save noise regions to the sessions structure

    for n = 1:sessions(sess_i).nCell
        if ~isempty(sessions(sess_i).raw_spikes)
            spike_idx = sessions(sess_i).raw_spikes{1,n}; 
        else; 
            continue
        end
        if ~isempty(spike_idx) && ~iscell(spike_idx)
            snippet_len = 500;
            waveforms = cell(end_idx, 1);
            noise_regions = sessions(sess_i).noise_regions;
            % Get valid spike indices
            trace_len = length(sessions(sess_i).trace{1}(:,n));
            valid_spikes = spike_idx(spike_idx > snippet_len & spike_idx < trace_len - snippet_len);    
                %traces_all = cell(end_idx, 1);
            for f = 1:end_idx
                trace = sessions(sess_i).trace{f}(:,n); 
                aligned = zeros(length(valid_spikes), 2*snippet_len + 1);
                for s = 1:length(valid_spikes)
                    idx = valid_spikes(s);
                    aligned(s, :) = trace(idx-snippet_len:idx+snippet_len);
                end
                mean_waveform = mean(aligned, 1);
                waveforms{f} = mean_waveform;
                spike_heights(n, f) = max(mean_waveform);
                psnrs(n, f) = 20 * log10(spike_heights(n, f) / std(trace(noise_regions(n):(noise_regions(n)+299))));
        
                % scaling traces
                maxPos = max(trace);
                scaled = trace/maxPos;
                sessions(sess_i).scaled_traces{f}(:,n) = scaled;
            end
            sessions(sess_i).spike_height{n} = spike_heights(n, :);
            sessions(sess_i).waveforms{n} = waveforms;
            sessions(sess_i).psnr{n} = psnrs(n, :);
        else
            % can scale trace, but not much else if there are no spikes in original trace
            for f = 1:end_idx
                % scaling traces
                maxPos = max(trace);
                scaled = trace/maxPos;
                sessions(sess_i).scaled_traces{f}(:,n) = scaled;
            end
            sessions(sess_i).spike_height{n} = NaN;
            sessions(sess_i).waveforms{n} = NaN;
            sessions(sess_i).psnr{n} = NaN;
        end
    end

end
end

if ~exist(fullfile(parent,'sessions.mat'))
    save(fullfile(parent, 'sessions.mat'), "sessions")
end


%% Compare Pre/Post SUPPORT PSNRs

if psnr_compare
    all_pre_psnr = [];
    all_post_psnr = [];
    for i = 1:length(sessions)
            for j = 1:length(sessions(i).psnr)
                if isempty(j) || sum(isnan(sessions(i).psnr{j})); continue; 
                else
                all_pre_psnr = [all_pre_psnr; sessions(i).psnr{j}(1)];
                all_post_psnr = [all_post_psnr; sessions(i).psnr{j}(2)];
                end
            end
    end
    % make edits if necessary
    all_post_psnr(16) = [];
    all_pre_psnr(16) = [];

    %plot
    psnr_diff = (all_post_psnr - all_pre_psnr) ./ all_pre_psnr;

    figure
    plot(all_pre_psnr, all_post_psnr, '.', 'MarkerSize',12)
    xlabel('Raw PSNR')
    ylabel('PSNR after support')
    title('Raw PSNR vs. Denoised PSNR')
    hold on
    xline = [0:24];
    yline = xline;
    plot(xline,yline, '--', Color=[0.5, 0.5, 0.5], LineWidth=2)
    fit = polyfit(all_pre_psnr, all_post_psnr,1);
    fit_y = fit(1) .* xline + fit(2);
    plot(xline, fit_y, LineWidth=2)
    hold off
    legend(["", "x = y", "1.2999x + -7.0217"])

    figure
    plot(all_pre_psnr, psnr_diff, '.', 'MarkerSize',12)
    xlabel('Raw PSNR')
    ylabel('Percent PSNR Change')
    title('Percent PSNR Change after Denoising')
    
end


%% Plotting - Big Plot

if big_plot
    fig = figure('Position', [100, 100, 1400, 900], 'Color', 'w');
for sess_i = 6 %1:length(sessions)
    i = 1; % pick a cell out of nCells

    % Top-left: traces
    figure(fig);
    subplot('Position', [0.05, 0.35, 0.7, 0.55]); hold on;
    offset = 0;  % vertical offset between traces
    for f = 1:end_idx
        if isfield(sessions(sess_i), 'scaled_traces') && ~isempty(sessions(sess_i).scaled_traces) && f <= length(sessions(sess_i).scaled_traces)
            trace = sessions(sess_i).scaled_traces{f};
        else
            trace = sessions(sess_i).trace{f}(:,i);
            maxPos = max(trace);
            trace = trace/maxPos;
        end
        if f == 1
            plot(trace + offset * (2 - f), 'k', 'LineWidth', 0.7, 'DisplayName', type{f});
        else
            % on top of for many looks unclear
            % plot(trace_0 + offset * (nEpochs - f), 'k', 'LineWidth', 0.9, 'HandleVisibility', 'off');
            plot(trace + offset * (2 - f), 'Color', colors(f,:), 'LineWidth', 0.7, 'DisplayName', type{f});
        end
    end
    title('Raw vs Denoised Trace (Stacked)');
    xlabel('Frame'); ylabel('ΔF (offset)');
    legend;
    ylim auto

    % Top-right: PSNR
    epochs = [0, 50];
    figure(fig);
    subplot('Position', [0.8, 0.7, 0.15, 0.2]);
    plot(epochs, psnrs(i, :), '-o', 'LineWidth', 1.5);
    title('PSNR'); xlabel('# Epochs'); ylabel('20log10(peak/std)'); grid on;

    % Bottom: Spike waveforms
    figure(fig);
    for f = 1:2
        waveforms =  sessions(sess_i).waveforms;
        subplot('Position', [0.05 + 0.16*(f-1), 0.05, 0.13, 0.2]); hold on;
        plot(mat2gray(waveforms{1}), 'Color', [0 0 0 0.5], 'LineWidth', 1);  % showing denoised on top
        plot(mat2gray(waveforms{f}), 'Color', colors(f,:), 'LineWidth', 1.2);
        corr = corrcoef(mat2gray(waveforms{1}), mat2gray(waveforms{f}));
        corrs(i, f) = corr(2,1);
        xline(snippet_len+1, '--', '0');
        title(sprintf('%d epochs', epochs(f)));
        xlabel('Frame'); ylabel('Norm ∆F');
    end
    sessions(sess_i).corr_waveform = corrs(i, 2);

    % Bottom right: average waveform
    figure(fig);
    avg_axes = subplot('Position', [0.05 + 0.32, 0.05, 0.13, 0.2]); hold(avg_axes, 'on');
    denoised_fig = openfig(fullfile(save_path,'Fig1_avg_spike_waveform.fig'),'invisible', 'new');
    lines_denoised = findobj(denoised_fig, 'Type', 'Line');
    raw_fig = openfig(fullfile(sessions(sess_i).raw_path,'Fig1_avg_spike_waveform.fig'),'invisible', 'new');
    lines_raw = findobj(raw_fig, 'Type', 'Line');
    x_raw = lines_raw.XData; y_raw = lines_raw.YData;
    x_denoised = lines_denoised.XData; y_denoised = lines_denoised.YData;

    % normalize spike height
    y_raw = y_raw/max(y_raw); y_denoised = y_denoised/max(y_denoised);
    plot(avg_axes, x_raw, y_raw,'Color', colors(1,:), 'LineWidth', 1.2);
    plot(avg_axes, x_denoised, y_denoised, 'Color', colors(2,:), 'LineWidth', 1.2);
    title(avg_axes, 'Average Spike Waveform');
    xlabel(avg_axes, 'Time (ms)'); ylabel(avg_axes, 'Fluorescence (A.U.)');
    legend(avg_axes, 'Raw', 'Denoised');
    xlim(avg_axes, [-0.02, 0.02]);
    close(raw_fig); close(denoised_fig);
    figure(fig); 
    sessions(sess_i).corr_waveform = corrs(i, 2);

    % Middle-right: Spike height
    subplot('Position', [0.8, 0.4, 0.15, 0.2]);
    plot(epochs, corrs(i, :), '-o', 'LineWidth', 1.5);
    title('Avg Spike Correlations'); xlabel('# Epochs'); ylabel('Pearson R'); grid on;

    sgtitle(sprintf('%s %s Cell %d', sessions(sess_i).animalID, sessions(sess_i).session_title, i), 'FontSize', 14, 'FontWeight', 'bold');

    saveas(fig, fullfile(save_path, "metrics", sprintf('%s_%s_FOV%d_Cell%d.png', sessions(sess_i).animalID, sessions(sess_i).session_title, sessions(sess_i).FOV, i)));
    savefig(fig, fullfile(save_path, "metrics", sprintf('%s_%s_FOV%d_Cell%d', sessions(sess_i).animalID, sessions(sess_i).session_title, sessions(sess_i).FOV, i)));
    close(fig)
end
save(fullfile(save_path,'sessions_var'), 'sessions');
end









