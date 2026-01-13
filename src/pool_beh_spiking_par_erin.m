function [sessions] = pool_beh_spiking_par_erin(varargin)
%Function to process many recordings from a behavioral session
%Inputs: base_path - path to slice to be analyzed
%Outputs: sessions - struct of each session
sessions = [];
p = inputParser;
addParameter(p, 'base_path', '', @ischar);
addParameter(p, 'FOVs', [], @isnumeric);
addParameter(p, 'blueStim', 'AO', @ischar);
addParameter(p, 'sess_ids', {});

parse(p, varargin{:});
base_path = p.Results.base_path;
FOVs = p.Results.FOVs;
blueStim = p.Results.blueStim;
sess_ids = p.Results.sess_ids;

%% Session Parameters
%base_path = sprintf('/Volumes/fanlab/Labmembers/Kohl/CCK/%s/%s/%s',anim_id,sess_id,slice_id);
parts = strsplit(base_path, filesep);
anim_id = parts{end-2}; %'cck-gevi-w05';
sess_id = parts{end-1}; %'Running9_15_2025';
slice_id = parts{end}; %'slice1';

if isempty(FOVs)
    all_entries = dir(base_path);
    fov_dirs = all_entries([all_entries.isdir] & startsWith({all_entries.name}, 'FOV'));
    for k = 1:length(fov_dirs)
        num = sscanf(fov_dirs(k).name, 'FOV%d');
        if ~isempty(num); FOVs(end+1) = num; end
    end
end

%% Set Parameters
target_file = 'inter_spikeT_spikeW.mat';

% Get all valid subdir paths before parfor
session_list = struct('anim_id',{},'FOV', {}, 'subdir_path', {}, 'subdir_name', {}, 'cell_id', {},'num_cells', {});
for k = FOVs
    fov_path = fullfile(base_path, sprintf('FOV%d', k));
    dirs = dir(fov_path);
    dirs = dirs([dirs.isdir] & ~ismember({dirs.name}, {'.', '..'}));
    for i = 1:numel(dirs)
        if isempty(sess_ids) || contains({dirs(i).name}, sess_ids)
            subdir_path = fullfile(fov_path, dirs(i).name);
            target_path = fullfile(subdir_path, target_file);
            if isfile(target_path)
                load(target_path, "nCells");
                for cell_id = 1:nCells
                    session_list(end+1) = struct( ...
                        'anim_id', anim_id,...
                        'FOV', k, ...
                        'subdir_path', subdir_path, ...
                        'subdir_name', dirs(i).name, ...
                        'cell_id', cell_id, ...
                        'num_cells', nCells ...
                        );
                end
            end
        end
        
    end
end

%% Processing Loop
if ~isempty(session_list)
    n_sessions = numel(session_list);
    sessions_local = cell(1, n_sessions); % for parallel write
    fprintf('Processing %d total sessions...\n', n_sessions);
    tic;
    
    isDebug = 0;
    if isDebug
        idx = 1;
        entry = session_list(idx);
        beh_spiking(entry.subdir_path, entry.cell_id, 1);
    end
    
    for idx = 1:n_sessions
        entry = session_list(idx);
        try
            % Store locally
            sess = struct();
            sess.anim_id = entry.anim_id;
            sess.session_path = entry.subdir_path;
            sess.session_name = entry.subdir_name;
            sess.FOV = entry.FOV;
            sess.cell_id = entry.cell_id;
            sess.fov_num_cells = entry.num_cells;
            sess.cell_hash = gen_cell_hash(sess.session_path,sess.cell_id);
            [sess.beh, sess.spik,sess.sub_t] = load_voltage_and_beh(entry.subdir_path, 'cellID', entry.cell_id,'isPlot',1);
            close all;
    
            %Metrics
            sess.nspikes = sess.spik.nspike;
            sess.snr = sess.sub_t.norm.snr;
            sess.fr = sess.spik.fr;
            sess.mean_width = sess.spik.meanWidth;
            sess.fwhm = sess.spik.fwhm;
    
            %Conditions
            is_run = sess.beh.run(1:size(sess.sub_t.trace.raw,1))';
            is_still = sess.beh.still(1:size(sess.sub_t.trace.raw,1));
            sess.fr_run = mean(sess.spik.smooth(is_run),'omitnan');
            sess.fr_still = mean(sess.spik.smooth(is_still),'omitnan');
            sess.theta_amp_run = mean(sess.sub_t.theta.power(is_run),'omitnan');
            sess.theta_amp_still = mean(sess.sub_t.theta.power(is_still),'omitnan');
    
            sessions_local{idx} = sess;
        
            fprintf('✓ [%d/%d] Success: %s Cell %d\n', idx, n_sessions, entry.subdir_name, entry.cell_id);
        catch ME
            fprintf('✗ [%d/%d] Failed: %s Cell %d — %s\n', idx, n_sessions, entry.subdir_name, entry.cell_id, ME.message);
        end
    end
    
    elapsed = toc;
    fprintf('Finished all sessions in %.1f seconds (%.1f minutes).\n', elapsed, elapsed/60);
    
    sessions = [sessions_local{:}];
    
    %% Normalized Firing Rate
    % Get unique cells
    unique_cells = unique({sessions.cell_hash});
    num_cells = length(unique_cells);
    
    % Loop through each unique cell
    for c_i = 1:num_cells
        cell_id = unique_cells{c_i};
    
        % Get indices of sessions containing current cell
        coi = find(strcmp({sessions.cell_hash}, cell_id));
        num_sess = length(coi);
    
        % Collect firing rates for all sessions of current cell
        full_fr = [];
        for s_i = 1:num_sess
            full_fr = [full_fr, sessions(coi(s_i)).spik.smooth];
        end
    
        % Z-Score Firing Rates
        mean_fr = mean(full_fr);
        std_fr = std(full_fr);
    
        % Store computed values in each session and compute Z-scored data
        for s_i = 1:num_sess
            spik = sessions(coi(s_i)).spik;
    
            spik.mean_fr = mean_fr;
            spik.std_fr = std_fr;
            spik.smooth_z = (spik.smooth - mean_fr) / std_fr;
    
            sessions(coi(s_i)).spik = spik;
        end
    end
    
    %% Merge and Save
    if ~isempty(sessions)
        paths = get_paths(sessions(1).session_path);
    else
        paths = get_paths(base_path);
    end
    save(fullfile(paths.save,'sessions.mat'), 'sessions');
    
    %tot_num_cells = length(unique([[sessions.FOV]',[sessions.cell_id]'],'rows'));
    fprintf('Processed %d Unique Cells\n',num_cells);
end

end