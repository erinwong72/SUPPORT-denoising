function safe_addpath(p,rerun)
if nargin <2
    rerun = 0;
end

    if exist(p,'dir')
        % normalize to avoid trailing slashes and ensure consistent comparison
        normP = char(java.io.File(p).getCanonicalPath);
        pathList = strsplit(path, pathsep);
        already = any(cellfun(@(x) strcmpi(normP, char(java.io.File(x).getCanonicalPath)), ...
                              pathList, 'UniformOutput', true));
        if ~already || rerun
            addpath(genpath(p));
        end
    else
        warning('Path not found (skipped addpath): %s', p);
    end
end