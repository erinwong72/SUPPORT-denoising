function run_inference(session, opts)
arguments
    session struct
    opts.config string = "/shared/ml_inference/configs/default.yaml"
end

script = "/shared/ml_inference/scripts/run_inference.sh";
session_dir = session.session_path;

cmd = sprintf('bash %s %s %s', script, session_dir, opts.config);
status = system(cmd);

if status ~= 0
    error("Inference failed for %s", session_dir);
end
end
