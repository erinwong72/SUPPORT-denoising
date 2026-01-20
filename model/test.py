import os, sys, glob, argparse, skimage.io as skio, tifffile, torch
from typing import List
from pathlib import Path
from support_model import *
# # get working directory
# pwd = os.path.dirname(os.path.abspath(__name__))
# sys.argv.insert(0, '/home/knswift/SUPPORT/')

# def get_dims(tif_file):
#     with tifffile.TiffFile(tif_file) as tif:
#         num_frames = len(tif.pages)
#         height, width = tif.pages[0].shape
#     return num_frames, height, width

def batch_inference(raw_data_path, model):
    # raw_data_path is a directory containing .tiff files to process
    paths_to_process = list(Path(raw_data_path).glob('*.tif'))
    print(f"Found {len(paths_to_process)} files to process.")

    for i, tif_path in enumerate(paths_to_process):
        tif_path = str(tif_path)
        output_filename = tif_path.replace('.tif', '_denoised.tif')
        if os.path.exists(output_filename):
            print(f"File already processed, skipping: {tif_path}")
            paths_to_process.pop(i)
            continue
        try:
            print(f"Processing file: {tif_path}")
            movie = torch.from_numpy(skio.imread(tif_path).astype(np.float32)).type(torch.FloatTensor)
            # get dims of movie
            patch_size = [61, movie.shape[-2], movie.shape[-1]]  # [time, height, width]
            patch_interval = [1, movie.shape[-2]//2, movie.shape[-1]//2]
            testset = DatasetSUPPORT_test_stitch(movie, patch_size=patch_size, \
                                        patch_interval=patch_interval)
            testloader = torch.utils.data.DataLoader(testset, batch_size=128, num_workers=4
                                                    , pin_memory=True)
            denoised_stack = validate(testloader, model)
            skio.imsave(output_filename, denoised_stack.astype(np.float32))
            print(f"Saved {output_filename}")
            del movie, testset, testloader, denoised_stack
            torch.cuda.empty_cache()
        except Exception as e:
            print(f"Error processing file {tif_path}: {e}")
    

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Denoise movies using SUPPORT')
    parser.add_argument('--raw_path', type=str, help='Path to the raw data directory')
    parser.add_argument('--model_path', type=str, help='Path to the model file')
    parser.add_argument('--gpu', type=int, default=0, help='GPU id to use (default: 0)')
    args = parser.parse_args()

    raw_path = args.raw_path
    model_path = args.model_path

    # load list of paths to process from text file
    # must use GPU
    device = torch.device(f"cuda:{args.gpu}" if torch.cuda.is_available() else "cpu")

    # load models
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

    # create output directory if it doesn't exist

    # run inference
    batch_inference(raw_data_path=raw_path, model=model)
