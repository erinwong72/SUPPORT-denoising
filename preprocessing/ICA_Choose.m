% This is the manual input portion of Run_PCA_ICA_RMmov_FanLab_function
% Save this as Run_PCA_ICA_RMmov_FanLab_Input.m

function ICA_Choose(session_path, use_support, support_dirname)

positions = {
    [0.0, 0.5, 0.5, 0.5]; % Top-left
    [0.5, 0.5, 0.5, 0.5]; % Top-right
    [0.0, 0.0, 0.5, 0.5]; % Bottom-left
    [0.5, 0.0, 0.5, 0.5]; % Bottom-right
    };
if nargin <3
    support_dirname = 'support';
end
if use_support
    save_dir = fullfile(session_path, support_dirname);
else
    save_dir = session_path;
end
load(fullfile(save_dir, 'ICA_PreResults.mat')); % loads icsTime_all, icsTimeOrig_all, icsSpace_all, nCell, t, CellImgs, MaskMov
h = openfig(fullfile(save_dir, 'MaskTraces_RMmov.fig'), 'new', 'visible');%Raw Traces
set(h, 'Units', 'normalized', 'Position', positions{1});

IntensOrig = zeros(length(t), nCell);
ICAImgs = cell(nCell,1);


%% 
for i = 1:nCell
    icsTime = icsTime_all{i};
    icsTimeOrig = icsTimeOrig_all{i};
    icsSpace = icsSpace_all{i};
    nrowB = floor(size(CellImgs{i,1}, 1)/2);
    ncolB = floor(size(CellImgs{i,1}, 2)/2);

    is_process = 1;

    while is_process
        nIcs = size(icsSpace,2);

        %% Figures
        h = figure(7); clf;
        set(h, 'Units', 'normalized', 'Position', positions{2});
        subplot(ceil(nIcs/3),ceil(nIcs/3),1);
        imshow(mean(MaskMov{i},3),[]);title('Template')
        for j = 1:size(icsSpace,2)
            subplot(ceil(nIcs/3),ceil(nIcs/3),j+1);
            imshow2(toimg(icsSpace(:,j), nrowB, ncolB), []);
            title(j)
        end
        suptitle(['Mask #' num2str(i)]);
        saveas(gca,fullfile(save_dir, [num2str(i) 'ICAImg.fig']))

        h = figure(8); clf; set(h, 'Units', 'normalized', 'Position', positions{3});
        stackplot(icsTime(:,1:min(30, size(icsTime,2))));
        suptitle('High pass');

        h = figure(9); clf; set(h, 'Units', 'normalized', 'Position', positions{4});
        stackplot(icsTimeOrig(:,1:min(30, size(icsTimeOrig,2))));
        suptitle('Applied to Original movie');
        saveas(gca,fullfile(save_dir, [num2str(i) 'ICATrace.fig']))

        %% Options
        Best = input(['Choose best IC for cell #' num2str(i) ': (C: crop, I: invert, P: Previous IC, T: template mask) '], 's');
        BestUpper = upper(strtrim(Best));
        if strcmp(BestUpper, 'C')
            %Get user input for time regions to remove.
            % all cells or option to remove time from just one cell?
            % Rerun ICApre with cropped time
            % Get back to this function
        elseif strcmp(BestUpper, 'I')
            % Invert logic here
            Best = input(['Invert which IC for cell #' num2str(i) ':'],'s');
            BestNum = str2double(Best);

            if ~isnan(BestNum) && BestNum >= 1 && BestNum <= nIcs && mod(BestNum,1)==0
                % Valid IC index
                IntensOrig(:,i) = -icsTimeOrig(:, BestNum);
                ICAImgs{i} = toimg(-icsSpace(:, BestNum), nrowB, ncolB);
                is_process = 0;
            else
                error('Invalid input. Enter C, I, or FOV #.');
            end
        elseif strcmp(BestUpper, 'T')
            W = mean(MaskMov{i},3); %Template Weights
            W = (W - min(W(:))) / (max(W(:)) - min(W(:))); %Normalize
            

            thr = 0.4 * max(W(:));%Set Threshold
            W(W < thr) = 0;         %Zero Threshold
            %figure(); imagesc(W);

            wvec = reshape(W, 1, []);                 % 1x576
            M2   = reshape(MaskMov{1}, [], size(MaskMov{1},3)); % 576xT
            sOrig = wvec * M2;                            % 1xT
            sOrig = sOrig(:);                                 % Tx1
            sOrig = (sOrig-mean(sOrig))/std(sOrig)*60;

            % Original size
            [H, W_] = size(W);
            % Block size (example)
            bh = 2;   % rows per block
            bw = 2;   % cols per block
            % Check divisibility
            assert(mod(H,bh)==0 && mod(W_,bw)==0, 'Size not divisible by block size');
            % Reshape and average
            W_downsample = squeeze(mean(mean(reshape(W, bh, H/bh, bw, W_/bw),1), 3));            W_ds_flat = reshape(W_downsample, 1, [])';
            %figure(); hold on; plot((1:size(s,1))/1000,s);

            % High-pass the template trace - note distinct from ICA_pre implementation
            Fs = 1000;      % Hz (dt = 1 ms)
            Fc = 100;       % Hz cutoff
            [b,a] = butter(2, Fc/(Fs/2), 'high');
            sHP = filtfilt(b, a, sOrig);
            sHP = sHP/(60*2);

            % Append as an extra component
            icsSpace    = [icsSpace, W_ds_flat];     % space: (nrowB*ncolB) x (nIcs+1)
            icsTimeOrig = [icsTimeOrig, sOrig]; % time (orig): T x (nIcs+1)
            icsTime     = [icsTime, sHP];       % time (HP):   T x (nIcs+1)

        elseif strcmp(BestUpper, 'P')
            % Won't work because need to project IC onto raw trace to extract
            % signal...

            %Get Previous Path
            prev = load('ICA_PreResults.mat',{'icsTimeOrig_all','icsSpace'});
            open([num2str(i) 'ICAImg.fig']);sgtitle('Previous Recording IC''s for cell');

            

            Best = input(['Which Previous IC for cell #' num2str(i) ':'],'s');
            BestNum = str2double(Best);

            if ~isnan(BestNum) && BestNum >= 1 && BestNum <= nIcs && mod(BestNum,1)==0
                % Valid IC index
                IntensOrig(:,i) = prev.icsTimeOrig(:, BestNum);
                ICAImgs{i} = toimg(icsSpace(:, BestNum), nrowB, ncolB);
            else
                error('Invalid input. Enter C, I, or FOV #.');
            end

        else
            % Try to interpret as a number
            BestNum = str2double(BestUpper);

            if ~isnan(BestNum) && BestNum >= 1 && BestNum <= nIcs && mod(BestNum,1)==0
                % Valid IC index
                IntensOrig(:,i) = icsTimeOrig(:, BestNum);
                ICAImgs{i} = toimg(icsSpace(:, BestNum), nrowB, ncolB);
                is_process = 0;
            else
                error('Invalid input. Enter C, I, or FOV #.');
            end
        end

    end

    save(fullfile(save_dir, 'Masks_BestIcaTrace'),'IntensOrig');
    save(fullfile(save_dir, 'Masks_BestIcaImgs'),'ICAImgs','CellImgs');

    figure;
    for i = 1:nCell
        subplot(nCell+3,nCell*2,2*i-1); imshow(CellImgs{i},[]);
        subplot(nCell+3,nCell*2,2*i); imshow(ICAImgs{i},[]);
        subplot(nCell+3,nCell*2,i*nCell*2+1:(i+1)*nCell*2);
        plot(t/1000, IntensOrig(:,i), 'r'); ylabel('F'); hold on;
    end

    ai_data_path = fullfile(session_path, 'AI Data');
    try
        Bh = load(ai_data_path);
    catch ME
        % If MAT load fails (e.g., "not a binary mat-file"), try loading as ASCII
        if contains(ME.message, 'not a binary mat-file') || contains(ME.message, 'ASCII')
            try
                Bh = load(ai_data_path, '-ASCII');
            catch ME2
                error('Unable to load AI Data file as ASCII: %s\nError: %s', ai_data_path, ME2.message);
            end
        else
            % For other errors, try ASCII as fallback
            try
                Bh = load(ai_data_path, '-ASCII');
            catch ME2
                error('Unable to load AI Data file: %s\nOriginal error: %s\nASCII load error: %s', ...
                    ai_data_path, ME.message, ME2.message);
            end
        end
    end
    Bh2 = Bh(:,10+1:end); % Assumes dt = 1 ms and removal of first 10 ms
    DaqRate = 10000;
    tdaq = (1:size(Bh2,2)) / DaqRate;

    subplot(nCell+3,nCell*2,(nCell+1)*2*nCell+1:(nCell+2)*nCell*2);
    plot(tdaq, -75/75*64/0.75*(Bh2(1,:)-1.6497)/50 + 4, 'k'); hold on;
    plot(tdaq, Bh2(4,:)/5.2 + 3, 'color', [0.5,0.5,0.5]);
    plot(tdaq, Bh2(3,:)/3.2 + 2, 'r');
    plot(tdaq, Bh2(2,:)/5.2 + 1, 'c');
    %plot(tdaq, Bh2(5,:)/3.2 + 0, 'b');
    stim_protocol = get_stim_protocol(session_path);
    plot(tdaq, stim_protocol.WFAO(end-(size(Bh2,2)-1):end,1), 'b');% 10 ms offset Modified KS 11/4/25
    legend({'Velocity','TrialSynC','Reward','Lick','BlueStim'});
    xlabel('Time, sec'); ylabel('VR'); axis tight;

    saveas(gca, fullfile(save_dir, 'Fig_intens_ICA.fig'));
    saveas(gca, fullfile(save_dir, 'Fig_intens_ICA.png'));
end
