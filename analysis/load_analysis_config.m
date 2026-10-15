function cfg = load_analysis_config(config)
%LOAD_ANALYSIS_CONFIG  Resolve the analysis config used by every analysis script.
%
%   cfg = load_analysis_config()             % the only config in configs/analysis, if there is just one
%   cfg = load_analysis_config('my_config')  % feval('my_config'): any function on
%                                            % the path that returns a cfg struct
%   cfg = load_analysis_config(cfg_struct)   % already a cfg, returned unchanged
%
% Configs live in <code>/configs/analysis/ (added to the path here); any other
% function on the path works too.
%
% To analyse another preparation, copy a file in configs/analysis/ to e.g. config_pharm.m
% (rename the function inside to match), edit it (at least cfg.save_subdir /
% cfg.filestr so outputs do not overwrite each other, cfg.models, and
% cfg.sessions_file), then call e.g. support_model_comparison('config_pharm').
% <code>/configs/analysis, three levels up from this file (code/SUPPORT-denoising/analysis)
config_dir = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'configs', 'analysis');
if isfolder(config_dir), addpath(config_dir); end
if nargin < 1 || isempty(config)
    found = dir(fullfile(config_dir, '*.m'));
    names = erase(string({found.name}), '.m');
    assert(~isempty(names), 'No config given and none found in %s.', config_dir);
    assert(isscalar(names), 'Specify a config (e.g. support_model_comparison(''%s'')). Available: %s', ...
        names(1), strjoin(names, ', '));
    config = char(names);
end
if isstruct(config)
    cfg = expand_placeholders(fill_defaults(config));
    return
end
name = char(config);
if endsWith(name, '.m'), name = name(1:end-2); end
assert(exist(name, 'file') == 2, ...
    'Config "%s" not found on the MATLAB path (expected %s.m returning a cfg struct).', name, name);
cfg = feval(name);
assert(isstruct(cfg), 'Config "%s" must return a struct.', name);
cfg = expand_placeholders(fill_defaults(cfg));
end

function cfg = expand_placeholders(cfg)
% {dataset} -> the dataset name and {psnr} -> 'psnr<cutoff>' (or '' when there is no cutoff) in
% cfg.sessions_file and cfg.psnr_audit_dir, e.g.
%   'SUPPORT-denoising/datasets/{dataset}/total_sessions_{psnr}.mat' -> .../BTSP/total_sessions_psnr17.mat
%
% Several datasets: cfg.dataset = {'DSI','BTSP'} and (optionally) cfg.psnr_cutoff = {15, 17}, one cutoff per
% dataset (a single value applies to all; [] = none). cfg.sessions_file / cfg.psnr_audit_dir then become
% cellstrs with one path per dataset, and the sessions of all datasets are pooled (load_session_list.m).
% cfg.dataset_list is the dataset names as a cellstr. Paths in cfg.training_windows are NOT expanded when
% there are several datasets (give them explicitly, one csv per model).
ds = cfg.dataset;
if isempty(ds), ds = {''}; elseif ~iscell(ds), ds = {char(ds)}; else, ds = cellfun(@char, ds, 'UniformOutput', false); end
n = numel(ds);
cut = cfg.psnr_cutoff;
if ~iscell(cut), cut = repmat({cut}, 1, n); end
assert(numel(cut) == n, 'cfg.psnr_cutoff must be a single value or one per dataset (%d datasets).', n);
tags = cell(1, n);
for i = 1:n
    tags{i} = '';
    if ~isempty(cut{i})
        if isnumeric(cut{i}), tags{i} = sprintf('psnr%g', cut{i});
        else, tags{i} = char(cut{i}); if ~startsWith(tags{i}, 'psnr'), tags{i} = ['psnr' tags{i}]; end
        end
    end
end
cfg.dataset_list = ds;
cfg.sessions_file = fill_paths(cfg.sessions_file, ds, tags);
cfg.psnr_audit_dir = fill_paths(cfg.psnr_audit_dir, ds, tags);
for i = 1:size(cfg.training_windows, 1)
    if n > 1
        assert(~contains(char(cfg.training_windows{i, 2}), {'{dataset}', '{psnr}'}), ...
            'cfg.training_windows paths cannot use {dataset}/{psnr} with several datasets: give the csv path explicitly.');
    else
        cfg.training_windows{i, 2} = fill_paths(cfg.training_windows{i, 2}, ds, tags);
    end
end
end

function out = fill_paths(p, ds, tags)
% one path per dataset (a cellstr), or a single char path when there is nothing to vary
if ~(ischar(p) || isstring(p)) || isempty(p), out = p; return; end
p = char(p);
out = cell(1, numel(ds));
for i = 1:numel(ds)
    q = p;
    if contains(q, '{dataset}')
        assert(~isempty(ds{i}), 'Path "%s" uses {dataset} but cfg.dataset is empty.', q);
        q = strrep(q, '{dataset}', ds{i});
    end
    q = strrep(q, '{psnr}', tags{i});
    out{i} = regexprep(q, '(?<!:)/{2,}', '/');   % an empty {psnr} segment can leave a double slash
end
if numel(unique(out)) == 1, out = out{1}; end
end

function cfg = fill_defaults(cfg)
% fields added after older configs were written
if ~isfield(cfg, 'sessions_file'), cfg.sessions_file = ''; end
if ~isfield(cfg, 'dataset'), cfg.dataset = ''; end                 % dataset folder name under SUPPORT-denoising/datasets
if ~isfield(cfg, 'psnr_cutoff'), cfg.psnr_cutoff = []; end         % e.g. 17 -> 'psnr17' for {psnr}; [] = none
if ~isfield(cfg, 'reuse_psnr_audit'), cfg.reuse_psnr_audit = true; end
if ~isfield(cfg, 'psnr_audit_dir'), cfg.psnr_audit_dir = 'SUPPORT-denoising/datasets/{dataset}/psnr_audit'; end
if ~isfield(cfg, 'exclude_cell_if_any_artifact'), cfg.exclude_cell_if_any_artifact = false; end
if ~isfield(cfg, 'training_windows'), cfg.training_windows = {}; end
if ~isfield(cfg, 'stim_mode'), cfg.stim_mode = 'all'; end
if ~isfield(cfg, 'sel_sessions'), cfg.sel_sessions = {}; end
if ~isfield(cfg, 'invert_sel_sessions'), cfg.invert_sel_sessions = false; end
% single-pixel SNR over the template-footprint pixels, next to the spike PSNR (support_model_comparison.m)
if ~isfield(cfg, 'pixel_snr'), cfg.pixel_snr = false; end                  % true: also compute it (reads every movie: slow)
if ~isfield(cfg, 'pixel_skip_frames'), cfg.pixel_skip_frames = 10; end     % first frames ICA_Pre.m drops (10 ms at 1 kHz)
end
