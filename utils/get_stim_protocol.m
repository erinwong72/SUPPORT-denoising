function data = get_stim_protocol(targetDir,is_btsp,is_ds,stim_tresh)
% GET_STIM_PROTOCOL
% Runs ReadBinWaveFormsV1() from a subfolder under "matlab wvfm".
%
% USAGE:
%   get_stim_protocol()
%       - Legacy behavior: runs ReadBinWaveFormsV1() from the first
%         subdirectory under ./matlab wvfm, returns nothing,
%         and exports loaded variables to the *caller* (parent function).
%
%   data = get_stim_protocol(rootDir)
%       - Runs ReadBinWaveFormsV1() from first subdirectory under
%         fullfile(rootDir,'matlab wvfm') and returns a struct
%         containing variables created by the script (no exports).

%  if is_btsp, need to find stimulation times in the AIData.bin file

fs_daq = 10000;

original_path = pwd;
cleanupObj = onCleanup(@() cd(original_path)); %#ok<NASGU>

% Resolve path to the "matlab wvfm" directory
if nargin < 4
    stim_tresh = 0.1;
end
if nargin < 3
    is_ds = 0;
end
if nargin <2
    is_btsp = 0;
end

if nargin < 1
    wvfm_path = fullfile(original_path, 'matlab wvfm');
else
    wvfm_path = fullfile(targetDir, 'matlab wvfm');
end

% Find first valid subdirectory
subdirs = dir(fullfile(wvfm_path, '*'));
subdirs = subdirs([subdirs.isdir] & ~ismember({subdirs.name}, {'.', '..'}));
if isempty(subdirs)
    error('No valid subdirectories found in %s', wvfm_path);
end

% Track variables present before running the script
preVars = who;

%Get Protocol Data from Save Waveform
% Run the waveform reader in the first subdir
cd(fullfile(wvfm_path, subdirs(1).name));
ReadBinWaveFormsV1();
trace = WFAO(:,1)';

% IF btsp, also get location specific stimulation pulses
if is_btsp
    cd(targetDir);
    Bh = load('AI Data');% 1, pitch; 2, lick; 3, ValveTrig; 4, synC; % see Run_VImgTrialSynC_VRBlue_randITIspeedlimit_FanLab_functionV5 for reference
    %Bh2 = Bh(:,10*10+1:end);% remove the first 10
    
    ao = trace;
    sync = Bh(5,:);
    trace = zeros(size(sync));
    trace(sync>stim_tresh) = max(ao);
    clear Bh sync;
end

t_stim = (1:size(trace,2))/fs_daq;
dur = sum(trace>stim_tresh);
%figure(); plot(t_stim,WFAO);

if is_ds
    trace = trace(10:10:end);
    t_stim = t_stim(10:10:end);
    WFAO = WFAO(:,10:10:end);
end

% Common: figure out what was created by the script (exclude internals)
postVars = whos;
internalNames = union(preVars, ...
    {'original_path','cleanupObj','wvfm_path','subdirs', ...
     'data','vars','i','k','name','names','preVars','postVars','internalNames'});

createdNames = setdiff({postVars.name}, internalNames);

% Decide behavior based on whether caller asked for an output
legacy_mode = (nargout == 0);

if legacy_mode
    % ----------------------------
    % Legacy mode: export to parent (caller), no return value
    % ----------------------------
    for k = 1:numel(createdNames)
        assignin('caller', createdNames{k}, eval(createdNames{k}));
    end

    % If you ALSO want these computed vars in the parent, explicitly export them:
    assignin('caller','trace',trace);
    assignin('caller','t_stim',t_stim);
    assignin('caller','dur',dur);

    return;  % no data output
else
    % ----------------------------
    % New mode: return a struct of outputs
    % ----------------------------
    data = struct();
    for k = 1:numel(createdNames)
        data.(createdNames{k}) = eval(createdNames{k});
    end

    % Include your computed vars too (usually you want these in the struct)
    data.trace = trace;
    data.t_stim = t_stim;
    data.dur = dur;
end



%Backup
%{
original_path = pwd; 
wvfm_path = fullfile(original_path, 'matlab wvfm');

subdirs = dir(fullfile(wvfm_path, '*'));
subdirs = subdirs([subdirs.isdir] & ~ismember({subdirs.name}, {'.', '..'}));

if isempty(subdirs)
    error('No valid subdirectories found in %s', wvfm_path);
end

cd(fullfile(wvfm_path, subdirs(1).name))
ReadBinWaveFormsV1();
cd(original_path); % Return to original path
end
¸¸¸
%}
%{
subdirs = dir(fullfile(wvfm_path, '*'));
subdirs = subdirs([subdirs.isdir] & ~ismember({subdirs.name}, {'.', '..'}));

if isempty(subdirs)
    error('No valid subdirectories found in %s', wvfm_path);
end

cd(fullfile(wvfm_path, subdirs(1).name));
%}
%{
path1 = cd; 
cd(fullfile(path1,'matlab wvfm'))
if nargin < 1
cd(path1)
%}
