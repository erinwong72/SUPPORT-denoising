clear all; close all;
set(0, 'DefaultFigurePosition', 'remove');
for k = [1:9 ] % 1 2 3 10 11
    
    path = ['Z:\Labmembers\Kailong\in vivo imaging_IPSP\ipsp-btsp-ctrl\ipsp-btsp-ctrl-w07\2025-11-26 ipsp test\slice1','\FOV', num2str(k)];
    target = 'movReg.bin'; % 'Sq_camera.bin';
    dt = 1;
    dirs = dir(path);
    for i = 1:length(dirs)
        cd(path);
        if isdir(dirs(i).name) && ~strcmp(dirs(i).name, '.') && ~strcmp(dirs(i).name, '..')
            files = dir(fullfile(path, dirs(i).name));
            
            cd(fullfile(path,dirs(i).name));
            fov = i;
            for j = 1: length(files)
                if strcmp(files(j).name, target)
                    
                    try
                        
                        cd(fullfile(path,dirs(fov).name));
                        
                        Run_xtalk_PCA_ICA_RMmov_FanLab_function_automask(dt);
                         %Run_PCA_ICA_RMmov_FanLab_function(dt); 
                        
                        disp(['success at ', fullfile(path, dirs(i).name)]);
                    catch ME
                        disp(['fail at ', fullfile(path, dirs(i).name)]);
                    end
                    close all;
                end
            end
        end
    end
end
