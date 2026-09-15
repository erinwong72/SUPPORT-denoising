function batchPreprocess(opts)
% BATCHPREPROCESS
% Configurable preprocessing pipeline with optional SUPPORT denoising.
%
% Sessions can either be discovered automatically under opts.source_dir, or
% supplied directly through opts.session_list (e.g. a sessions struct saved
% by a previous run of discover_sessions, or one you curated by hand).
%
% ------------------------- opts fields -------------------------
% WHERE THE DATA IS (need source_dir, session_list, or both)
%   source_dir    Root(s) of the raw data tree, laid out as
%                 <root>/<anim_id>/<sess_id>/slice*/FOV*/<recording>.
%                 May be any of:
%                   char           - a single root
%                   cell of chars  - several roots, searched in turn and
%                                    concatenated, e.g.
%                                    {'/Volumes/fanlab/Labmembers/Kohl/CCK', ...
%                                     '/Volumes/fanlab/Labmembers/Erin/PC'}
%                   containers.Map - anim_id -> that animal's own folder
%                                    (i.e. <root>/<anim_id>), for animals
%                                    scattered across unrelated roots
%                 Not needed when session_list is given.
%   save_dir      char. Where discovery caches its session structs, and
%                 (discovery mode only) where sessions_for_support.txt goes.
%                 Not needed when session_list is given — in that case the
%                 SUPPORT list is written to the highest common parent of the
%                 selected session_path values. Must be reachable from the
%                 server (under /Volumes/fanlab) when use_support is true and
%                 you are not using session_list. Default: first source_dir.
%
% SESSION SELECTION (either let the pipeline discover sessions, or pass a list)
%   session_list  struct array of sessions to process, with at least
%                 session_path (and typically anim_id / slice / FOV /
%                 session_name already on each entry). When non-empty,
%                 discovery is skipped and this list is used instead (paths
%                 are still remapped to the current OS root). anim_id and
%                 sess_id are NOT required — they live on each row. Optional
%                 filters below still apply if you want to narrow the list.
%                 Default: [] (discover sessions).
%   anim_id       optional. Animal ID filter, e.g. 'cck-gtacr-w14'. Used for
%                 discovery and/or filterSessions. Default: [] (keep all).
%   sess_id       optional. Session/date filter, e.g.
%                 '01_22_2026-VR_V_Disinhibit'. Default: [] (keep all).
%   sel_slices    numeric vector of slice numbers to keep, e.g. [1 2].
%                 Default: [] (all slices).
%   sel_FOVs      numeric vector of FOV numbers to keep, e.g. [1 3].
%                 Default: [] (all FOVs).
%   sel_recs      cell array of recording folder names to keep,
%                 e.g. {'Spon30','VR1'}. Default: {} (all recordings).
%   exclude       cell array of date/folder substrings to skip during
%                 discovery, e.g. {'01_20_2026'}. Default: {}.
%   struct_save   logical scalar or [1x3]. Force-refresh flags, expanded to
%                 [1x3] if scalar:
%                   (1) re-run discovery instead of loading the session
%                       struct cached under save_dir
%                   (2) reserved (session struct regeneration)
%                   (3) overwrite an existing sessions_for_support.txt
%                 Default: true.
%
% PIPELINE CONTROL
%   prepro        [1x6] logical. Steps to run:
%                   1 motion correction (NoRMCorre -> movReg.bin)
%                   2 raw.tiff generation for SUPPORT
%                   3 SUPPORT inference on the server
%                   4 ICA preprocessing (ICA_PreResults.mat)
%                   5 ICA component selection (Fig_intens_ICA.fig)
%                   6 spike extraction (inter_spikeT_spikeW.mat)
%                 Default: all false.
%   rerun         [1x6] logical. Re-run a step even if its output already
%                 exists. Default: all false.
%   is_stim       logical. Recording includes blue-light stimulation.
%                 Default: true.
%   use_ring_bkg  logical. Ring background subtraction in ICA_Pre instead of
%                 the corner box method. Default: false.
%   use_auto_ica  logical. Auto-select the best IC per cell in ICA_Choose
%                 (score_ica_components.m) when confident, and only prompt
%                 for ambiguous cells (flagged in ICA_AutoSelect_Log.mat per
%                 session — see reviewFlaggedICA.m). Default: false.
%   auto_skip_ica logical. Only used when use_auto_ica is true. Never
%                 prompts — ambiguous cells are logged and left undecided
%                 (NaN) instead, so a whole batch can run unattended with no
%                 windows popping up. Come back later with
%                 findSkippedICACells.m + ICA_Choose(...,cell_subset) to
%                 pick those interactively. Default: false.
%
% SUPPORT (only used when use_support is true)
%   use_support   logical. Denoise with SUPPORT and read ICA inputs from the
%                 denoised outputs. Default: false.
%   support.username    char. Username on the fanlab server (for ssh).
%   support.model       char. Model name, e.g. 'CCKBC' or 'PC'.
%   support.dirname     char. Output subfolder created inside each session
%                       folder, e.g. 'support_CCKBC'.
%   support.background  0/1. Run inference in the background on the server.
%
% ------------------------- Usage -------------------------
%   % 1) discover sessions under source_dir
%   opts = struct();
%   opts.source_dir  = '/Volumes/fanlab/Labmembers/Kohl/CCK';
%   opts.anim_id     = 'cck-gtacr-w14';
%   opts.sess_id     = '01_22_2026-VR_V_Disinhibit';
%   opts.prepro      = [1 1 1 0 0 0];
%   opts.use_support = true;
%   opts.support.username   = 'knswift';
%   opts.support.model      = 'CCKBC';
%   opts.support.dirname    = 'support_CCKBC';
%   opts.support.background = 0;
%   batchPreprocess_EW(opts)
%
%   % 2) pass in an existing session list (no anim_id / sess_id / save_dir
%   %    needed — sessions_for_support.txt goes to the common parent of the
%   %    selected session_path values)
%   load('/Volumes/fanlab/Labmembers/Erin/sessions/total_sessions.mat','sessions');
%   opts = struct();
%   opts.session_list = sessions;
%   opts.sel_FOVs     = [1 2];   % optional filter on the list
%   opts.prepro       = [0 0 0 1 1 1];
%   batchPreprocess_EW(opts)
%
%   % 3) discover across several data roots, bookkeeping kept elsewhere
%   opts = struct();
%   opts.source_dir = {'/Volumes/fanlab/Labmembers/Kohl/CCK', ...
%                      '/Volumes/fanlab/Labmembers/Erin/PC'};
%   opts.save_dir   = '/Volumes/fanlab/Labmembers/Erin/sessions';
%   opts.prepro     = [1 1 0 0 0 0];
%   batchPreprocess_EW(opts)
%
% EW refactor 2026 — derived from KS / Fan Lab pipeline

%% ================= Argument handling =================
arguments
    opts (1,1) struct
end

%% ================= Defaults =================
defaults = struct( ...
    'source_dir',   [], ...
    'save_dir',     [], ...
    'anim_id',      [], ...
    'sess_id',      [], ...
    'sel_FOVs',     [], ...
    'sel_slices',   [], ...
    'exclude',      {{}}, ...
    'sel_recs',      {{}}, ...
    'struct_save', true, ...
    'prepro',       false(1,6), ...
    'rerun',        false(1,6), ...
    'use_support',  false, ...
    'support',      struct(), ...
    'is_stim',      true, ...
    'use_ring_bkg', false, ...
    'use_auto_ica', false, ...
    'auto_skip_ica', false, ...
    'session_list', [] ...
    );


opts = applyDefaults(opts, defaults);

%% ================= Validation =================
assert(~isempty(opts.source_dir) || ~isempty(opts.session_list), ...
    'Provide opts.source_dir to discover sessions, or opts.session_list to process a known set');

% source_dir may be one root, several roots, or an anim_id -> root map
source_dirs = normalizeRoots(opts.source_dir);

% bookkeeping (cached session structs, sessions_for_support.txt) defaults to
% the first data root, but can live anywhere
if isempty(opts.save_dir) && ~isempty(source_dirs) && ischar(source_dirs{1})
    opts.save_dir = source_dirs{1};
end

opts.prepro = logical(opts.prepro);
opts.rerun  = logical(opts.rerun);
assert(islogical(opts.prepro) && numel(opts.prepro)==6, ...
    'opts.prepro must be logical [1×6]');
assert(islogical(opts.rerun) && numel(opts.rerun)==6, ...
    'opts.rerun must be logical [1×6]');

% struct_save may be given as a scalar flag or as [1×3]
opts.struct_save = logical(opts.struct_save);
if isscalar(opts.struct_save)
    opts.struct_save = repmat(opts.struct_save, 1, 3);
end
assert(numel(opts.struct_save)==3, ...
    'opts.struct_save must be a logical scalar or [1×3]');

if ~isempty(opts.session_list)
    assert(isstruct(opts.session_list), ...
        'opts.session_list must be a struct array of sessions');
    assert(isfield(opts.session_list,'session_path'), ...
        'opts.session_list must have a session_path field');
end

if opts.use_support
    req = {'username','model','dirname','background'};
    for k = 1:numel(req)
        assert(isfield(opts.support,req{k}), ...
            'opts.support.%s is required when use_support=true', req{k});
    end
    % discovery mode needs somewhere to put sessions_for_support.txt;
    % session_list mode writes it to the common parent of session paths
    if isempty(opts.session_list)
        assert(~isempty(opts.save_dir), ...
            ['opts.save_dir must be provided when use_support=true without ' ...
             'session_list — it is where sessions_for_support.txt is written']);
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

%% ---------------- Session selection ----------------
% use opts.session_list if provided, otherwise discover sessions on disk
if ~isempty(opts.session_list)
    fprintf('Using provided session_list (%d sessions)\n', numel(opts.session_list));
    total_sessions = opts.session_list;
else
    total_sessions = struct([]);
    for r = 1:numel(source_dirs)
        root = source_dirs{r};
        save_opts = struct('save_dir', opts.save_dir);
        if numel(source_dirs) > 1
            % one cache per root so the roots don't overwrite each other
            save_opts.save_name = sprintf('sessions_for_preprocess_%s.mat', rootTag(root));
            fprintf('Discovering sessions under %s\n', rootTag(root));
        end

        found = discover_sessions(root, opts.anim_id, opts.sess_id, ...
            save_opts, opts.exclude, opts.struct_save(1), false);

        if isempty(found); continue; end
        if isempty(total_sessions)
            total_sessions = found;
        else
            total_sessions = [total_sessions, found]; %#ok<AGROW>
        end
    end
end

if isempty(total_sessions)
    warning('No sessions found in the requested data root(s) — nothing to do.');
    return
end

sessions_all = convert_struct_paths(total_sessions, root_path);
sel_sessions = filterSessions(sessions_all, 'anim_id', opts.anim_id, 'sess_id', opts.sess_id, ...
                            'slice', opts.sel_slices, 'FOV', opts.sel_FOVs, ...
                            'session_name', opts.sel_recs);

if isempty(sel_sessions)
    warning('No sessions matched the requested selection — nothing to do.');
    return
end


%% ---------------- SUPPORT prep ----------------
% subfolder written inside each session folder; also used by ICA steps below
if opts.use_support
    support_dirname = opts.support.dirname;
else
    support_dirname = 'support';
end

% sessions_for_support.txt location:
%   session_list  -> highest common parent of the selected session_path values
%   discovery     -> save_dir[/anim_id[/sess_id]] when those filters are set
if ~isempty(opts.session_list)
    support_root = commonParentPath({sel_sessions.session_path});
else
    support_root = fullfile(opts.save_dir, asChar(opts.anim_id), asChar(opts.sess_id));
end

if opts.use_support
    support_file = fullfile(support_root, 'sessions_for_support.txt');

    if ~isfile(support_file) || opts.struct_save(3)
        fprintf('Creating %s\n', support_file);

        if ~isfolder(support_root); mkdir(support_root); end
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

    %% 2) SUPPORT tiff generation (legacy — skip unless needed)
    % Inference now reads movReg.bin directly. Only run this if you still
    % need raw.tiff for an older inference.py / external tool.
    % if opts.prepro(2)
    %     out_dir = fullfile(session_path, support_dirname);
    %     if ~isfolder(out_dir); mkdir(out_dir); end
    %     raw_tiff = fullfile(out_dir, 'raw.tiff');
    %     if ~isfile(raw_tiff) || opts.rerun(2)
    %         Info = textscan(fopen(fullfile(session_path,'experimental_parameters.txt')),'%s');
    %         nrow = str2double(Info{1}{6});
    %         ncol = str2double(Info{1}{3});
    %         [movReg,~] = readBinMov(fullfile(session_path,'movReg.bin'),ncol,nrow);
    %         saveastiff(double(movReg), raw_tiff, struct('overwrite',true,'big',true));
    %     end
    % end
end

%% 3) SUPPORT inference (server) — loads movReg.bin (falls back to raw.tiff)
if opts.use_support && opts.prepro(3)
    missing = {};
    for s = 1:numel(sel_sessions)
        if ~isfile(fullfile(sel_sessions(s).session_path, 'movReg.bin'))
            missing{end+1} = sel_sessions(s).session_path; %#ok<AGROW>
        end
    end
    if ~isempty(missing)
        warning('%d session(s) lack movReg.bin — run prepro(1) first. Example: %s', ...
            numel(missing), missing{1});
    end

    data_path = support_root;
    if ispc
        data_path = strrep(strrep(data_path,'Z:','/Volumes/fanlab'),'\\','/');
    end

    run_inference(opts.support.username, data_path, opts.support.model, ...
        support_dirname, opts.support.background, opts.rerun(3));
end

%% 4–6) ICA + Spike Thresholding
blueStim = iff(opts.is_stim,'AO','');
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    fprintf('\n=== Processing: %d/%d %s ===\n', s, numel(sel_sessions), session_path);

    if opts.use_support
        save_dir = fullfile(session_path, support_dirname);
    else
        save_dir = session_path;
    end

    if any(opts.prepro(4:5)) && (~opts.use_support || isfile(fullfile(save_dir,'denoised.tiff')))
        if opts.prepro(4) && (~isfile(fullfile(save_dir,'ICA_PreResults.mat')) || opts.rerun(4))
            ICAPre_opts = struct( ...
                'session_path', session_path, ...
                'is_stim', opts.is_stim, ...
                'use_ring_bkg', opts.use_ring_bkg, ...
                'use_support', opts.use_support, ...
                'support_dirname', support_dirname ...
            );
            ICA_Pre_multiple_rec(ICAPre_opts);
        end
        if opts.prepro(5) && (~isfile(fullfile(save_dir,'Fig_intens_ICA.fig')) && (~isfile(fullfile(save_dir, 'Masks_BestIcaTrace.mat'))) || opts.rerun(5))
            ICA_Choose(session_path, opts.use_support, support_dirname, 0, opts.use_auto_ica, opts.auto_skip_ica);
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

function roots = normalizeRoots(source_dir)
% Return data roots as a cell array: {} when none, {map} for a containers.Map
% (discover_sessions handles the animal -> root lookup itself)
if isempty(source_dir)
    roots = {};
elseif isa(source_dir, 'containers.Map')
    roots = {source_dir};
elseif iscell(source_dir)
    roots = cellfun(@char, source_dir, 'UniformOutput', false);
else
    roots = {char(source_dir)};
end
end

function tag = rootTag(root)
% Filename-safe short tag for a data root, so cached session structs from
% different roots don't collide in a shared save_dir
if isa(root, 'containers.Map'); tag = 'map'; return; end
parts = split(string(root), {'/','\',':'});
parts = parts(strlength(parts) > 0);
tag = char(matlab.lang.makeValidName(strjoin(parts(max(1,end-1):end), '_')));
end

function root = commonParentPath(paths)
% Longest common directory prefix of a cell array of paths.
% Cheap: O(n * depth). Empty -> ''; one path -> that path.
paths = paths(:);
paths = paths(~cellfun(@isempty, paths));
if isempty(paths)
    root = '';
    return
end
% normalize separators so Windows/Mac/Linux paths compare cleanly
norm = cellfun(@(p) strrep(char(p), '\', '/'), paths, 'UniformOutput', false);
parts = cellfun(@(p) strsplit(p, '/'), norm, 'UniformOutput', false);

n = min(cellfun(@numel, parts));
keep = 0;
for i = 1:n
    tok = parts{1}{i};
    if all(cellfun(@(p) strcmp(p{i}, tok), parts))
        keep = i;
    else
        break
    end
end
assert(keep >= 1, ...
    'Selected session_path values share no common parent directory');
root = strjoin(parts{1}(1:keep), filesep);
end

function out = asChar(x)
% Coerce an id (char, string, or 1-element cell) to char; '' when empty
if isempty(x)
    out = '';
elseif iscell(x)
    assert(isscalar(x), 'Only one anim_id / sess_id can be used to build SUPPORT paths');
    out = char(x{1});
else
    out = char(x);
end
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
