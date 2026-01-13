function [beh, spik, sub_t] = load_voltage_and_beh_support(path_mov, varargin)
% LOAD_VOLTAGE_AND_BEH Orchestrates loading behavior and voltage/spiking data
%
% Syntax
%   [beh, spik, sub_t] = load_voltage_and_beh(path_mov)
%   [beh, spik, sub_t] = load_voltage_and_beh(path_mov, 'cellID', 1, ...)
%
% Name-Value Pairs
%   'cellID'     : cell index (default 1)
%   'ThetaTrace' : 'prep_norm' (default) or 'despike' to compute theta from
%                  spike-removed trace produced by prep_norm_and_snr
%   'isPlot'     : enable plotting (currently unused in this wrapper)

% ---- Parameters ----
p = inputParser;
p.addRequired('path_mov', @(x) ischar(x) || isstring(x));
p.addParameter('cellID', 1, @(x) isnumeric(x) && isscalar(x));
p.addParameter('ThetaTrace', 'prep_norm', @(x) ischar(x) || isstring(x));
p.addParameter('isPlot', 0, @(x) isnumeric(x) || islogical(x));
p.addParameter('os', 0, @(x) isnumeric(x) || islogical(x));

p.parse(path_mov, varargin{:});
opts = p.Results;

% ---- Paths ----
path = get_paths_erin(char(opts.path_mov), opts.os);

% ---- Behavior ----
beh = load_beh(path.beh);

% ---- Voltage/Spiking ----
% Use the utility that bundles spiking timeline, subthreshold, and normalization
vol = load_voltage(path.spik, opts.cellID, path.mov);
spik = vol.spik;

% If requested, recompute theta from prep_norm-based spike removal
if strcmpi(opts.ThetaTrace, 'prep_norm') && isfield(vol, 'norm') && isfield(vol, 'sub_t')
    try
        theta_trace = vol.norm.IntensRmSpike;
        sub_t = vol.sub_t; % start from existing
        if ~isempty(theta_trace)
            fs = 1000; % subthresh and loaders assume 1 kHz
            sub_t.theta = theta_hilbert(theta_trace, fs, [4 10], 3, 200);
            sub_t.trace.norm_rmspike = theta_trace;
        else
            sub_t = vol.sub_t;
        end
    catch
        sub_t = vol.sub_t;
    end
else
    sub_t = vol.sub_t;
end

%Compute 

% ---- Optional plots (placeholder) ----
% if opts.isPlot, add any summary figures here using beh, spik, sub_t

%% Plotting

path.save = fullfile(path.save,'RecFigs'); [~,~] = mkdir(path.save);

%Spike Removal Comparison
if opts.isPlot
    y_min = min([vol.norm.IntensRmSpike;sub_t.trace.raw;sub_t.trace.norm_rmspike]);
    y_max = max([vol.norm.IntensRmSpike;sub_t.trace.raw;sub_t.trace.norm_rmspike]);
    figure('Visible','off');
    subplot(3,1,1)
    plot(vol.norm.IntensRmSpike)
    ylim([y_min y_max])

    subplot(3,1,2)
    plot(sub_t.trace.raw)
    ylim([y_min y_max])


    subplot(3,1,3)
    plot(sub_t.trace.norm_rmspike)
    ylim([y_min y_max])
    linkaxes
end

% Firing Rate & Running Plot
if opts.isPlot
    cellLabel = sprintf('%s %s %s %s %s Cell#%d', path.anim, path.sess_date, path.slic, path.fov, path.rec, opts.cellID);

    % Plot
    fig1 = figure('Visible', 'off');
    %figure();
    handles = [];
    labels = {};

    % Movement
    val = beh.vel;
    [vmin, vmax] = bounds(val); vrag= (vmax-vmin);
    plot(beh.ts, (val-vmin)/(vmax*1.1), 'k'); hold on;
    text(beh.ts(1), 0, 'Velocity', 'VerticalAlignment','bottom')

    % Theta
    val = sub_t.theta.theta_band;
    [vmin, vmax] = bounds(val); vrag = (vmax-vmin);
    plot(spik.ts(1:size(sub_t.trace.raw,1)), (val-vmin)/(vrag*1.1)+1, 'k');        % *** spike and behavior offset - likely from movement correction code filtering
    text(spik.ts(1), 1, 'Theta amplitude', 'VerticalAlignment','bottom')

    % Firing Rate
    val = spik.smooth;
    [vmin, vmax] = bounds(val); vrag = (vmax-vmin);
    plot(spik.ts, (val-vmin)/(vrag*1.1)+2, 'k');        % *** spike and behavior offset - likely from movement correction code filtering
    text(spik.ts(1), 2, 'Firing rate', 'VerticalAlignment','bottom')

    % Raw Trace
    val = sub_t.trace.raw;
    [vmin, vmax] = bounds(val); vrag = (vmax-vmin);
    plot(spik.ts(1:size(sub_t.trace.raw,1)), (val-vmin)/(vrag*1.1)+3, 'k'); 
    text(spik.ts(1), 3, 'Raw trace', 'VerticalAlignment','bottom')

    % Plot movement onset
    if ~isempty(beh.t_onset)
        h_onset = plot(beh.t_onset, beh.params.threshold, 'go');
        handles(end+1) = h_onset(1);
        labels{end+1} = 'Movement Onset';
    end

    % Plot movement offset
    if ~isempty(beh.t_offset)
        h_offset = plot(beh.t_offset,  beh.params.threshold, 'ro');
        handles(end+1) = h_offset(1);
        labels{end+1} = 'Movement Offset';
    end

    %handles = [h_spike, handles]; % Firing rate first
    %labels = [{'Firing Rate'}, labels];

    xlabel('Time (s)');
    title(sprintf('Velocity and Smoothed Spike Rate\n%s', cellLabel), 'Interpreter', 'none');
    %legend(handles, labels);

    % Save figure
    %set(fig1,'Visible','on')
    saveas(gcf, fullfile(path.save,[cellLabel '.png']));
    saveas(gcf, fullfile(path.save,[cellLabel '.fig']));
end

% Theta Running vs Still Plot
if opts.isPlot
    fig1 = figure('Visible', 'off');
    
    theta_still = sub_t.theta.power(beh.still(1:size(sub_t.trace.raw,1)));
    theta_run = sub_t.theta.power(beh.run(1:size(sub_t.trace.raw,1)));


    ydata = [theta_still;theta_run];
    xgroupdata = categorical(repelem(["still";"run"],[length(theta_still),length(theta_run)]));

    violinplot(xgroupdata,ydata);
    ylabel('Theta Power (ΔF/F%)²');
    title(sprintf('Intracellular Theta Power while Running vs Still\n%s',cellLabel));
    % Save figure
    figure('Visible','off');
    
    theta_still = sub_t.theta.power(beh.still(1:size(sub_t.trace.raw,1)));
    theta_run = sub_t.theta.power(beh.run(1:size(sub_t.trace.raw,1)));


    ydata = [theta_still;theta_run];
    xgroupdata = categorical(repelem(["still";"run"],[length(theta_still),length(theta_run)]));

    violinplot(xgroupdata,ydata);
    ylabel('Theta Power (ΔF/F%)²');
    title(sprintf('Intracellular Theta Power while Running vs Still\n%s',cellLabel), 'Interpreter', 'none');
    % Save figure
    %set(fig1,'Visible','on')
    saveas(gcf, fullfile(path.save,[cellLabel '_run-still_theta.png']));
    saveas(gcf, fullfile(path.save,[cellLabel '_run-still_theta.fig']));
end

% Firing Rate - Running vs Still Plot
if opts.isPlot && spik.nspike >0
    fig1 = figure('Visible', 'off');
    
    fr_run = spik.smooth(beh.run(1:size(sub_t.trace.raw,1)))';
    fr_still = spik.smooth(beh.still(1:size(sub_t.trace.raw,1)))';


    ydata = [fr_still;fr_run];
    xgroupdata = categorical(repelem(["still";"run"],[length(fr_still),length(fr_run)]));

    violinplot(xgroupdata,ydata);
    ylabel('Firing Rate (Hz)');
    title(sprintf('Firing Rate while Running vs Still\n%s',cellLabel), 'Interpreter', 'none');
    % Save figure
    %set(fig1,'Visible','on')
    saveas(gcf, fullfile(path.save,[cellLabel '_run-still_firing.png']));
    saveas(gcf, fullfile(path.save,[cellLabel '_run-still_firing.fig']));
end

%STA Plot - spike triggered spectogram of subtrheshold and spiking
if opts.isPlot && spik.nspike >10

    figure('Position', [100, 100, 1200, 400],'Visible', 'off');
    x = -1000:1000;
    subplot(1,2,1);
    plot(x,spik.auto)
    xlim([-60 60]);
    xlabel('Time Relative to Spike (ms)')
    ylabel('% Spikes');
    title('Spike-triggered Autocorrelogram');
    %set(gca(), 'YScale', 'log');

    subplot(1,2,2);
    plot(x,spik.sta)
    xlim([-250 250]);
    xlabel('Time Relative to Spike (ms)')
    ylabel('% Spike Height');
    title('Spike-triggered average waveform');

    saveas(gcf, fullfile(path.save,[cellLabel '_Autocorrelogram_STA.png']));
    saveas(gcf, fullfile(path.save,[cellLabel '_Autocorrelogram_STA.fig']));

end

%STA & Autocorrelogram Plot w/ STS - spike triggered average of subtrheshold and spiking
if opts.isPlot && spik.nspike >10

    % Calculate autocorrelogram and Spike Triggered Average - for run vs still periods
    spi = nan(spik.nspike,2001,2);
    sub = nan(spik.nspike,2001,2);

    end_time = max(spik.ts)*fs;
    for i = 1:spik.nspike
        window = max(1,spik.spikeT(i)-1000):min(end_time,spik.spikeT(i)+1000);

        if length(window)<size(spi,2)
            mask = spik.spikeT(i)-1000:spik.spikeT(i)+1000;
            mask = mask>=1 & mask<=end_time;
        else
            mask = 1:size(spi,2);
        end

        if beh.run(spik.spikeT(i))
            spi(i,mask,1) = spik.train(window);
            sub(i,mask,1) = vol.norm.NormIntensRmSpike(window);%Check timing
        elseif beh.still(spik.spikeT(i))
            spi(i,mask,2) = spik.train(window);
            sub(i,mask,2) = vol.norm.NormIntensRmSpike(window);%Check timing
        end
    end

    num_spikes_run   = sum(beh.run(spik.spikeT));
    num_spikes_still = sum(beh.still(spik.spikeT));
    spik.auto_run   = nansum(spi(:,:,1),1)/spik.nspike;
    spik.sta_run    = nanmean(sub(:,:,1),1);
    spik.auto_still = nansum(spi(:,:,2),1)/spik.nspike;
    spik.sta_still  = nanmean(sub(:,:,2),1);

    figure('Position', [100, 100, 1200, 400],'Visible', 'off');
    ax(1)=subplot(2,3,1); 
    ax(2)=subplot(2,3,2);
    ax(3)=subplot(2,3,4); 
    ax(4)=subplot(2,3,5); 
    ax(5)=subplot(2,3,3);
    ax(6)=subplot(2,3,6); 

    x = -1000:1000;
    plot(ax(1),x,spik.auto_run)
    xlim(ax(1),[-60 60]);
    xlabel(ax(1),'Time Relative to Spike (ms)')
    ylabel(ax(1),'% Spikes');
    title(ax(1),sprintf('Spike-triggered Autocorrelogram - run (%d Spikes)', num_spikes_run));
    %set(gca(), 'YScale', 'log');

    plot(ax(2),x,spik.sta_run)
    xlim(ax(2),[-250 250]);
    xlabel(ax(2),'Time Relative to Spike (ms)')
    ylabel(ax(2),'% Spike Height');
    title(ax(2),'Spike-triggered average waveform - run');

    plot(ax(3),x,spik.auto_still)
    xlim(ax(3),[-60 60]);
    xlabel(ax(3),'Time Relative to Spike (ms)')
    ylabel(ax(3),'% Spikes');
    title(ax(3),sprintf('Spike-triggered Autocorrelogram - still (%d Spikes)', num_spikes_still));
    %set(gca(), 'YScale', 'log');

    plot(ax(4),x,spik.sta_still)
    xlim(ax(4),[-250 250]);
    xlabel(ax(4),'Time Relative to Spike (ms)')
    ylabel(ax(4),'% Spike Height');
    title(ax(4),'Spike-triggered average waveform - still');


    %Spike Triggered Spectogram - run vs still
    fs = 1000;
    spik.theta_sts_still = struct();
    [spik.theta_sts_still.freq,spik.theta_sts_still.amp] = fft_plot(spik.sta_still,fs,0);
    spik.theta_sts_run = struct();
    [spik.theta_sts_run.freq,spik.theta_sts_run.amp] = fft_plot(spik.sta_run,fs,0);

    plot(ax(5),spik.theta_sts_run.freq,spik.theta_sts_run.amp)
    xlim(ax(5),[0 64]);
    xlabel(ax(5),'Frequency (hz)')
    ylabel(ax(5),'Amplitude (au)');
    title(ax(5),'Spike-triggered Spectogram - run');
    %set(gca(), 'YScale', 'log');

    plot(ax(6),spik.theta_sts_still.freq,spik.theta_sts_still.amp)
    xlim(ax(6),[0 64]);
    xlabel(ax(6),'Frequency (hz)')
    ylabel(ax(6),'Amplitude (au)');
    title(ax(6),'Spike-triggered Spectogram - still');
    

    saveas(gcf, fullfile(path.save,[cellLabel '_Autocorrelogram_STA_STS_run_still.png']));
    saveas(gcf, fullfile(path.save,[cellLabel '_Autocorrelogram_STA_STS_run_still.fig']));

end

end

%{

        % Align spikes to all nonzero licks
        lickTimes = beh.ts(beh.lick > 0);
        pre = 1; post = 2;
        spikeTimes = cell(length(lickTimes),1);

        for i = 1:length(lickTimes)
            idx = find(spik.ts > lickTimes(i)-pre & spik.ts < lickTimes(i)+post);
            relTime = spik.ts(idx) - lickTimes(i);
            spikeTimes{i} = relTime(spik.train(idx) > 0);
        end
%}




%{
% Old Plot
    % Plot
    figure('Visible', 'off');
    handles = [];
    labels = {};

    % Plot velocity
    yyaxis left
    h_vel = plot(beh.ts, beh.vel, 'k'); hold on;
    ylabel('Velocity (cm/s)');
    ylim([-0.4 2.0]);
    handles(end+1) = h_vel;
    labels{end+1} = 'Velocity';

    % Plot movement onset
    if ~isempty(beh.t_onset)
        h_onset = plot(beh.t_onset, params.threshold, 'go');
        handles(end+1) = h_onset(1);
        labels{end+1} = 'Movement Onset';
    end

    % Plot movement offset
    if ~isempty(beh.t_offset)
        h_offset = plot(beh.t_offset, params.threshold, 'ro');
        handles(end+1) = h_offset(1);
        labels{end+1} = 'Movement Offset';
    end

    % Plot firing rate
    yyaxis right
    h_spike = plot(spik.ts, spik.smooth, 'b');
    ylabel('Firing Rate (Hz)');
    ylim([-6 30]);
    handles = [h_spike, handles]; % Firing rate first
    labels = [{'Firing Rate'}, labels];

    xlabel('Time (s)');
    title(sprintf('Velocity and Smoothed Spike Rate\n%s', cellLabel), 'Interpreter', 'none');
    legend(handles, labels);
%}


