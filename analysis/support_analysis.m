% support_analysis.m
% Analysis of SUPPORT denoised sessions
% Refactored to use discover_sessions and support_sessions_{animal_prep} structs

clear; close all;

%% Session Parameters
% % Automatically detect OS: Windows uses Z:\, macOS/Linux use /Volumes/fanlab
if ismac || isunix
    root_path = fullfile('/Volumes/fanlab');
elseif ispc
    root_path = fullfile('Z:');
end

motion_corr = 'post-motion'; % 'pre-motion' or 'post-motion'
compare_motion = 1; % compare pre vs post-motion performance

%% generating paths
safe_addpath(fullfile(root_path,'Labmembers','Kohl','Code'));
safe_addpath(fullfile(root_path,'Labmembers','Erin','code'));
safe_addpath(fullfile(root_path,'Computer Code','Image Processing'));
safe_addpath(fullfile(root_path,'Computer Code','NoRmCorre'));
safe_addpath(fullfile(root_path,'Computer Code','Fan Lab'));

%% setting directories
path.root.parent = fullfile(root_path, 'Labmembers','Kohl','CCK');
path.root.analysis = fullfile(path.root.parent, 'support_analysis');

% if contains(motion_corr, 'post')
%     path.save_name = "post-motion"; 
% else
%     path.save_name = 'pre-motion';
% end
path.root.save = fullfile(path.root.analysis);
[~,~] = mkdir(path.root.save);

%% Parameters
path.analysis_file = "analysis-pre_post_motion.mat";
is_rerun = 0;

%% creating sessions using discover_sessions
custom_raw_roots = containers.Map( ...
    {'cck-gevi-w03', 'cck-gevi-w05'}, ...
    { fullfile(root_path,'Data and Analysis','DSI-BTSP','CCK-voltage_KS','cck-gevi-w03'), ...
      fullfile(root_path,'Labmembers','Kohl','CCK','cck-gevi-w05') } ...
);

% exclude = {'ExpressionCheck'};
target_file = "denoised.tiff";

animal_preps = {'cck-gevi'};
sessions = struct([]);
support_sessions = struct([]);

% Check if saved analysis file exists - if so, load it and continue analysis
analysis_file_path = fullfile(path.root.save, path.analysis_file);
if exist(analysis_file_path, 'file') && ~is_rerun
    fprintf('Loading saved analysis file: %s\n', path.analysis_file);
    saved_data = load(analysis_file_path);
    if isfield(saved_data, 'sessions')
        sessions = saved_data.sessions;
        % Convert paths in loaded sessions struct to match current OS
        sessions = convert_struct_paths(sessions, root_path);
        support_sessions = sessions; % Use same sessions as support_sessions
        fprintf('Continuing analysis from saved file.\n');
    else
        fprintf('Analysis file format not recognized, discovering sessions...\n');
        is_rerun = 1; % Force discovery if file format is wrong
    end
end

% If no saved analysis file or rerun requested, discover/load sessions
if isempty(sessions) || is_rerun
    % Load or discover sessions for each animal prep
    for prep = 1:numel(animal_preps)
        animal_prep = animal_preps{prep};
        
        % Try to load saved sessions first
        path.support_sessions_file = sprintf('sessions_%s.mat', animal_prep);
        if exist(fullfile(path.root.parent, path.support_sessions_file), 'file')
            load(fullfile(path.root.parent, path.support_sessions_file), 'support_sessions');
            continue; %skip this animal prep
        end
        % path.sessions_file = sprintf('sessions_%s.mat', animal_prep);
        % sessions_path = fullfile(path.root.parent, path.sessions_file);
        
        if exist(sessions_path, 'file') && ~is_rerun
            fprintf('Loading saved sessions: %s\n', path.sessions_file);
            loaded_data = load(sessions_path);
            if isfield(loaded_data, 'sessions')
                new_sessions = loaded_data.sessions;
            else
                % If file doesn't have expected format, discover sessions
                fprintf('File format not recognized, discovering sessions...\n');
                new_sessions = discover_sessions(custom_raw_roots, animal_prep, path.root.parent, exclude);
            end
        else
            % Discover sessions using existing discover_sessions function
            fprintf('Discovering sessions for %s...\n', animal_prep);
            new_sessions = discover_sessions(custom_raw_roots, animal_prep, path.root.parent, exclude);
        end
        
        new_sessions = convert_struct_paths(new_sessions, root_path);
        % Filter sessions for support
        new_support_sessions = filter_sessions_for_support(new_sessions, motion_corr, target_file);
                
        % Renumber cell_ids to be sequential for each date+FOV combination
        % new_support_sessions = renumber_cell_ids(new_support_sessions);
        
        support_sessions = [support_sessions, new_support_sessions];
        sessions = [sessions, new_support_sessions];

        % Save support sessions
        save(fullfile(path.root.parent, path.support_sessions_file), 'support_sessions', '-v7.3');
    end
end

if isempty(sessions)
    error('No sessions found. Please run discover_sessions first.');
end
%% Choosing baseline noise regions
% load previously saved noise regions
noise_regions_file = "noise_regions.mat";
if exist(fullfile(path.root.save, noise_regions_file), 'file')
    load(fullfile(path.root.save, noise_regions_file));
else
    if ~exist(fullfile(path.root.save, "noise_regions"), 'dir')
        [~,~] = mkdir(fullfile(path.root.save, "noise_regions"));
    end
    noise_regions = struct([]);
    for sess_i = 1:length(sessions)
        if exist(fullfile(path.root.save, "noise_regions", sprintf('%s.mat', sessions(sess_i).cell_hash))); 
            load(fullfile(path.root.save, "noise_regions", sprintf('%s.mat', sessions(sess_i).cell_hash)), 'noise_region');
            noise_regions(sess_i) = noise_region;
            continue; 
        end
        dt = 1; % period = 1000:2000;
        nCell = sessions(sess_i).fov_num_cells;
        IntensOrig = sessions(sess_i).trace{2}; % get denoised trace
        noise_region = zeros(1,nCell);
        % raw_noise_region = zeros(1, nCell);
        clear SNR
        for i = 1:nCell
           dFTraces = IntensOrig(:, i);
           % raw_dFTraces = raw_IntensOrig(:, i);
           traces = {dFTraces};%, raw_dFTraces};
           for t = 1:numel(traces)
               trace = traces{t};
               save_path = fullfile(path.save_dir, "noise_regions");
               % else; save_path = fullfile(path.save_dir, "noise_regions", "raw"); end
               while true
                   fig = figure('Position', [100 100 1500 600]);plot(trace,'r');
                   title('Right-click to select start of baseline noise region')
                   hold on;
            
                   [x, ~] = ginput(1);
                   %tochoose = x;
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
                       %if t == 1; denoised_noise_region(i) = period1;
                       %else; raw_noise_region(i) = period1; end
                       noise_region(i) = period1;
                       saveas(fig, fullfile(save_path, sprintf('NoiseRegion%s%d.png', sessions(sess_i).cell_hash, i)));
                       savefig(fig, fullfile(save_path, sprintf('NoiseRegion%s%d.fig', sessions(sess_i).cell_hash, i)));
                       close(fig);
                       break
                   end
                   close(fig);
               end
           end
        end
        sessions(sess_i).noise_regions = noise_region;
        %sessions(sess_i).raw_noise_reg = raw_noise_region;
    end
end


if ~exist(fullfile(path.save_dir, 'noise_regions'))
    save(fullfile(path.save_dir, 'noise_regions'), 'sessions');
end
%% individual session summary plots
if ~exist(fullfile(path.save_dir, "metrics"), 'dir')
    mkdir(fullfile(path.save_dir, "metrics"));end
colors = [
    0, 0, 0;          % Raw - black
    0.0, 0.45, 0.74;];  % 50 - blue
if compare_motion
    type = {'raw', 'pre', 'post'}; 
    end_idx = 3;
else
    type = {'raw', 'SUPPORT'}; 
    end_idx = 2;
end
for sess_i = 1:length(sessions)
    if sessions(sess_i).session_name == '105014_Spon30'; continue; end
    nCell = sessions(sess_i).fov_num_cells;
    i = sessions(sess_i).cell_id;
    fig = figure('Position', [100, 100, 1400, 900], 'Color', 'w');
    spike_idx = sessions(sess_i).raw_spikes{i};
    snippet_len = 500;
    waveforms = cell(end_idx, 1);
    noise_regions = sessions(sess_i).noise_regions;
    % Get valid spike indices
    trace_len = length(sessions(sess_i).trace{1}(:,i));
    valid_spikes = spike_idx(spike_idx > snippet_len & spike_idx < trace_len - snippet_len);    
    traces_all = cell(end_idx, 1);
    for f = 1:3
        trace = sessions(sess_i).trace{f}(:,i);
        aligned = zeros(length(valid_spikes), 2*snippet_len + 1);
        for s = 1:length(valid_spikes)
            idx = valid_spikes(s);
            aligned(s, :) = trace(idx-snippet_len:idx+snippet_len);
        end
        mean_waveform = mean(aligned, 1);
        waveforms{f} = mean_waveform;
        spike_heights(i, f) = max(mean_waveform);
        psnrs(i, f) = 20 * log10(spike_heights(i, f) / std(trace(noise_regions(i):(noise_regions(i)+299))));

        % scaling traces
        maxPos = max(trace);
        scaled = trace/maxPos;
        sessions(sess_i).scaled_traces{f} = scaled;
    end

    sessions(sess_i).spike_height = spike_heights(i);
    sessions(sess_i).waveforms = waveforms;
    sessions(sess_i).psnr = psnrs(i);
    
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
        % norm_trace = trace - movmean(trace, 100);
        % norm_trace = norm_trace + offset * (nEpochs - f);  % stack traces top-down

        % norm_trace_0 = trace_0 - movmean(trace_0, 100);
        % norm_trace_0 = norm_trace_0 + offset * (nEpochs - f);
    
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
    % load waveform fig
    session_info = strsplit(sessions(sess_i).session_path, filesep);
    if contains(sessions(sess_i).anim_id, "w03")
        cck_w03_path = custom_raw_roots('cck-gevi-w03');
        w03_dirs = dir(cck_w03_path);
        w03_dirs = w03_dirs([w03_dirs.isdir]);
        w03_dirs = w03_dirs(~ismember({w03_dirs.name}, {'.', '..'}));
        if length(session_info) >= 4
            matching_dirs = w03_dirs(startsWith({w03_dirs.name}, session_info{end-3}));
            if ~isempty(matching_dirs)
                matching_date = matching_dirs(1).name;
                raw_path = fullfile(cck_w03_path, sprintf('%s/slice%d/FOV%d', matching_date, 1, sessions(sess_i).FOV));
            else
                raw_path = fullfile(cck_w03_path, sprintf('slice%d/FOV%d', 1, sessions(sess_i).FOV));
            end
        else
            raw_path = fullfile(cck_w03_path, sprintf('slice%d/FOV%d', 1, sessions(sess_i).FOV));
        end
    else
        cck_w05_path = custom_raw_roots('cck-gevi-w05');
        if length(session_info) >= 12
            raw_path = fullfile(cck_w05_path, sprintf('%s/slice%d/FOV%d', session_info{12}, 1, sessions(sess_i).FOV));
        else
            raw_path = fullfile(cck_w05_path, sprintf('slice%d/FOV%d', 1, sessions(sess_i).FOV));
        end
    end
    avg_waveform_name = sprintf('Fig%d_avg_spike_waveform.fig', sessions(sess_i).cell_id);
    
    %ax_raw = findobj(raw_fig, 'Type', 'Axes');
    figure(fig);
    avg_axes = subplot('Position', [0.05 + 0.32, 0.05, 0.13, 0.2]); hold(avg_axes, 'on');
    denoised_fig = openfig(fullfile(sessions(sess_i).session_path, avg_waveform_name),'invisible', 'new');
    %ax_denoised = findobj(denoised_fig, 'Type', 'Axes');
    lines_denoised = findobj(denoised_fig, 'Type', 'Line');
    raw_fig = openfig(fullfile(raw_path, sessions(sess_i).session_name, avg_waveform_name), 'invisible', 'new');
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

    sgtitle(sprintf('%s %s Cell%d', sessions(sess_i).anim_id, erase(sessions(sess_i).session_name, '_'), i), 'FontSize', 14, 'FontWeight', 'bold');
    
    saveas(fig, fullfile(path.save_dir, "metrics", sprintf('%s_%s_FOV%d_Cell%d.png', sessions(sess_i).anim_id, sessions(sess_i).session_name, sessions(sess_i).FOV, i)));
    savefig(fig, fullfile(path.save_dir, "metrics", sprintf('%s_%s_FOV%d_Cell%d', sessions(sess_i).anim_id, sessions(sess_i).session_name, sessions(sess_i).FOV, i)));

    %exportgraphics(fig, fullfile(path.save_dir, "metrics", 'MoviePanels.pdf'), 'Append', i > 1, 'Resolution', 300, 'ContentType', 'vector');
    close(fig);
    
end
%save(fullfile(path.save_dir, saved_file), 'sessions');

%% just plotting average waveform to confirm pre vs post motion
if compare_motion
for sess_i = 1:length(post_sessions)
    i = post_sessions(sess_i).cell_id;
    if post_sessions(sess_i).session_name == '105014_Spon30'; continue; end
    fig = figure('Position', [100, 100, 1400, 900], 'Color', 'w');
    % Paths should already be converted by convert_struct_paths, but ensure consistency
    if ismac || isunix
        post_sessions(sess_i).session_path = replace(post_sessions(sess_i).session_path, 'Z:', '/Volumes/fanlab');
        post_sessions(sess_i).session_path = replace(post_sessions(sess_i).session_path, '\', '/');
    end
    pre_session_info = strsplit(pre_sessions(sess_i).session_path, filesep);
    post_session_info = strsplit(post_sessions(sess_i).session_path, filesep);

    if contains(post_sessions(sess_i).anim_id, "w03")
        cck_w03_path = custom_raw_roots('cck-gevi-w03');
        w03_dirs = dir(cck_w03_path);
        w03_dirs = w03_dirs([w03_dirs.isdir]);
        w03_dirs = w03_dirs(~ismember({w03_dirs.name}, {'.', '..'}));
        if length(post_session_info) >= 4
            matching_dirs = w03_dirs(startsWith({w03_dirs.name}, post_session_info{end-3}));
            if ~isempty(matching_dirs)
                matching_date = matching_dirs(1).name;
                raw_path = fullfile(cck_w03_path, sprintf('%s/slice%d/FOV%d', matching_date, 1, post_sessions(sess_i).FOV));
            else
                raw_path = fullfile(cck_w03_path, sprintf('slice%d/FOV%d', 1, post_sessions(sess_i).FOV));
            end
        else
            raw_path = fullfile(cck_w03_path, sprintf('slice%d/FOV%d', 1, post_sessions(sess_i).FOV));
        end
    else
        cck_w05_path = custom_raw_roots('cck-gevi-w05');
        if length(post_session_info) >= 12
            raw_path = fullfile(cck_w05_path, sprintf('%s/slice%d/FOV%d', post_session_info{12}, 1, post_sessions(sess_i).FOV));
        else
            raw_path = fullfile(cck_w05_path, sprintf('slice%d/FOV%d', 1, post_sessions(sess_i).FOV));
        end
    end
end
    avg_waveform_name = sprintf('Fig%d_avg_spike_waveform.fig', post_sessions(sess_i).cell_id);
    %ax_raw = findobj(raw_fig, 'Type', 'Axes');
    %avg_axes = subplot('Position', [0.05 + 0.32, 0.05, 0.13, 0.2]); hold(avg_axes, 'on');
    pre_fig = openfig(fullfile(pre_sessions(sess_i).session_path, avg_waveform_name),'invisible', 'new');
    %ax_denoised = findobj(denoised_fig, 'Type', 'Axes');
    lines_pre = findobj(pre_fig, 'Type', 'Line');
    post_fig = openfig(fullfile(post_sessions(sess_i).session_path, avg_waveform_name),'invisible', 'new');
    lines_post = findobj(post_fig, 'Type', 'Line');
    raw_fig = openfig(fullfile(raw_path, post_sessions(sess_i).session_name, avg_waveform_name), 'invisible', 'new');
    lines_raw = findobj(raw_fig, 'Type', 'Line');
    x_raw = lines_raw.XData; y_raw = lines_raw.YData;
    x_pre = lines_pre.XData; y_pre = lines_pre.YData;
    x_post = lines_post.XData; y_post = lines_post.YData;

    % compute pearson correlation btw avg waveforms
    y_raw  = y_raw(:); y_pre  = y_pre(:); y_post = y_post(:);
    r_raw_pre  = corr(y_raw, y_pre,  'Type', 'Pearson');
    r_raw_post = corr(y_raw, y_post, 'Type', 'Pearson');
    % normalize spike height
    y_raw = y_raw/max(y_raw); y_pre = y_pre/max(y_pre); y_post = y_post/max(y_post);
    plot(x_raw, y_raw,'Color', 'black', 'LineWidth', 1.2); hold on;
    plot(x_pre, y_pre, 'Color', 'blue', 'LineWidth', 1.2); hold on;
    plot(x_post, y_post, 'Color', 'red', 'LineWidth', 1.2);
    txt = {
    sprintf('Raw vs Pre:  r = %.3f', r_raw_pre)
    sprintf('Raw vs Post: r = %.3f', r_raw_post)
    };
    text(0.02, 0.95, txt, ...
        'Units', 'normalized', ...
        'VerticalAlignment', 'top', ...
        'FontSize', 11);
    xlabel('Time (ms)'); ylabel('Fluorescence (A.U.)');
    legend('Raw', 'Pre', 'Post');
    xlim([-0.02, 0.02]);
    close(raw_fig); close(pre_fig); close(post_fig);
    sgtitle(sprintf('%s %s Cell%d', pre_sessions(sess_i).anim_id, erase(pre_sessions(sess_i).session_name, '_'), i), 'FontSize', 14, 'FontWeight', 'bold');
        
    saveas(fig, fullfile(path.root.dataset,'analysis', "waveforms", sprintf('%s_%s_FOV%d_Cell%d.png', pre_sessions(sess_i).anim_id, pre_sessions(sess_i).session_name, pre_sessions(sess_i).FOV, i)));
    savefig(fig, fullfile(path.root.dataset,'analysis', "waveforms", sprintf('%s_%s_FOV%d_Cell%d', pre_sessions(sess_i).anim_id, pre_sessions(sess_i).session_name, pre_sessions(sess_i).FOV, i)));
    
    %exportgraphics(fig, fullfile(path.save_dir, "metrics", 'MoviePanels.pdf'), 'Append', i > 1, 'Resolution', 300, 'ContentType', 'vector');
    close(fig);
    waveform_corr(sess_i).raw_pre  = r_raw_pre;
    waveform_corr(sess_i).raw_post = r_raw_post;
    waveform_corr(sess_i).cell_hash  = post_sessions(sess_i).cell_hash;
    waveform_corr(sess_i).difference = r_raw_post - r_raw_pre;
end
save(fullfile(path.root.dataset,'analysis', "waveforms", 'correlations.mat'), "waveform_corr")
%% loading both post and pre motion processing sessions
if compare_motion
    full_sessions = cell(1,2);
    if exist('sessions', 'var') && ~isempty(sessions)
        if contains(motion_corr, 'post')
            pre_data = load(fullfile(path.root.dataset,'analysis','pre-motion',saved_file));
            pre_sessions = pre_data.sessions;
            post_sessions = sessions;
        else
            post_data = load(fullfile(path.root.dataset,'analysis','post-motion',saved_file));
            post_sessions = post_data.sessions;
            pre_sessions = sessions;
        end
        full_sessions{1} = pre_sessions;
        full_sessions{2} = post_sessions;
    else
        pre_data = load(fullfile(path.root.dataset,'analysis','pre-motion',saved_file));
        post_data = load(fullfile(path.root.dataset,'analysis','post-motion',saved_file));
        pre_sessions = pre_data.sessions;
        post_sessions = post_data.sessions;
        full_sessions{1} = pre_sessions;
        full_sessions{2} = post_sessions;
    end
    % Convert paths in loaded sessions
    pre_sessions = convert_struct_paths(pre_sessions, root_path);
    post_sessions = convert_struct_paths(post_sessions, root_path);
end

%% dataset summary
% changing save dir to general (one level up from pre/post motion subdir)
path.save_dir = fullfile(path.root.dataset,'analysis');
% preparing and aligning sessions % later can get rid of this once
% consolidated into one struct
names_pre = {full_sessions{1}.session_name};
names_post = {full_sessions{2}.session_name};
[common_names, idx_pre, idx_post] = intersect(names_pre, names_post);
% 
pre_aligned = full_sessions{1}(idx_pre);
post_aligned = full_sessions{2}(idx_post); 
% PSNR
psnrs{1} = cat(1, pre_aligned.raw_psnr);
psnrs{2} = cat(1, pre_aligned.denoised_psnr);
psnrs{3} = cat(1, post_aligned.denoised_psnr);
figure; hold on;
colors = {'r', 'b'};
all_vals = []; % to get axis lims
for f = 2:3
    x = psnrs{1}(:);
    y = psnrs{f}(:);
    all_vals = [all_vals; x; y;];
    scatter(x, y, 25, colors{f-1}, 'filled','MarkerFaceAlpha', 0.6);
    coeffs = polyfit(x, y, 1);
    x_fit = linspace(min(x), max(x), 100);
    y_fit = polyval(coeffs, x_fit);
    plot(x_fit, y_fit, 'Color', colors{f-1}, 'LineWidth', 1.5);    
end
lims = [min(all_vals), max(all_vals)];
plot(lims, lims, 'k--', 'LineWidth', 1);
xlabel('PSNR Raw');
ylabel('PSNR with SUPPORT');
title('PSNR: after SUPPORT vs Raw');

axis square;
grid on;
legend({'pre-motion', 'pre best fit', 'post-motion', 'post best fit', 'y=x'}, ...
    'Location', 'best');
[~, p_pre] = ttest(psnrs{2}, psnrs{1});
[~, p_post] = ttest(psnrs{3}, psnrs{1});
x_text1 = lims(1) + 0.32*(lims(2)-lims(1));
y_text1 = lims(2) - 0.08*(lims(2)-lims(1));
x_text2 = lims(1) + 0.40*(lims(2)-lims(1));
y_text2 = lims(2) - 0.33*(lims(2)-lims(1));
text(x_text1, y_text1, sprintf('p_{pre} = %.3g', p_pre), ...
    'FontSize', 12, 'FontWeight', 'bold', 'Color', colors{1});

text(x_text2, y_text2, sprintf('p_{post} = %.3g', p_post), ...
    'FontSize', 12, 'FontWeight', 'bold', 'Color', colors{2});

saveas(gcf(), fullfile(path.save_dir, 'PSNR after SUPPORT vs Raw.png'));

% firing rate

% num spikes vs SNR

%% -------- Local helper functions --------


% function support_sessions = renumber_cell_ids(support_sessions)
%     % Renumber cell_ids to be sequential (1, 2, 3, ...) for each date+FOV combination
    
%     if isempty(support_sessions)
%         return;
%     end
    
%     % Get all unique dates
%     dates = {support_sessions.date};
%     unique_dates = unique(dates);
    
%     % Create mapping from old indices to new indices for reordering
%     new_indices = 1:numel(support_sessions);
    
%     for d = 1:numel(unique_dates)
%         date = unique_dates{d};
%         % Find all sessions with this date
%         date_mask = strcmp(dates, date);
%         date_indices = find(date_mask);
%         date_sessions = support_sessions(date_mask);
        
%         % Get all unique FOVs for this date
%         fovs = [date_sessions.FOV];
%         unique_fovs = unique(fovs);
        
%         for f = 1:numel(unique_fovs)
%             fov = unique_fovs(f);
%             % Find all sessions with this date and FOV
%             fov_mask = [date_sessions.FOV] == fov;
%             fov_indices = date_indices(fov_mask);
%             fov_sessions = date_sessions(fov_mask);
            
%             % Get current cell_ids for this date+FOV combination
%             cell_ids = [fov_sessions.cell_id];
            
%             % Update fov_num_cells for all sessions in this FOV to be the number of cells
%             num_cells_in_fov = numel(fov_sessions);
%             for i = 1:numel(fov_indices)
%                 idx = fov_indices(i);
%                 support_sessions(idx).fov_num_cells = num_cells_in_fov;
%             end
            
%             % Check if cell_ids are already sequential starting from 1
%             sorted_cell_ids = sort(cell_ids);
%             expected_cell_ids = 1:numel(sorted_cell_ids);
            
%             if ~isequal(sorted_cell_ids, expected_cell_ids)
%                 % Need to renumber - create mapping from old to new cell_id
%                 % Sort by current cell_id to establish order
%                 [sorted_cell_ids, sort_order] = sort(cell_ids);
%                 old_to_new_map = containers.Map('KeyType', 'double', 'ValueType', 'double');
%                 for i = 1:numel(sorted_cell_ids)
%                     old_to_new_map(sorted_cell_ids(i)) = i;
%                 end
                
%                 % Apply renumbering to sessions
%                 for i = 1:numel(fov_indices)
%                     idx = fov_indices(i);
%                     old_cell_id = support_sessions(idx).cell_id;
%                     support_sessions(idx).cell_id = old_to_new_map(old_cell_id);
%                     %  update cell_hash with new cell_id
%                     support_sessions(idx).cell_hash = replace(support_sessions(idx).cell_hash, sprintf("Cell%d", old_cell_id), sprintf("Cell%d", support_sessions(idx).cell_id));
%                 end
%             end
%         end
%     end
% end