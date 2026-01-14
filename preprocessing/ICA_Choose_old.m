% This is the manual input portion of Run_PCA_ICA_RMmov_FanLab_function
% Save this as Run_PCA_ICA_RMmov_FanLab_Input.m

function ICA_Choose_support(metadata)

positions = {
    [0.0, 0.5, 0.5, 0.5]; % Top-left
    [0.5, 0.5, 0.5, 0.5]; % Top-right
    [0.0, 0.0, 0.5, 0.5]; % Bottom-left
    [0.5, 0.0, 0.5, 0.5]; % Bottom-right
};
if metadata.use_support
    save_dir = fullfile(metadata.session_path, 'support');
else
    save_dir = metadata.session_path;
end
load(fullfile(save_dir, 'ICA_PreResults.mat')); % loads icsTime_all, icsTimeOrig_all, icsSpace_all, nCell, t, CellImgs, MaskMov
h = openfig(fullfile(save_dir, 'MaskTraces_RMmov.fig'), 'new', 'visible');%Raw Traces
set(h, 'Units', 'normalized', 'Position', positions{1});

IntensOrig = zeros(length(t), nCell);
ICAImgs = cell(nCell,1);
nIcs = 10;

for i = 1:nCell
    icsTime = icsTime_all{i};
    icsTimeOrig = icsTimeOrig_all{i};
    icsSpace = icsSpace_all{i};
    nrowB = floor(size(CellImgs{i,1}, 1)/2);
    ncolB = floor(size(CellImgs{i,1}, 2)/2);

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

    % Bring command window to front for input
    commandwindow;
    Best = input(['Choose best IC for cell #' num2str(i) ': ']);
    IntensOrig(:,i) = icsTimeOrig(:,Best);
    ICAImgs{i} = toimg(icsSpace(:,Best), nrowB, ncolB);
end

save(fullfile(save_dir, 'Masks_BestIcaTrace.mat'),'IntensOrig');
save(fullfile(save_dir, 'Masks_BestIcaImgs.mat'),'ICAImgs','CellImgs');

figure;
for i = 1:nCell
    subplot(nCell+3,nCell*2,2*i-1); imshow(CellImgs{i},[]);
    subplot(nCell+3,nCell*2,2*i); imshow(ICAImgs{i},[]);
    subplot(nCell+3,nCell*2,i*nCell*2+1:(i+1)*nCell*2);
    plot(t/1000, IntensOrig(:,i), 'r'); ylabel('F'); hold on;
end

% Load AI Data - try as MAT file first, then as ASCII if that fails
ai_data_path = fullfile(metadata.session_path, 'AI Data');
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
if metadata.is_stim; stim_protocol = get_stim_protocol(metadata.session_path);
    plot(tdaq, stim_protocol.WFAO(end-(size(Bh2,2)-1):end,1), 'b');% 10 ms offset Modified KS 11/4/25
else; stim_protocol = 0;
    %plot(tdaq, 0, 'b');% 10 ms offset Modified KS 11/4/25
end
legend({'Velocity','TrialSynC','Reward','Lick','BlueStim'});
xlabel('Time, sec'); ylabel('VR'); axis tight;

saveas(gca,fullfile(save_dir, 'Fig_intens_ICA.fig'));
saveas(gca,fullfile(save_dir, 'Fig_intens_ICA.png'));
end
