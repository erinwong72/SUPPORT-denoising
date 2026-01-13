function struct_out = convert_struct_paths(struct_in, target_root)
    % Convert paths in struct fields from one OS format to another
    % struct_in: input struct (can be struct array)
    % target_root: target root path (e.g., '/Volumes/fanlab' or 'Z:')
    % struct_out: struct with converted paths (not saved to disk)
    
    struct_out = struct_in;
    
    if isempty(struct_out)
        return;
    end
    
    % Determine source root paths to look for
    if ismac || isunix
        source_roots = {'Z:', 'Z:\'};
    else
        source_roots = {'/Volumes/fanlab'};
    end
    
    % Process each struct in the array
    for i = 1:numel(struct_out)
        fields = fieldnames(struct_out(i));
        for j = 1:numel(fields)
            field_val = struct_out(i).(fields{j});
            
            % If it's a string/char that looks like a path, convert it
            if ischar(field_val) || isstring(field_val)
                path_str = char(field_val);
                % Check if it contains any of the source roots
                for k = 1:numel(source_roots)
                    if contains(path_str, source_roots{k})
                        % Replace the source root with target root
                        path_str = strrep(path_str, source_roots{k}, target_root);
                        % Also handle path separators if needed
                        if ispc && contains(path_str, '/')
                            path_str = strrep(path_str, '/', filesep);
                        elseif (ismac || isunix) && contains(path_str, '\')
                            path_str = strrep(path_str, '\', filesep);
                        end
                        struct_out(i).(fields{j}) = path_str;
                        break;
                    end
                end
            % If it's a struct, recurse
            elseif isstruct(field_val)
                struct_out(i).(fields{j}) = convert_struct_paths(field_val, target_root);
            % If it's a cell array, check each element
            elseif iscell(field_val)
                for c = 1:numel(field_val)
                    if ischar(field_val{c}) || isstring(field_val{c})
                        path_str = char(field_val{c});
                        for k = 1:numel(source_roots)
                            if contains(path_str, source_roots{k})
                                path_str = strrep(path_str, source_roots{k}, target_root);
                                if ispc && contains(path_str, '/')
                                    path_str = strrep(path_str, '/', filesep);
                                elseif (ismac || isunix) && contains(path_str, '\')
                                    path_str = strrep(path_str, '\', filesep);
                                end
                                field_val{c} = path_str;
                                break;
                            end
                        end
                    elseif isstruct(field_val{c})
                        field_val{c} = convert_struct_paths(field_val{c}, target_root);
                    end
                end
                struct_out(i).(fields{j}) = field_val;
            end
        end
    end
end