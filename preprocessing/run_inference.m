function run_inference(username, root_data, model, background, rerun)

% read in username and password from text file
server_ip = '10.93.5.151'; % fanlab server IP address

inference_script = "/home/" + username + "/SUPPORT-denoising/model/inference.sh";

% first ssh to check if SUPPORT-denoising repo is cloned
cmd = sprintf(['ssh -o StrictHostKeyChecking=no %s@%s ' ...
    '"if [ ! -d \\"/home/%s/SUPPORT-denoising\\" ]; then ' ...
    'git clone https://github.com/erinwong72/SUPPORT-denoising.git /home/%s/SUPPORT-denoising; fi"'], ...
    username, server_ip, username, username);
status = system(cmd);

if status ~= 0
    error("Inference failed for %, problem setting up repo on server");
end

% run inference script on server
cmd = sprintf([ ...
    'ssh -o StrictHostKeyChecking=no %s@%s ' ...
    '"bash -lc ''%s %s %s %s %d %d''"' ], ...
    username, server_ip, ...
    inference_script, username, root_data, model, background, rerun);

system(cmd, '-echo');
end