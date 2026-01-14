# Preprocessing Directory

This directory contains scripts for preprocessing voltage imaging data in the SUPPORT-denoising pipeline. The preprocessing pipeline performs motion correction, SUPPORT denoising preparation, ICA/PCA analysis, and spike thresholding.

## Overview

The preprocessing pipeline consists of five main steps:
1. **Motion Correction** - Corrects for motion artifacts in raw imaging data
2. **SUPPORT Data Generation** - Prepares data for SUPPORT denoising model
3. **ICA Pre** - Performs PCA/ICA decomposition on masked cell regions
4. **ICA Choose** - Interactive selection of best independent components
5. **Spike Thresholding** - Detects and characterizes action potentials

## Main Scripts

### batch_preprocess.m

**Purpose**: Main orchestration script that runs the complete preprocessing pipeline.

**Functionality**:
- Automatically detects OS and sets appropriate root paths (Windows: Z:\, macOS/Linux: /Volumes/fanlab)
- Discovers sessions from specified animal IDs and session IDs
- Executes preprocessing steps based on the prepro array configuration
- Handles both standard preprocessing and SUPPORT-integrated preprocessing workflows

**Configuration**:
- prepro array: [1 1 1 1 1] controls which steps to run:
  - prepro(1): Motion Correction
  - prepro(2): SUPPORT data generation
  - prepro(3): ICA Pre
  - prepro(4): ICA Choose
  - prepro(5): Spike Thresholding
- is_stim: Logical flag for stimulation protocol (affects blueStim parameter)
- path.anim_ids: Cell array of animal IDs to process
- path.sess_ids: Cell array of session IDs to process

**Input Files**:
- Sq_camera.bin: Raw camera data
- experimental_parameters.txt: Session metadata (nrow, ncol, offsets)

**Output Files**:
- movReg.bin: Motion-corrected movie (in session directory)
- support/raw.tiff: Raw movie in TIFF format for SUPPORT (if prepro(2) == 1)
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
