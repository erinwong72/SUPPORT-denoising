#!/bin/bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate SUPPORT

## YOU ONLY NEED TO CHANGE THESE VARIABLES
USER=knswift
export MODEL_NAME="PC" # change the name to what you want your model to be called (e.g. basket cell)
export TRAINING_DATA="/mnt/fanlab/Computer Code/SUPPORT-denoising/datasets/PC/train_higherSNR" # make sure to add /mnt/fanlab in front of labmembers
# make sure this is the directory where the source code for SUPPORT is (copied from Roshni's setup) 
export src_dir="/home/$USER/SUPPORT/"

## NO NEED TO CHANGE BELOW THIS LINE
cd "$src_dir"

nohup bash -c '
  set -ex
  which python
  python --version
  pwd
  python -m src.train \
    --exp_name "$1" \
    --noisy_data "$2" \
    --n_epochs 50 \
    --auto_patch_size \
    --is_folder
' bash "$MODEL_NAME" "$TRAINING_DATA" \
> /home/knswift/SUPPORT/results/logs/train/PC.log 2>&1 &
echo "Training started for model $MODEL_NAME. Check train.log for progress."