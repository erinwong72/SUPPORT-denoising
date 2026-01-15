#!/usr/bin/env bash
set -euo pipefail
source ~/miniconda3/etc/profile.d/conda.sh

USER=$1
CONFIG=$2

ROOT=/shared/ml_inference

if conda env list | awk '{print $1}' | grep -Fxq "SUPPORT"; then
    conda activate SUPPORT
    echo "Activated SUPPORT environment"
else
    # check if support denoising repository is cloned
    if [ ! -d "/home/$USER/SUPPORT-denoising"]; then
        # then create conda directory using .yml file
        git clone https://github.com/erinwong72/SUPPORT-denoising.git /home/$USER/
    fi
    conda env create -f /home/$USER/SUPPORT-denoising/model/support_model.yml


LOGDIR="$SESSION_DIR/logs"
mkdir -p "$LOGDIR"

echo "Starting inference at $(date)" > "$LOGDIR/inference.log"

python "$ROOT/scripts/infer.py" \
    --session "$SESSION_DIR" \
    --config "$CONFIG" \
    >> "$LOGDIR/inference.log" 2>&1

touch "$SESSION_DIR/inference_done"
