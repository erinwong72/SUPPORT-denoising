function p = to_local_path(p, root_path)
%TO_LOCAL_PATH  Map a path saved by a run on a different machine/OS (Windows
% Z:\, a UNC path, or a Linux /mnt/fanlab mount) onto THIS machine's own
% fanlab root (root_path, from setup_analysis_paths.m).
%
% Thin wrapper around convert_struct_paths.m (SUPPORT-denoising/utils),
% which holds the authoritative, platform-aware list of source roots -
% keep path-mapping logic there, not duplicated here.
s = convert_struct_paths(struct('p', p), root_path);
p = s.p;
end
