#!/usr/bin/env bash
set -euo pipefail
source ~/miniconda3/etc/profile.d/conda.sh

USER=$1
CONFIG=$2

ROOT=/home/$USER/

# activate conda environment
if conda env list | awk '{print $1}' | grep -Fxq "SUPPORT"; then
    conda activate SUPPORT
    echo "Activated SUPPORT environment"
else
    # check if support denoising repository is cloned
    if [ ! -d "$ROOT/SUPPORT-denoising"]; then
        # then create conda directory using .yml file
        git clone https://github.com/erinwong72/SUPPORT-denoising.git $ROOT
    fi
    conda env create -f $ROOT/SUPPORT-denoising/model/support_model.yml -n SUPPORT
    conda activate SUPPORT
    echo "Created and activated SUPPORT environment"


LOGDIR="$SESSION_DIR/logs"
mkdir -p "$LOGDIR"

echo "Starting inference at $(date)" > "$LOGDIR/inference.log"

python "$ROOT/scripts/infer.py" \
    --session "$SESSION_DIR" \
    --config "$CONFIG" \
    >> "$LOGDIR/inference.log" 2>&1

touch "$SESSION_DIR/inference_done"
