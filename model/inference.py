import os, argparse, numpy as np, skimage.io as skio, torch
from support_model import *


def parse_frame_size(session_path):
    """Read width/height tokens from experimental_parameters.txt.

    Matches the Fan Lab MATLAB convention used by ICA_Pre / TIFF generation:
      dim1 = Info{3}, dim2 = Info{6}
    which are passed to readBinMov(file, dim1, dim2).
    """
    param_file = os.path.join(session_path, 'experimental_parameters.txt')
    with open(param_file, 'r') as f:
        tokens = f.read().split()
    if len(tokens) < 6:
        raise ValueError(f'experimental_parameters.txt has too few tokens: {param_file}')
    dim1 = int(float(tokens[2]))  # Info{3}
    dim2 = int(float(tokens[5]))  # Info{6}
    return dim1, dim2


def read_bin_mov(bin_path, dim1, dim2):
    """Python port of Image Processing/readBinMov.m → float32 [T, H, W].

    MATLAB:
      tmp = fread(fid, '*uint16', 'l');
      mov = reshape(tmp, [ncol nrow L]);   % ncol=dim2, nrow=dim1
      mov = permute(mov, [2 1 3]);         % → [dim1, dim2, L]
    """
    file_bytes = os.path.getsize(bin_path)
    frame_pix = dim1 * dim2
    if file_bytes % (frame_pix * 2) == 0:
        tmp = np.fromfile(bin_path, dtype='<u2')
    elif file_bytes % (frame_pix * 4) == 0:
        tmp = np.fromfile(bin_path, dtype='<f4')
        nframe = tmp.size // frame_pix
        mov = tmp.reshape((dim1, dim2, nframe), order='F')
        return np.transpose(mov, (2, 0, 1)).astype(np.float32)
    else:
        raise ValueError(
            f'{bin_path} size {file_bytes} is not divisible by '
            f'{dim1}*{dim2}*{{2|4}}'
        )

    nframe = tmp.size // frame_pix
    # reshape([ncol, nrow, L]) with ncol=dim2, nrow=dim1  (MATLAB column-major)
    mov = tmp.reshape((dim2, dim1, nframe), order='F')
    mov = np.transpose(mov, (1, 0, 2))       # [dim1, dim2, T]
    return np.transpose(mov, (2, 0, 1)).astype(np.float32)  # [T, H, W]


def load_movie(session_path, support_dirname):
    """Load movie for SUPPORT: prefer movReg.bin, fall back to raw.tiff."""
    bin_path = os.path.join(session_path, 'movReg.bin')
    tiff_candidates = [
        os.path.join(session_path, 'raw.tiff'),
        os.path.join(session_path, support_dirname, 'raw.tiff'),
    ]

    if os.path.isfile(bin_path):
        dim1, dim2 = parse_frame_size(session_path)
        print(f'Loading movReg.bin ({dim1} x {dim2})')
        return read_bin_mov(bin_path, dim1, dim2)

    for tiff_path in tiff_candidates:
        if os.path.isfile(tiff_path):
            print(f'Loading legacy raw.tiff: {tiff_path}')
            return skio.imread(tiff_path).astype(np.float32)

    raise FileNotFoundError(
        f'Neither movReg.bin nor raw.tiff found under {session_path}'
    )


def batch_inference(paths_to_process, model, device, rerun=False, support_dirname="support"):
    for i, session_path in enumerate(paths_to_process):
        print(f"Processing file {i+1} of {len(paths_to_process)}")
        # if path is in the wrong format (aka for PC use), fix it
        if session_path.startswith("Z:"):
            session_path = session_path.replace("Z:", "/mnt/fanlab")
            session_path = session_path.replace("\\", "/")
        elif session_path.startswith("/Volumes"):
            session_path = session_path.replace('/Volumes', '/mnt')
        try:
            out_dir = os.path.join(session_path, support_dirname)
            output_filename = os.path.join(out_dir, "denoised.tiff")
            if os.path.exists(output_filename) and not rerun:
                print(f"File already processed, skipping: {session_path}")
                continue
            # creating and saving denoised files
            print(f"Processing file: {session_path}")
            movie = torch.from_numpy(load_movie(session_path, support_dirname)).type(torch.FloatTensor).to(device)
            # get dims of movie
            patch_size = [61, movie.shape[-2], movie.shape[-1]]  # [time, height, width]
            patch_interval = [1, movie.shape[-2]//2, movie.shape[-1]//2]
            testset = DatasetSUPPORT_test_stitch(movie, patch_size=patch_size,
                                        patch_interval=patch_interval)
            testloader = torch.utils.data.DataLoader(testset, batch_size=128, num_workers=4,
                                                    pin_memory=True)
            denoised_stack = validate(testloader, model)
            os.makedirs(out_dir, exist_ok=True)
            skio.imsave(output_filename, denoised_stack.astype(np.float32))
            print(f"Saved {output_filename}")
            del movie, testset, testloader, denoised_stack
            torch.cuda.empty_cache()
        except Exception as e:
            print(f"Error processing file {session_path}: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Denoise movies using SUPPORT')
    parser.add_argument('--raw_path', type=str, help='Path to the raw data directory')
    parser.add_argument('--model_path', type=str, help='Path to the model file')
    parser.add_argument('--gpu', type=int, default=0, help='GPU id to use (default: 0)')
    parser.add_argument('--rerun', type=int, default=0, help='Whether to rerun inference on already processed files (default: 0)')
    parser.add_argument('--support_dirname', type=str, help='Name of the support directory')
    args = parser.parse_args()

    raw_path = args.raw_path
    model_path = args.model_path
    rerun = bool(args.rerun)
    support_dirname = args.support_dirname

    # load list of paths to process from text file
    raw_path = raw_path.replace("/Volumes", "/mnt")
    with open(f'{raw_path}/sessions_for_support.txt', 'r') as f:
        paths_to_process = f.read().splitlines()
        # replace any instances of 'fanlab-1' with 'fanlab'
        paths_to_process = [p.replace('fanlab-1', 'fanlab') for p in paths_to_process]

    print(f"Found {len(paths_to_process)} files to process.")

    # must use GPU
    device = torch.device(f"cuda:{args.gpu}" if torch.cuda.is_available() else "cpu")

    # load models
    if ("roshni" in support_dirname) or ("pretrained" in support_dirname):
        # different support hyperparams
        model = SUPPORT(in_channels=61,
                  mid_channels=[16, 32, 64, 128, 256],
                  depth=5,
                  blind_conv_channels=64,
                  one_by_one_channels=[32, 16],
                  last_layer_channels=[64, 32, 16],
                  bs_size=1,
                  bp=False).to(device)
    else:
        model = SUPPORT(in_channels=61,
                mid_channels=[64, 128, 256, 512, 1024],
                depth=5,
                blind_conv_channels=64,
                one_by_one_channels=[32, 16],
                last_layer_channels=[64, 32, 16],
                bs_size=3,
                bp=False).to(device)
    state_dict = torch.load(model_path, map_location=device)
    model.load_state_dict(state_dict, strict=True)

    # run inference
    batch_inference(paths_to_process, model, device, rerun, support_dirname)
