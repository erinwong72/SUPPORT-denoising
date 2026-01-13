#!/bin/bash

nohup python -m src.train --exp_name cck-gevi_post --noisy_data "/mnt/fanlab/Labmembers/Kohl/Support/cck-gevi/dataset/train/post-motion" --n_epochs 50 --auto_patch_size --is_folder > /dev/null 2>&1 &
