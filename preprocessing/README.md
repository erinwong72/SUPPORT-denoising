# Preprocessing Guide

This directory contains scripts for preprocessing voltage imaging data in the SUPPORT-denoising pipeline. The preprocessing pipeline performs motion correction, SUPPORT denoising preparation, ICA/PCA analysis, and spike thresholding.

**jump to [[preprocessing/README#Workflow|workflow]] for instructions on how to set up for different use-cases (with and without SUPPORT).**
## Overview

The preprocessing pipeline consists of five main steps:
1. **Motion Correction** - Corrects for motion artifacts in raw imaging data
2. **SUPPORT Data Generation** - Prepares data for SUPPORT denoising model
3. **SUPPORT inference** - applies trained SUPPORT model on the noisy data, producing denoised data
3. **ICA Pre** - Performs PCA/ICA decomposition on masked cell regions
4. **ICA Choose** - Interactive selection of best independent components
5. **Spike Thresholding** - Detects and characterizes action potentials
### Generating SSH key
This is necessary if you want to enable end to end preprocessing (without leaving matlab), specifically for step 3 (running a trained model on the noisy data), which has to ssh to the compute server and run a bash script.

Do this on your local computer (wherever you are running matlab):
1. Find or generate an SSH key:
```bash
# run this to find existing keys
ls -al ~/.ssh
```
If you see a file like `id_rsa`, `id_ed25519`, or `id_ecdsa`, you already have SSH key(s).

If not, create one, replacing it with an appropriate name:
```bash
ssh-keygen -t ed25519 -C "name_of_key"
```
2. Copy key to remote host, replacing `username` with your username and `ip_address` with our server's ip address. This will prompt you for your password.
```bash
ssh-copy-id username@ip_address
```
3. Test that this is properly set up by running the following in matlab, replacing `username` and `ip_address` again:
```matlab
cmd = sprintf('ssh -o StrictHostKeyChecking=no %s@%s "echo SSH works"', username, ip_address);
status = system(cmd, '-echo');
```
If the ssh key is set up properly, matlab will print "SSH works".

## Workflow

### Preprocessing without SUPPORT

1. Run batch_preprocess.m with `use_support = 0`, `prepro = [1 0 0 1 1 1]`
2. Motion correction creates movReg.bin
3. ICA Pre processes movReg.bin directly
4. ICA Choose for manual IC selection
5. Spike thresholding on selected ICs

### SUPPORT-Integrated Preprocessing

1. Run batch_preprocess.m with `use_support = 0`, `prepro = [1 1 1 1 1 1]`
2. Motion correction creates movReg.bin
3. SUPPORT data generation creates support/raw.tiff
4. Run SUPPORT inference to generate support/denoised.tiff (make sure to [[preprocessing/README#generating SSH key|generate an SSH key]] first)
5. ICA Pre processes support/denoised.tiff
6. ICA Choose for manual IC selection
7. Spike thresholding on selected ICs

## Main Scripts

### batch_preprocess.m

Main script that runs the complete preprocessing pipeline.

**Functionality**:
- Automatically detects OS and sets appropriate root paths (Windows: Z:\, macOS/Linux: /Volumes/fanlab)
- Discovers sessions from specified animal IDs and session IDs
- Executes preprocessing steps based on the prepro array configuration, including applying the trained model to imaging data, denoising it without you having to leave matlab. Before this step, make sure that you have generated an ssh key for the server so matlab can log in without needing a password.
- Handles both standard preprocessing and SUPPORT-integrated preprocessing workflows

**Configuration**:
- prepro array: [1 1 1 1 1 1] controls which steps to run:
  - prepro(1): Motion Correction
  - prepro(2): SUPPORT data generation
  - prepro(3): SUPPORT inference on noisy data
  - prepro(3): ICA Pre
  - prepro(4): ICA Choose
  - prepro(5): Spike Thresholding
- is_stim: Logical flag for stimulation protocol (affects blueStim parameter)
- use_support: Logical flag for if you want to denoise and process the files
- path.anim_ids: Cell array of animal IDs to process
- path.sess_ids: Cell array of session IDs to process

---
### support_dataset_generation.m (WIP)

Generates training or test datasets for SUPPORT model from multiple sessions.

**Functionality**:
- Discovers sessions from specified animal IDs
- Generates raw.tiff files for SUPPORT inference
- For training datasets: extracts masked cell regions from random 2000-frame samples
- Creates sessions_for_support.txt file listing all session paths

**Configuration**:
- dataset_type: 'test' or 'train'
- sel_nframes: 2000 (number of frames to sample for training)
- target_file: 'movReg.bin' (motion-corrected movie)

**Input Files**:
- movReg.bin: Motion-corrected movie
- experimental_parameters.txt: Session metadata
- Masks.mat: ROI masks

**Output Files**:
- Test mode: support/raw.tiff in each session directory
- Train mode: [hash_id]_[sess_name].tiff in specified save directory (masked cell regions)
- sessions_for_support.txt: List of session paths

**Usage Notes**:
- Training mode extracts individual cell regions from random frame windows
- Test mode saves full FOV movies
- Automatically skips sessions where output files already exist
