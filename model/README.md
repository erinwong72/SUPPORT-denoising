## Training
To train a model on data you have already generated using `support_dataset_generation.m` in the preprocessing folder, run `train.sh`.

## Inference
There are two occasions where you may want to run inference:
1. As part of the **preprocessing** pipeline (most use cases): inference on a smaller number of tifs, each located within its own directory structure corresponding to the animal, preparation, imaging session, etc.
2. **Analysis** (of SUPPORT's performance) to improve something about SUPPORT's implementation: entails inferencing on a large dataset of tifs, expected to all be in the same folder

For **preprocessing**, the matlab script `batchPreprocess_EW.m` will automatically connect to the server and start inference on the images in the processing queue if the step "SUPPORT inference" is set to true. It does so by first ssh-ing onto the server and then executing `inference.sh` which will, in turn, call `inference.py` with the correct parameters. `inference.py` is the script that actually loads the trained model parameters and denoises the input images.

To run **analysis**, use the `run_test.sh` script, which has env variables you should set to point it to the directory containing your data and the name of the trained model you intend on using. It will run `test.py`.