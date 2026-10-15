function ensure_preprocessing_paths()
%ENSURE_PREPROCESSING_PATHS  Put the movie readers and the ICA_Pre helpers on the path.
%
% readBinMov, loadtiff and the vm class (pblc) live in <fanlab>/Computer Code/Image Processing;
% subtractRingXtalk and generateRingMaskFromROI in code/SUPPORT-denoising/preprocessing, which is
% appended (not prepended) because it also holds scripts that share names with ones in analysis/.
[root_path, code_path] = setup_analysis_paths();
if isempty(which('readBinMov')) || isempty(which('vm'))
    safe_addpath(fullfile(root_path, 'Computer Code', 'Image Processing'));
end
if isempty(which('subtractRingXtalk')) || isempty(which('generateRingMaskFromROI'))
    addpath(fullfile(code_path, 'SUPPORT-denoising', 'preprocessing'), '-end');
end
end
