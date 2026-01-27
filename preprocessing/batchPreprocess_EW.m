function batchPreprocess(opts)
% BATCHPREPROCESS
% Configurable preprocessing pipeline with optional SUPPORT denoising.
%
% Usage:
%   opts = struct();
%   opts.source_dir = '/Volumes/fanlab/Labmembers/Kohl/CCK';
%   opts.anim_id    = {'cck-gtacr-w14'};
%   opts.sess_id    = {'01_22_2026-VR_V_Disinhibit'};
%   opts.prepro     = [1 1 1 0 0 0];
%   opts.use_support = true;
%   opts.support.username  = 'knswift';
%   opts.support.model     = 'cck-gevi';
%   opts.support.dirname  = 'support_CCKBC';
%   opts.support.background = 0;
%
%   batchPreprocess(opts)
%
% EW refactor 2026 — derived from KS / Fan Lab pipeline

%% ================= Argument handling =================
arguments
    opts (1,1) struct
end

%% ================= Defaults =================
defaults = struct( ...
    'source_dir',   [], ...
    'anim_id',      [], ...
    'sess_id',      [], ...
    'sel_FOVs',     [], ...
    'sel_slices',   [], ...
    'exclude',      {{}}, ...
    'create_sess', true, ...
    'prepro',       false(1,6), ...
    'rerun',        false(1,6), ...
    'use_support',  false, ...
    'support',      struct(), ...
    'is_stim',      true, ...
    'use_ring_bkg', false ...
);

opts = applyDefaults(opts, defaults);

%% ================= Validation =================
assert(~isempty(opts.source_dir), 'opts.source_dir must be provided');
assert(~isempty(opts.anim_id),    'opts.anim_id must be provided');
assert(~isempty(opts.sess_id),    'opts.sess_id must be provided');
opts.prepro = logical(opts.prepro);
opts.rerun  = logical(opts.rerun);
assert(islogical(opts.prepro) && numel(opts.prepro)==6, ...
    'opts.prepro must be logical [1×6]');
assert(islogical(opts.rerun) && numel(opts.rerun)==6, ...
    'opts.rerun must be logical [1×6]');

if opts.use_support
    req = {'username','model','dirname','background'};
    for k = 1:numel(req)
        assert(isfield(opts.support,req{k}), ...
            'opts.support.%s is required when use_support=true', req{k});
    end
end


%% ---------------- OS + root paths ----------------
if ismac || isunix
    root_path = '/Volumes/fanlab';
elseif ispc
    root_path = 'Z:';
end

%% ---------------- Add required paths ----------------
safe_addpath(fullfile(root_path,'Computer Code','Image Processing'));
safe_addpath(fullfile(root_path,'Computer Code','NoRmCorre'));
safe_addpath(fullfile(root_path,'Computer Code','Fan Lab','1extract-voltage-imaging-signal'));

%% ---------------- Session discovery ----------------
total_sessions = discover_sessions(opts.source_dir, opts.anim_id,opts.source_dir, opts.exclude, opts.create_sess);

sessions_all = convert_struct_paths(total_sessions, root_path);
sel_sessions = generate_sessions_struct(sessions_all, struct('save_dir', {opts.source_dir}, 'anim_id',{opts.anim_id}, 'sess_id',{opts.sess_id}), opts.sel_FOVs, opts.sel_slices);

%% ---------------- SUPPORT prep ----------------
if opts.use_support
    sp = opts.support;
    assert(all(isfield(sp,{'username','model','background','dirname'})), ...
        'support.username / model / background / dirname required');

    support_file = fullfile( ...
        opts.source_dir, opts.anim_id, opts.sess_id, ...
        'sessions_for_support.txt');

    if ~isfile(support_file) || opts.create_sess
        fprintf('Creating sessions_for_support.txt\n');

        session_paths = {sel_sessions.session_path};

        fid = fopen(support_file,'w');
        assert(fid>0, 'Failed to create sessions_for_support.txt');

        fprintf(fid,'%s\n', session_paths{:});
        fclose(fid);
    else
        fprintf('sessions_for_support.txt already exists — skipping write\n');
    end
end

%% ---------------- Main loop ----------------
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    fprintf('\n=== Processing: %s ===\n', session_path);

    if opts.use_support
        save_dir = fullfile(session_path, opts.support.dirname);
    else
        save_dir = session_path;
    end

    %% 1) Motion correction
    if opts.prepro(1) && (~isfile(fullfile(session_path,'movReg.bin')) || opts.rerun(1))
        try
            Info = textscan(fopen(fullfile(session_path,'experimental_parameters.txt')),'%s');
            nrow = str2double(Info{1}{6});
            ncol = str2double(Info{1}{3});
            [mov,~] = readBinMov(fullfile(session_path,'Sq_camera.bin'),nrow,ncol);
            movReg = NoRMCorre2(mov);
            savebin(vm(movReg), fullfile(session_path,'movReg.bin'));
        catch ME
            warning('Motion correction failed: %s',ME.message);
        end
    end

    %% 2) SUPPORT tiff generation
    if opts.prepro(2)
        raw_tiff = fullfile(save_dir,'raw.tiff');
        if ~isfile(raw_tiff) || opts.rerun(2)
            Info = textscan(fopen(fullfile(session_path,'experimental_parameters.txt')),'%s');
            nrow = str2double(Info{1}{6});
            ncol = str2double(Info{1}{3});
            [movReg,~] = readBinMov(fullfile(session_path,'movReg.bin'),ncol,nrow);
            saveastiff(double(movReg), raw_tiff, struct('overwrite',true,'big',true));
        end
    end
end

%% 3) SUPPORT inference (server)
if opts.use_support && opts.prepro(3)
    data_path = fullfile(opts.source_dir, opts.anim_id, opts.sess_id);
    if ispc
        data_path = strrep(strrep(data_path,'Z:','/Volumes/fanlab'),'\\','/');
    end

    run_inference(opts.support.username, data_path, opts.support.model, ...
        opts.support.dirname, opts.support.background, opts.rerun(3));
end

%% 4–6) ICA + Spike Thresholding
blueStim = iff(opts.is_stim,'AO','');
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    if opts.use_support
        save_dir = fullfile(session_path, opts.support.dirname);
    else
        save_dir = session_path;
    end

    if any(opts.prepro(4:5)) && (~opts.use_support || isfile(fullfile(save_dir,'denoised.tiff')))
        if opts.prepro(4) && (~isfile(fullfile(save_dir,'ICA_PreResults.mat')) || opts.rerun(4))
            ICA_Pre(session_path, opts.is_stim, opts.use_ring_bkg, opts.use_support, opts.support.dirname);
        end
        if opts.prepro(5) && (~isfile(fullfile(save_dir,'Fig_intens_ICA.fig')) || opts.rerun(5))
            ICA_Choose(session_path, opts.use_support, opts.support.dirname);
        end
        close all;
    end

    if opts.prepro(6) && (~isfile(fullfile(save_dir,'inter_spikeT_spikeW.mat')) || opts.rerun(6))
        openfig(fullfile(save_dir,'Fig_intens_ICA.fig'));
        Run_ext_spike_HipCA1VR_AIBluecrt_FanLab_functionV6_withpath(blueStim, session_path, opts.use_support);
        close all
    end
end

fprintf('\n✔ Batch preprocessing complete.\n');
end
%% --- Helper functions ---
function out = iff(cond,a,b)
if cond; out=a; else; out=b; end
end

function opts = applyDefaults(opts, defaults)
% Apply defaults to an options struct without overwriting user values
f = fieldnames(defaults);
for i = 1:numel(f)
    if ~isfield(opts,f{i}) || isempty(opts.(f{i}))
        opts.(f{i}) = defaults.(f{i});
    end
end
end
