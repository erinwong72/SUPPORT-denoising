#!/bin/bash
## Change these parameters
#export RAW="/mnt/fanlab/Data and Analysis/DSI-BTSP/CCK-voltage_KS/"
source ~/miniconda3/etc/profile.d/conda.sh

# set values here
DATA_DIR= #change
MODEL= #name of model

# get paths and everything passed in from matlab script
ROOT= #/home/your_username/ #change

MODEL_PATH="/mnt/fanlab/Computer Code/SUPPORT-denoising/trained_models/$MODEL.pth"
conda activate SUPPORT

cd $ROOT/SUPPORT-denoising/model/

export DATA_DIR
LOG_DIR="$ROOT/SUPPORT-denoising/results/logs/inference/"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

LOG="$LOG_DIR/inference_$(date +%Y%m%d_%H%M%S).log"
export LOG
export MODEL_PATH
export GPU_ID=0

nohup bash -c 'set -e; python -m test --raw_path "$DATA_DIR" --model_path "$MODEL_PATH" --gpu "$GPU_ID"' \
2>&1 | tee "$LOG" &
echo "Inference started in background. Check $LOG for progress."