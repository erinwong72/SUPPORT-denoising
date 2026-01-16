# Preprocessing Directory

This directory contains scripts for preprocessing voltage imaging data in the SUPPORT-denoising pipeline. The preprocessing pipeline performs motion correction, SUPPORT denoising preparation, ICA/PCA analysis, and spike thresholding.

## Overview

The preprocessing pipeline consists of five main steps:
1. **Motion Correction** - Corrects for motion artifacts in raw imaging data
2. **SUPPORT Data Generation** - Prepares data for SUPPORT denoising model
3. **SUPPORT inference** - applies trained SUPPORT model on the noisy data, producing denoised data
3. **ICA Pre** - Performs PCA/ICA decomposition on masked cell regions
4. **ICA Choose** - Interactive selection of best independent components
5. **Spike Thresholding** - Detects and characterizes action potentials

### generating SSH key
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

## Main Scripts

### batch_preprocess.m

**Purpose**: Main script that runs the complete preprocessing pipeline.

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

**Input Files**:
- Sq_camera.bin: Raw camera data
- experimental_parameters.txt: Session metadata (nrow, ncol, offsets)

**Output Files**:
- movReg.bin: Motion-corrected movie (in session directory)
- support/raw.tiff: Raw movie in TIFF format for SUPPORT (if use_support == 1)
- support/denoised.tiff: Denoised movie from SUPPORT (must be generated externally)
- sessions_for_support.txt: List of session paths for Python inference script

**Usage Notes**:
- The script checks for existing output files and skips steps if outputs already exist
- For SUPPORT workflow, the script generates raw.tiff files and waits for external SUPPORT inference to create denoised.tiff before proceeding to ICA steps
- Session paths are automatically converted to match the current OS

---
### support_dataset_generation.m

**Purpose**: Generates training or test datasets for SUPPORT model from multiple sessions.

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

---

## Workflow

### Standard Preprocessing (without SUPPORT)

1. Run batch_preprocess.m with prepro(2) = 0
2. Motion correction creates movReg.bin
3. ICA Pre processes movReg.bin directly
4. ICA Choose for manual IC selection
5. Spike thresholding on selected ICs

### SUPPORT-Integrated Preprocessing

1. Run batch_preprocess.m with prepro(2) = 1
2. Motion correction creates movReg.bin
3. SUPPORT data generation creates support/raw.tiff
4. **External step**: Run SUPPORT inference to generate support/denoised.tiff
5. ICA Pre processes support/denoised.tiff (if available)
6. ICA Choose for manual IC selection
7. Spike thresholding on selected ICs

### Batch Processing Multiple Sessions

1. Configure path.anim_ids and path.sess_ids in batch_preprocess.m
2. Set prepro array to desired steps
3. Script automatically discovers and processes all matching sessions
4. Each step checks for existing outputs and skips if found

---

## File Dependencies

### Required Input Files (per session):
- Sq_camera.bin: Raw camera data
- experimental_parameters.txt: Session parameters (nrow, ncol, xoffset, yoffset)
- Masks.mat: ROI masks (in parent directory)
- AI Data: Behavior data (for spike thresholding with stimulation)

### Generated Intermediate Files:
- movReg.bin: Motion-corrected movie
- support/raw.tiff: Raw movie for SUPPORT
- support/denoised.tiff: SUPPORT denoised movie (external)
- ICA_PreResults.mat: ICA decomposition results
- Masks_BestIcaTrace.mat: Selected IC traces
- Masks_BestIcaImgs.mat: Selected IC images
- inter_spikeT_spikeW.mat: Spike thresholding results

---

## Notes

- All scripts support cross-platform paths (Windows Z:\ and macOS/Linux /Volumes/fanlab)
- Scripts check for existing output files to allow resuming interrupted processing
- The SUPPORT workflow requires external inference step between data generation and ICA processing

---
