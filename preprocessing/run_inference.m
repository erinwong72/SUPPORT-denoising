function run_inference(cred_file, root_data, model, background)

% read in username and password from text file
credentials = readtable(cred_file, 'Delimiter', '=', 'ReadVariableNames', false);
username = strtrim(credentials.Var2{strcmp(credentials.Var1, 'username')});
password = strtrim(credentials.Var2{strcmp(credentials.Var1, 'password')});
server_ip = '10.93.5.151'; % fanlab server IP address

inference_script = "/home/" + username + "/SUPPORT-denoising/model/inference.sh";

% first ssh to check if SUPPORT-denoising repo is cloned
cmd = sprintf(['sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s ' ...
    'if [ ! -d "/home/%s/SUPPORT-denoising" ]; then ' ...
    'git clone https://github.com/username/SUPPORT-denoising.git /home/%s/SUPPORT-denoising; fi'], ...
    password, username, server_ip, username, username);
status = system(cmd);

if status ~= 0
    error("Inference failed for %, problem setting up repo on server");
end

% run inference script on server
cmd = sprintf([ ...
    'sshpass -p "%s" ssh -o StrictHostKeyChecking=no %s@%s ' ...
    '"bash -lc ''%s %s %s %s %d''"' ], ...
    password, username, server_ip, ...
    inference_script, username, root_data, model, background);

system(cmd, '-echo');
end