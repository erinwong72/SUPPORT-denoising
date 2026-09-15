#!/bin/bash
## Change these parameters
#export RAW="/mnt/fanlab/Data and Analysis/DSI-BTSP/CCK-voltage_KS/"
set -euo pipefail
source ~/miniconda3/etc/profile.d/conda.sh

USER=$1
DATA_DIR=$2
MODEL=$3
SUPPORT_DIRNAME=$4
BACKGROUND=$5 # run in the background if 1, else run in foreground
RERUN=$6

# get paths and everything passed in from matlab script
ROOT=/home/$USER/

MODEL_PATH="/home/knswift/SUPPORT/results/saved_models/PC/model_49.pth" #"/mnt/fanlab/Labmembers/Erin/models/$MODEL.pth"
# TEMPORARILY overriding to test roshni's model
#MODEL_PATH="/home/knswift/SUPPORT/src/GUI/trained_models/purple_model_50.pth"
# testing another model
#MODEL_PATH="/home/knswift/SUPPORT/results/saved_models/PC_minSNR_5/model_49.pth"
if conda env list | awk '{print $1}' | grep -Fxq "SUPPORT"; then
    conda activate SUPPORT
    echo "Activated SUPPORT environment"
else
    # check if support denoising repository is cloned
    # if [ ! -d "$ROOT/SUPPORT-denoising"]; then
    #     # then create conda directory using .yml file
    #     git clone https://github.com/erinwong72/SUPPORT-denoising.git $ROOT
    # fi
    # download conda if not already installed
    if ! command -v conda &> /dev/null
    then
        echo "Conda could not be found, installing Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $ROOT/miniconda.sh
        bash $ROOT/miniconda.sh -b -p $ROOT/miniconda3
        rm $ROOT/miniconda.sh
        source $ROOT/miniconda3/etc/profile.d/conda.sh
        echo "Miniconda installed successfully."
    fi
    conda env create -f $ROOT/SUPPORT-denoising/model/env.yml -n SUPPORT
    conda activate SUPPORT
    echo "Created and activated SUPPORT environment"
fi

cd $ROOT/SUPPORT-denoising/model/
# if fanlab-1 is in DATA_DIR, replace with fanlab
if [[ "$DATA_DIR" == *"fanlab-1"* ]]; then
    DATA_DIR="${DATA_DIR/fanlab-1/fanlab}"
    echo "Replaced fanlab-1 with fanlab in DATA_DIR"
fi
export DATA_DIR #="/mnt/fanlab/Labmembers/Kohl/CCK/cck-inhDSI-w08/2026-01-13-VR-V_blue/" # where output from support is saved
LOG_DIR="$ROOT/SUPPORT-denoising/results/logs/inference/"
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

LOG="$LOG_DIR/inference_$(date +%Y%m%d_%H%M%S).log"
export LOG
export MODEL_PATH
export GPU_ID=1
export SUPPORT_DIRNAME
export RERUN

echo SUPPORT_DIRNAME: $SUPPORT_DIRNAME
if [ "$BACKGROUND" -eq 0 ]; then
    echo "Running inference in foreground..."
    python -u -m inference --raw_path "$DATA_DIR" --model_path "$MODEL_PATH" --gpu "$GPU_ID" --support_dirname "$SUPPORT_DIRNAME" --rerun "$RERUN"  2>&1 | tee "$LOG"
else
    echo "Running inference in background..."
    nohup bash -c 'set -e; python -m inference --raw_path "$DATA_DIR" --model_path "$MODEL_PATH" --gpu "$GPU_ID" --rerun "$RERUN" --support_dirname "$SUPPORT_DIRNAME"' \
    2>&1 | tee "$LOG" &
    echo "Inference started in background. Check $LOG for progress."
fi