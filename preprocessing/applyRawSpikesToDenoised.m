function applyRawSpikesToDenoised(session_path, use_template_ica, support_dirname)
%APPLYRAWSPIKESTODENOISED  Build inter_spikeT_spikeW.mat for a denoised
% (SUPPORT) trace by reusing only the spike TIMES already found on the
% noisy/original (non-SUPPORT) trace, then recomputing amplitude and width
% from the denoised trace itself — fitting the same Gaussian used in
% Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_withpath.m to a window
% around each raw spike time, but on the denoised trace's background-
% corrected/smoothed signal (Tconv) instead of the raw one.
%
% This skips only the interactive parts of that pipeline — the
% getpts() threshold pick, spikefind3Linlin() detection, and the
% input()-driven bad-spike-index cleanup — because spike timing (already
% curated when detection was run on the noisy trace) is taken as given.
% Everything else (baseline removal, smoothing, per-spike Gaussian fit for
% amplitude/width, average waveform kernel) runs on the denoised trace, so
% it is safe to call unattended (matlab -batch).
%
% applyRawSpikesToDenoised(session_path, support_dirname, use_template_ica)
%
%   session_path       recording folder. Must already contain
%                       inter_spikeT_spikeW.mat at its root, from running
%                       spike detection on the non-SUPPORT (noisy) trace.
%   support_dirname     e.g. 'support_no_stim_model' or 'support_with_stim'
%   use_template_ica   (optional, default false) read the denoised trace
%                       from
%                       <support_dirname>/template_mask_results/Masks_BestIcaTrace_template.mat
%                       when true, else <support_dirname>/Masks_BestIcaTrace.mat

if nargin < 3
    support_dirname = '';
end
if nargin < 2
    use_template_ica = false;
end
if isempty(support_dirname)
    save_dir = fullfile(session_path);
else
    save_dir = fullfile(session_path, support_dirname);
end
raw_file = fullfile(session_path, 'inter_spikeT_spikeW.mat');
assert(isfile(raw_file), ...
    'Raw (non-SUPPORT) spike file not found: %s — run spike detection on the noisy trace first.', raw_file);

if use_template_ica
    trace_file = fullfile(save_dir, 'template_mask_results', 'Masks_BestIcaTrace_template.mat');
    save_dir = fullfile(save_dir, 'template_mask_results');
else
    trace_file = fullfile(save_dir, 'Masks_BestIcaTrace.mat');
    save_dir = fullfile(save_dir);
end
assert(isfile(trace_file), ...
    'Denoised trace file not found: %s — run ICA_Choose for this model first.', trace_file);

raw = load(raw_file, 'C', 'nCells', 'dt');
denoised = load(trace_file, 'IntensOrig');

nCells = raw.nCells;
assert(size(denoised.IntensOrig,2) == nCells, ...
    'Cell count mismatch: raw has %d cells, denoised trace (%s) has %d', ...
    nCells, trace_file, size(denoised.IntensOrig,2));

dt = raw.dt;
nFramesDenoised = size(denoised.IntensOrig,1);

% Same constants as Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_withpath.m
initial_frame = 1;
bkgd_interp_width = 10;
smpix = 9;
sigma = 0.8;
nback = 20;
nfront = 30;
% dAdd (optogenetic-stim correction) is always 0 here: the live 'AO' branch
% of Run_ext_spike_..._withpath.m that this pipeline uses has its actual
% correction logic commented out and always leaves dAdd at 0.
dAdd = 0; %#ok<NASGU>

x = -ceil((smpix-1)/2):ceil((smpix-1)/2);
f_sm = exp(-x.^2/(2*sigma^2));
f_sm = f_sm/sum(f_sm);
lensm = (length(f_sm)-1)/2;

C = raw.C;
for i = 1:nCells
    sT = C(i).spikeT{1};

    outOfRange = sT < 1 | sT > nFramesDenoised;
    if any(outOfRange)
        warning('applyRawSpikesToDenoised:outOfRange', ...
            '%s: cell %d has %d spike time(s) beyond the denoised trace''s %d frames — dropping them.', ...
            session_path, i, sum(outOfRange), nFramesDenoised);
        sT = sT(~outOfRange);
    end

    %% Recompute Tconv from the denoised trace (mirrors the raw pipeline)
    TracesOrig = denoised.IntensOrig(:,i);
    TracesN = mat2gray(TracesOrig) + 1;
    Traces = TracesN ./ prctile(TracesN, 10);
    Traces = Traces(initial_frame:end, :);
    nframe = size(Traces,1);
    FramesPerStep = nframe;

    bkgd = medfilt2(Traces, [bkgd_interp_width 1], 'symmetric');
    Tmed = Traces ./ bkgd;
    Tconv = conv([ones(1,lensm)*Tmed(1), Tmed', ones(1,lensm)*Tmed(end)], f_sm, 'valid');

    Sm = ceil(FramesPerStep/30);
    Tconv_bkgd = smooth(ordfilt2(Tconv, round(0.1*Sm), ones(1,Sm), 'symmetric'), Sm);
    Tconv = Tconv./Tconv_bkgd';
    Tconv = Tconv/mean(Tconv);
    Tstep = Tconv;

    %% Per-spike Gaussian fit for amplitude + width (mirrors the raw pipeline)
    ns = numel(sT);
    sT2 = zeros(1,ns);
    sW = nan(1,ns);
    Amp = nan(1,ns);
    kernel = zeros(nback+nfront+1, 1);
    c = 0;
    fitFailed = false(1,ns);

    for k = 1:ns
        Frame = max([1, sT(k)-lensm]):min([length(Tstep), sT(k)+lensm]);
        Peak = Tstep(Frame);
        Time = Frame - sT(k);
        try
            ffun = fittype('1 + A*exp(-4*log(2)*(x-t0)^2/w^2)');
            fopt = fitoptions('Method','NonlinearLeastSquares', ...
                'Lower',[0, -lensm, 1], ...
                'Upper',[max(1.5*(max(Peak)-1), 1e-6), lensm, 2*lensm+1], ...
                'StartPoint',[max(max(Peak)-1, 0), 0, lensm/2]);
            peak_fit = fit(Time',Peak',ffun,fopt);
            sT2(k) = sT(k) + peak_fit.t0;
            Amp(k) = peak_fit.A;
            sW(k) = peak_fit.w;
        catch ME
            fitFailed(k) = true;
            warning('applyRawSpikesToDenoised:fitFailed', ...
                '%s: cell %d spike at frame %d failed to fit on the denoised trace (%s) — leaving amplitude/width as NaN.', ...
                session_path, i, sT(k), ME.message);
            sT2(k) = sT(k);
        end

        if (sT(k) > nback) && ((sT(k) + nfront) <= length(Tstep))
            kernel = kernel + Traces((sT(k)-nback):(sT(k)+nfront), 1);
            c = c + 1;
        end
    end
    if any(fitFailed)
        warning('applyRawSpikesToDenoised:fitFailed', ...
            '%s: cell %d — %d/%d spike(s) failed to fit on the denoised trace.', ...
            session_path, i, sum(fitFailed), ns);
    end
    if c > 0
        kernel = kernel/c;
    end
    tau = (-nback:nfront)*dt;

    C(i).nspike(1) = ns;
    C(i).spikeT{1} = sT;
    C(i).spikeW{1} = sW;
    C(i).spikeA{1} = Amp;
    C(i).Tconv{1} = Tconv;
    C(i).kernel{1,2} = kernel;
    C(i).kernel{1,1} = tau';
    C(i).C = c;
end

save(fullfile(save_dir, 'inter_spikeT_spikeW.mat'), 'C', 'nCells', 'dt', 'dAdd');
end
