function safe_addpath(p)
    if exist(p,'dir')
        % normalize to avoid trailing slashes and ensure consistent comparison
        normP = char(java.io.File(p).getCanonicalPath);
        pathList = strsplit(path, pathsep);
        already = any(cellfun(@(x) strcmpi(normP, char(java.io.File(x).getCanonicalPath)), ...
                              pathList, 'UniformOutput', true));
        if ~already
            addpath(genpath(p));
        end
    else
        warning('Path not found (skipped addpath): %s', p);
    end
end