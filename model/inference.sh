#!/bin/bash
## Change these parameters
#export RAW="/mnt/fanlab/Data and Analysis/DSI-BTSP/CCK-voltage_KS/"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate SUPPORT
cd /home/knswift/SUPPORT/SUPPORT-denoising/model/

export RAW="/mnt/fanlab/Labmembers/Kohl/CCK/cck-inhDSI-w08/2026-01-13-VR-V_blue/" # where output from support is saved
export LOG_DIR="/home/knswift/SUPPORT/results/logs/inference/"
export MODEL="/home/knswift/SUPPORT/results/saved_models/cck-gevi_post/model_49.pth"
export GPU_ID=0

START_TIME=$(date +%s)
nohup bash -c 'set -e; python -m inference --raw_path "$RAW" --model_path "$MODEL" --gpu "$GPU_ID"' \
> $LOG_DIR/inference_"$START_TIME".log 2>&1 &
echo "Inference started. Check inference_${START_TIME}.log for progress."