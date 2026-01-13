
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
