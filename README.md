# guide to SUPPORT denoising project

organization:
- **analysis**: analysis code for deciding model implementations (e.g. where SUPPORT fits in the workflow), quantifying signal improvement (PSNR, waveform correlation, etc.)
- **model**: code for training SUPPORT, generating datasets for SUPPORT, and inferencing
- **preprocessing**: code integrating SUPPORT into standard lab pipeline
- **utils**: helper functions (for analysis and preprocessing)

general use-cases:
1. Training a denoising model for a new cell type
    a. copy SUPPORT folder from Roshni's labmembers folder and place it in the same *parent* directory on the compute server as this repository
    b. Analyzing the newly trained model - refer to code in **analysis**
2. Applying a pre-trained model on new imaging data - refer to the [preprocessing guide](/preprocessing#readme) for more instructions
