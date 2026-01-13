function [] = Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_erin(metadata)

%KS Edit - 2ms delay is messing up function - removed from line 85
% twBlueV = unique( round( twBlueAI/10) ) +2; % 2 ms delay btw wvfm command and actual data
 

% Fan Lab: spike finding in voltage imaging traces
% step 1: use median filter to get baseline and divide signal over this baseline to get rid of low frequency noise;
% step 2: use gaussian smoothing function to smooth trace;
% step 3: idenfitying spikes with guide of 4*sigma where sigma is temporally uncorrelated gaussian noise
% step 4: spike find: set threshold with the help of visual guide and visual inspection

% * note once spikes are identified, all further characterization was performed on the original trace

% blueStim: AO or AI, either output command from wvfm-AO or input recording from behavior data-AI
% this is for correcting optogenetics stimulation light induced increase of fluorescence.

% Linlin Fan 2024-12-12; updated 2025-02-12

if metadata.use_support
    save_dir = fullfile(metadata.session_path, 'support', metadata.motion_corr);
else
    save_dir = metadata.session_path;
end

sz=get(0,'screensize');

load(fullfile(save_dir, 'Masks_BestIcaTrace.mat')); % cd path out of the function

nCells = size(IntensOrig,2);
clear C;
for i = 1:nCells
    % Delete initial frames that are due to onset of the camera
    initial_frame = 1; % if no deletion, initial_fr = 1
    % minimum number of frames between spikes
    min_interspike_time = 3;    % the minimum number of frames between spikes
    dt = 0.001;
    
    TracesOrig = IntensOrig(:,i); % figure; plot(TracesOrig)
    TracesN = mat2gray( TracesOrig ) + 1; % figure; plot(TracesN)
    Traces = TracesN./prctile( TracesN,10); % figure; plot(Traces) % 5% prctile as the baseline
    Traces = Traces (initial_frame : end, :);
    [nframe ncell] = size(Traces);
    FramesPerStep = nframe; % the number of frames per step
    t = (1:nframe)*dt; % the time points (ms)
    
    % remove baseline noise
    bkgd_interp_width = 10;     % number of points to smooth over when calculating background % used 25 before; 10/15 better than 25
    bkgd = medfilt2(Traces, [bkgd_interp_width 1],'symmetric');  % figure; plot(bkgd) % use median filter to calculate background
    Tmed = Traces./bkgd; % figure; plot(Tmed)
    
    % smoothing function of gaussian function for better identification of spikes
    smpix = 9;                  % the number of points to use in the smoothing function
    sigma = 0.8;                % the width of the gaussian in the smoothing function in frames
    x = -ceil((smpix-1)/2):ceil((smpix-1)/2);
    f_sm = exp(-x.^2/(2*sigma^2));
    f_sm = f_sm/sum(f_sm);
    %figure(1); plot(x,f_sm,'-*'); title('smoothing function');
    lensm = (length(f_sm)-1)/2;
    % smooth using calulated smoothing function
    Tconv = conv([ones(1,lensm)*Tmed(1), Tmed', ones(1,lensm)*Tmed(end)],f_sm,'valid');  % smooth using calulated smooth function
    % figure; plot(Tconv)
    Sm = ceil(FramesPerStep/30);% Sm = ceil(FramesPerStep/8);
    %Sm = bkgd_interp_width;
    Tconv_bkgd = smooth(ordfilt2(Tconv, round(0.1*Sm), ones(1,Sm),'symmetric'),Sm); % raise up the regions that stick down too far during spiking
    
    figure(2); clf;
    set(gcf,'position',[0,sz(4)/6,sz(3)/1,sz(4)/7])% set(gcf,'position',[sz(3)/20,sz(4)/50,sz(3)/1.2,sz(4)/1.1])
    %     ylim ([0.98 1.5]);
    plot(t,Traces,t,bkgd,t,Tconv,t,Tconv_bkgd)
    xlabel('time (sec)'); ylabel('fluorescence intensity');
    legend('raw','bkgd','conv','conv bkgd'); hold on
    
    Tconv = Tconv./Tconv_bkgd';
    Tconv = Tconv/mean(Tconv);
    
    % if protNm contains optogenetic stimulation, then add dAdd to bring
    % spike height the same with and without optogenetic stimulation
    if ~isempty(strfind(metadata.blueStim, 'AO'))
        % for EStepV5 type of protocol where you use AO to control blue light on and off and intensity
        % if spikes amp on top of blue light is lower than that without blue light
        % twBlue = [241:740 1241:1740 2241:2740 3241:3740 4241:4740 5241:5740 6241:6740 7241:7740 7990:11990];% 8 steps
        % load wvfm and find the time points where AO5
        % Get Stimulation protocol
        stim_protocol = get_stim_protocol(metadata.session_path);
        
        AOtoAOTFblue = stim_protocol.WFAO(10*10+1:end,1)';% remove the 2
        t_blue = (1:length(AOtoAOTFblue))/10000;
        
        %twBlueAI = find (AOtoAOTFblue > 0 ) ; % tmp = diff(Bh2); figure;plot(tmp);
        twBlueAI = find (AOtoAOTFblue > 2 ) ;
        if ~isempty(twBlueAI)
            
            %What does this do? Not useful... KS 11/6/2025
            %{
            twBlueV = unique( round( twBlueAI/10) ); %+2; % 2 ms delay btw wvfm command and actual data
            
            twoBlueV = setdiff(1:nframe,twBlueV);
            if max(Tconv(twBlueV)) < max(Tconv(twoBlueV))
                Tconv(twBlueV) = Tconv(twBlueV) + max(Tconv(twoBlueV))-max(Tconv(twBlueV));
            end
            %}            
            
            %{
            figure (1000); clf;
            set(gcf,'position',[0,sz(4)/50,sz(3)/1,sz(4)/4.5]) % set(gcf,'position',[sz(3)/20,sz(4)/50,sz(3)/1.2,sz(4)/1.1])
            plot (Tconv); ylim ([0.95 1.35]);
            
            
            % Suggestion for wBlue
            stim = downsample(WFAO(:,1),10);
            stim = stim(11:end);
            stim>=0;

            mean_tconv = mean(Tconv(stim<=0));

            sig = Tconv-mean_tconv;
            mean_sig = mean(sig(stim>=0));
            stim(stim==0) = nan;
            sig_filt = conv(sig, gausswin(round(0.1*1000))/sum(gausswin(round(0.1*1000))), 'same');
            mean_sig = mean(sig_filt(stim>=0));
            g = mean(sig_filt./stim','omitnan');

            
            dAdd = input(sprintf('add value for wBlue:   (suggestions: %0.3f %0.3f)',mean_sig,g)); % dAdd = 0; %
            Tconv(twBlueV) = Tconv(twBlueV) + dAdd;
            %}
            dAdd = 0;
        else
            dAdd = 0;
        end
        
        
    elseif ~isempty(strfind(metadata.blueStim, 'AI'))
        % load AI and find the time points where AO5
        Bh = load(fullfile(metadata.session_path, 'AI Data'));% 1, pitch; 2, lick; 3, ValveTrig; 4, synC
        Bh2 = Bh(5,10*10+1:end);% remove the first 10
        tdaq = (1:size(Bh2,2))/10000;
        
        twBlueAI = find (Bh2 > 2 ) ; % tmp = diff(Bh2); figure;plot(tmp);
        if ~isempty(twBlueAI)
            twBlueV = unique( round( twBlueAI/10) );
            
            twoBlueV = setdiff(1:nframe,twBlueV);
            if max(Tconv(twBlueV)) < max(Tconv(twoBlueV))
                Tconv(twBlueV) = Tconv(twBlueV) + max(Tconv(twoBlueV))-max(Tconv(twBlueV));
            end
            
            figure (1000); clf;
            set(gcf,'position',[0,sz(4)/50,sz(3)/1,sz(4)/4.5])% set(gcf,'position',[sz(3)/20,sz(4)/50,sz(3)/1.2,sz(4)/1.1])
            plot (Tconv); ylim ([0.95 1.35]);
            
            dAdd = input('add value for wBlue:   '); % dAdd = 0; %
            Tconv(twBlueV) = Tconv(twBlueV) + dAdd;
        else
            dAdd = 0;
        end
    else
        dAdd = 0;
    end
    
    figure (1001); clf;
    set(gcf,'position',[0,sz(4)/50,sz(3)/1,sz(4)/4.5])% set(gcf,'position',[sz(3)/20,sz(4)/50,sz(3)/1.2,sz(4)/1.1])
    
    plot (Tconv); ylim ([0.95 1.35]);
    
    % loop through the total number of pulses, indicate thresholds, and record spike timings and widths
    C(i).nspike = zeros(1);  % the number of spikes for each step
    C(i).spikeT = cell(1);   % the spike timings for each spike
    C(i).spikeW = cell(1);   % the widths for each spike
    C(i).spikeA = cell(1);   % the Amplitude for each spike
    
    p = 1; Tstep = Tconv(FramesPerStep*(p-1) + (1:FramesPerStep));
    guide = mean(Tstep) + 4*(prctile(Tstep, 50) - prctile(Tstep,16)); 
    % thresh = 1 + 4*(prctile(Tstep, 50) - prctile(Tstep,16));%thresh used to be 8
    % guide = mean(Tstep) + 1/2*(max(Tstep)-mean(Tstep));
    hold on;
    plot([1 length(Tstep)], [guide guide], 'g-');
    
    title('Right-click to indicate threshold')
    [x, y] = getpts(gca);
    thresh = y(end);
    
    figure(888); clf;
    set(gcf,'position',[0,sz(4)/50,sz(3)/1,sz(4)/4.5])% set(gcf,'position',[sz(3)/20,sz(4)/50,sz(3)/1.2,sz(4)/1.1])
    
    plot(Tstep)
    hold on;
    plot([1 length(Tstep)], [guide guide], 'g-');
    [sT, ns] = spikefind3Linlin(Tstep,min_interspike_time,guide,thresh);
    % [sT, ns] = spikefind_corr(Tconv, FramesPerStep*(i-1), (1:FramesPerStep));
    
    % fit each spike to a Gaussian to extract the width and fine-tune the timing
    sT2 = zeros(1,ns);
    sW = zeros(1,ns);
    Amp = zeros(1,ns);
    % Set up a kernel for the average spike waveform
    nback = 20;
    nfront = 30;
    Lk = nback + nfront + 1;
    kernel = zeros(Lk,1);
    
    c = 0; % counter of good spikes;
    for k = 1:ns
        Frame = max([1,sT(k)-lensm]):min([length(Tstep),sT(k)+lensm]);    % pull out indices a few points on either side of spike
        Peak = Tstep(Frame);    % corresponding intensity values
        Time = Frame - sT(k);
        ffun = fittype('1 + A*exp(-4*log(2)*(x-t0)^2/w^2)'); % Fit function.  A is amplitude, t0 is time shift, w is full width half max
        fopt = fitoptions('Method','NonlinearLeastSquares','Lower',[0, -lensm, 1],'Upper',[1.5*(max(Peak)-1), lensm, 2*lensm+1],'StartPoint',[max(Peak)-1, 0, lensm/2]);   % specify min, max, and guess for each parameter
        peak_fit = fit(Time',Peak',ffun,fopt);
        Frame_interp = interp1(1:length(Frame),Frame,1:.1:length(Frame));    % plot fit using more finely spaced points
        
        %plot(Frame_interp,1 + peak_fit.A*exp(-4*log(2)*(Frame_interp - sT(k) - peak_fit.t0).^2/peak_fit.w^2),'c')
        ylim ([0.9 1.2]);hold all;
        %text(sT(k) + peak_fit.t0,1+peak_fit.A,int2str(k));
        sT2(k) = sT(k) + peak_fit.t0;
        Amp(k) = peak_fit.A;
        sW(k) = peak_fit.w;
        if (sT(k) > nback) & ((sT(k) + nfront) <= length(Tstep));
            kernel = kernel + Traces((sT(k)-nback):(sT(k)+nfront), 1);
            c = c + 1;
        end;
        
    end
    
    kernel = kernel/c;
    
    title({['cell ',int2str(i)];'Press space to input bad indices. To keep all peaks press any other key.'});
    hold off;
    saveas(gcf,fullfile(save_dir, ['Fig' num2str(i) '_spike_kernel','.fig']));
    tau = (-nback:nfront)*dt;
    if c > 0;
        figure;
        plot(tau, kernel);
        xlabel('Time (ms)')
        ylabel('Fluorescence (A.U.)')
        title(['Average spike waveform (n = ' num2str(c) ' spikes)'])
        saveas(gcf,fullfile(save_dir, ['Fig' num2str(i) '_avg_spike_waveform','.fig']));
        
        % input bad index for spikes
        idx = input('Input bad spike indices. [6 7] or [6:7]');
        %     idx = inputdlg('Input bad spike indices. "space" for individual, : for sequences');
        %     idc = str2num(idx{:});
        % sT2(indc) = [];
        sT(idx) = [];
        sW(idx) = [];
        Amp(idx) = [];
    end
    ns = length(sT);
    
    C(i).nspike(1) = ns;
    C(i).spikeT{1} = sT;
    C(i).spikeW{1} = sW;
    C(i).spikeA{1} = Amp;
    C(i).Tconv{1} = Tconv;
    C(i).kernel{1,2} = kernel;
    C(i).kernel{1,1} = tau';
    C(i).C=c;
end

save(fullfile(save_dir, 'inter_spikeT_spikeW.mat'),'C','nCells','dt','dAdd');

end
