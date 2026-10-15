function mov = load_roi_movie(session_path, model, skip_frames)
%LOAD_ROI_MOVIE  The movie one trace set was extracted from, as ICA_Pre.m reads it.
%
%   mov = load_roi_movie(session_path, model, skip_frames)
%
%   model        'raw' reads movReg.bin at the session root (registered, not denoised);
%                anything else reads <session_path>/<model>/denoised.tiff
%   skip_frames  leading frames dropped to line up with IntensOrig (ICA_Pre.m: nremove)
%   mov          double [dim1 x dim2 x nFrames]
if strcmp(model, 'raw')
    fid = fopen(fullfile(session_path, 'experimental_parameters.txt'));
    info = textscan(fid, '%s');
    fclose(fid);
    nrow = str2double(info{1}{6});   % same token positions and argument order as ICA_Pre.m
    ncol = str2double(info{1}{3});
    mov = readBinMov(fullfile(session_path, 'movReg.bin'), ncol, nrow);
else
    tiffFile = fullfile(session_path, model, 'denoised.tiff');
    assert(isfile(tiffFile), 'denoised movie not found: %s', tiffFile);
    mov = loadtiff(tiffFile);
end
mov = double(mov(:, :, skip_frames + 1:end));
end
