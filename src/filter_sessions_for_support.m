function support_sessions = filter_sessions_for_support(sessions, motion_corr, target_file)
    % Filter sessions to only include those with support directory containing target file
    % sessions: struct array of sessions from discover_sessions
    % target_file: name of target file (e.g., f'denoised.tiff')
    % motion_corr: 'pre-motion' or 'post-motion'
    % support_sessions: filtered struct array containing only sessions with support data

    % set default values
    if nargin < 3
        target_file = 'denoised.tiff';
    end

    support_sessions = struct([]);
    
    for s = 1:numel(sessions)
        session_path = sessions(s).session_path;
        support_dir = fullfile(session_path, 'support');
        
        if isfolder(support_dir)
            % Check for target file in motion_corr subdirectory (post-motion case)
            target_path = fullfile(support_dir, motion_corr, target_file);
            if ~isfile(target_path)
                % Also check in support_dir directly (pre-motion case)
                target_path = fullfile(support_dir, target_file);
            end
            
            if isfile(target_path)
                support_sessions = [support_sessions, sessions(s)];
            end
        end
    end
end