function [root_path, code_path] = setup_analysis_paths()
%SETUP_ANALYSIS_PATHS  Root paths + addpath, safe for `matlab -batch`
% (which starts with a clean path).

if ismac,      root_path = '/Volumes/fanlab';
elseif isunix, root_path = '/mnt/fanlab';
else,          root_path = 'Z:\';
end
code_path = fullfile(root_path, 'Labmembers', 'Erin', 'code');
addpath(fullfile(code_path, 'SUPPORT-denoising', 'utils'));
addpath(fileparts(mfilename('fullpath')));   % helpers next to these scripts

% get_stim_protocol runs ReadBinWaveFormsV1, which lives under Fan Lab code
if isempty(which('ReadBinWaveFormsV1'))
    safe_addpath(fullfile(root_path, 'Computer Code', 'Fan Lab'));
end
end
