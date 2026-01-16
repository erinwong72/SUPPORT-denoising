#!/bin/bash
## Change these parameters
#export RAW="/mnt/fanlab/Data and Analysis/DSI-BTSP/CCK-voltage_KS/"
set -euo pipefail
source ~/miniconda3/etc/profile.d/conda.sh

USER=$1
DATA_DIR=$2
MODEL=$3
BACKGROUND=$4 # run in the background if 1, else run in foreground

# get paths and everything passed in from matlab script
ROOT=/home/$USER/

MODEL_PATH="/mnt/Labmembers/Erin/models/$MODEL.pth"
if conda env list | awk '{print $1}' | grep -Fxq "SUPPORT"; then
    conda activate SUPPORT
    echo "Activated SUPPORT environment"
else
    # check if support denoising repository is cloned
    # if [ ! -d "$ROOT/SUPPORT-denoising"]; then
    #     # then create conda directory using .yml file
    #     git clone https://github.com/erinwong72/SUPPORT-denoising.git $ROOT
    # fi
    conda env create -f $ROOT/SUPPORT-denoising/model/support_model.yml -n SUPPORT
    conda activate SUPPORT
    echo "Created and activated SUPPORT environment"
fi

cd $ROOT/SUPPORT-denoising/model/

export DATA_DIR #="/mnt/fanlab/Labmembers/Kohl/CCK/cck-inhDSI-w08/2026-01-13-VR-V_blue/" # where output from support is saved

LOG_DIR="$ROOT/SUPPORT-denoising/results/logs/inference/"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

LOG="$LOG_DIR/inference_$MODEL_$(date +%Y%m%d_%H%M%S).log"
export LOG
export MODEL_PATH
export GPU_ID=0

if [ "$BACKGROUND" -eq 0 ]; then
    echo "Running inference in foreground..."
    python -u -m inference --raw_path "$DATA_DIR" --model_path "$MODEL_PATH" --gpu "$GPU_ID" 2>&1 | tee "$LOG"
else
    echo "Running inference in background..."
    nohup bash -c 'set -e; python -m inference --raw_path "$DATA_DIR" --model_path "$MODEL_PATH" --gpu "$GPU_ID"' \
    2>&1 | tee "$LOG" &
    echo "Inference started in background. Check $LOG for progress."
fi