#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate SUPPORT

## YOU ONLY NEED TO CHANGE THESE VARIABLES
USER=knswift
export MODEL_NAME="cck-gevi_post" # change the name to what you want your model to be called (e.g. basket cell)
export TRAINING_DATA="/mnt/fanlab/Labmembers/Kohl/Support/cck-gevi/dataset/train/post-motion" # make sure to add /mnt/fanlab in front of labmembers
# make sure this is the directory where the source code for SUPPORT is (copied from Roshni's setup) 
export src_dir="/home/$USER/SUPPORT/"

## NO NEED TO CHANGE BELOW THIS LINE
cd $src_dir
nohup bash -c 'set -e; python -m src.train --exp_name "$MODEL_NAME" --noisy_data "$TRAINING_DATA" --n_epochs 50 --auto_patch_size --is_folder' \
> /dev/null 2>&1 &