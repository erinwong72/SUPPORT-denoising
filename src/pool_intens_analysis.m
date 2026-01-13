function [sessions] = pool_intens_analysis(varargin)
%Function to process many recordings from a behavioral session
%Inputs: base_path - path to slice to be analyzed
%Outputs: sessions - struct of each session
sessions = [];
p = inputParser;
addParameter(p, 'base_path', '', @ischar);
addParameter(p, 'raw_path', '', @ischar);
addParameter(p, 'FOVs', [], @isnumeric);
addParameter(p, 'sess_ids', {});
addParameter(p, 'motion_corr', 1);

parse(p, varargin{:});
base_path = p.Results.base_path;
FOVs = p.Results.FOVs;
sess_ids = p.Results.sess_ids;
raw_path = p.Results.raw_path;
process_motion = p.Results.motion_corr;

%% Session Parameters
%base_path = sprintf('/Volumes/fanlab/Labmembers/Kohl/CCK/%s/%s/%s',anim_id,sess_id,slice_id);
parts = strsplit(base_path, filesep);
anim_id = parts{end-2}; %'cck-gevi-w05';
sess_id = parts{end-1}; %'Running9_15_2025';
slice_id = parts{end}; %'slice1';
if parts{1} == "Z:"; os = 0;
else; os = 1;
end
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

% Get all valid subdir paths
session_list = struct('anim_id',{},'FOV', {}, 'subdir_path', {}, 'raw_path', {}, 'subdir_name', {}, 'cell_id', {},'num_cells', {});
for k = FOVs
    fov_path = fullfile(base_path, sprintf('FOV%d', k));
    dirs = dir(fov_path);
    dirs = dirs([dirs.isdir] & ~ismember({dirs.name}, {'.', '..'}));
    for i = 1:numel(dirs)
        if isempty(sess_ids) || ~contains({dirs(i).name}, sess_ids)
            subdir_path = fullfile(fov_path, dirs(i).name);
            raw_subdir_path = fullfile(raw_path, sprintf('FOV%d', k), dirs(i).name);
            target_path = fullfile(subdir_path, target_file);
            if process_motion; motion_target_path = fullfile(replace(subdir_path, 'post', 'pre'), target_file); end
            if isfile(target_path) && isfile(motion_target_path)
                load(target_path, "nCells");
                for cell_id = 1:nCells
                    session_list(end+1) = struct( ...
                        'anim_id', anim_id,...
                        'FOV', k, ...
                        'subdir_path', subdir_path, ...
                        'raw_path', raw_subdir_path, ...
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
    
    for idx = 1:n_sessions
        entry = session_list(idx);
        try
            % Store locally
            sess = struct();
            sess.anim_id = entry.anim_id;
            %sess.session_path = entry.subdir_path;
            sess.session_name = entry.subdir_name;
            sess.FOV = entry.FOV;
            sess.cell_id = entry.cell_id;
            sess.fov_num_cells = entry.num_cells;
            % modified to be based on Roshni's Testing Epoch script
            if process_motion; end_idx = 3; end
            for f = 1:end_idx
                beh_spiking_sess = [];
                if f == 1; path_name = entry.raw_path; is_plot = 0;
                else 
                    if f == 2; path_name = entry.subdir_path; is_plot = 1; 
                    else; path_name = replace(entry.subdir_path, 'post', 'pre'); is_plot = 1; end
                end
                load(fullfile(path_name, 'Masks_BestIcaTrace.mat'), 'IntensOrig');
                sess.trace{f} = IntensOrig;

                [beh_spiking_sess.beh, beh_spiking_sess.spik,beh_spiking_sess.sub_t] = load_voltage_and_beh_support(path_name, 'cellID', entry.cell_id,'isPlot',is_plot, 'os', os);
                sess.beh_spiking{f} = beh_spiking_sess;

                spike_struct = dir(fullfile(path_name, '*inter_spike*T_spikeW.mat'));
                load(fullfile(path_name, spike_struct(1).name), 'C');
                spikes = C;
                for i = 1:entry.num_cells
                    sess.spikes{f}{i} = spikes(i).spikeT{1};
                end
            end
            sess.cell_hash = gen_cell_hash(entry.subdir_path,sess.cell_id);
            
            close all;
    
            %Metrics
            for f = 1:end_idx
                sess.nspikes{f} = sess.beh_spiking{f}.spik.nspike;
                %sess.snr = sess.sub_t.norm.snr;
                sess.fr{f} = sess.beh_spiking{f}.spik.fr;
                sess.mean_width{f} = sess.beh_spiking{f}.spik.meanWidth;
                sess.fwhm = sess.beh_spiking{f}.spik.fwhm;
                % sess.fwhm = sess.spik.fwhm;
            end
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
        for f = 1:end_idx
            full_fr = [];
            for s_i = 1:num_sess
                full_fr = [full_fr, sessions(coi(s_i)).beh_spiking{f}.spik.smooth];
            end
            % Z-Score Firing Rates
            mean_fr = mean(full_fr);
            std_fr = std(full_fr);
            for s_i = 1:num_sess
                spik = sessions(coi(s_i)).beh_spiking{f}.spik;
                spik.mean_fr = mean_fr;
                spik.std_fr = std_fr;
                spik.smooth_z = (spik.smooth - mean_fr) / std_fr;    
                sessions(coi(s_i)).spik{f} = spik; 
            end
        end        
    end
    
    %% Merge and Save
    if ~isempty(sessions)
        paths = get_paths_erin(entry.subdir_path, os);
    else
        paths = get_paths_erin(base_path, os);
    end
    save(fullfile(paths.save,'support_analysis_motion.mat'), 'sessions');
    
    %tot_num_cells = length(unique([[sessions.FOV]',[sessions.cell_id]'],'rows'));
    fprintf('Processed sessions');
end