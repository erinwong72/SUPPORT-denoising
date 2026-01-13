function [path] = get_paths_erin(ref_path, os)
% Function to parse input paths based on which operating system is used

path = struct();

path.mov = ref_path;
path.parts= strsplit(path.mov, filesep);

path.spik = fullfile(path.mov, 'inter_spikeT_spikeW.mat');
path.beh  = fullfile(path.mov, 'AI Data');
path.trace = fullfile(path.mov, 'Masks_BestIcaTrace.mat');

path.anim = path.parts{end-4};
path.sess = path.parts{end-3};
path.sess_date = split(path.sess, ' ');path.sess_date = path.sess_date{1};  % Just Date '2025-05-07'
path.slic = path.parts{end-2};
path.fov  = path.parts{end-1};
path.rec   = path.parts{end};

%path.cellLabel = sprintf('%s %s %s %s %s Cell#%d', path.anim, path.sess_date, path.slic, path.fov, path.rec, cellID);
if os == 0; path.save = fullfile(fullfile(path.parts{1:end-2}),'Figures');
else; path.save = fullfile(fullfile('/', path.parts{1:end-2}),'Figures');
end
[~,~] = mkdir(path.save);

end