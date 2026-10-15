# SUPPORT model-comparison analysis pipeline

Reminder of what each step does, what command runs it, and what it writes. Code lives in  
`Labmembers/Erin/code/`: analysis scripts here (`SUPPORT-denoising/analysis/`), analysis configs in  
`configs/analysis/`, job launchers (`run_headless_analysis.sh`, ...) at the top of `code/`.

## 0. Setup: configs and paths

- A config is a MATLAB function in `configs/analysis/` returning a `cfg` struct, e.g.
`config_w25_w27_specific.m`, `config_optoCCKBC_activation_BTSP.m`. Make a new preparation by copying one.
- Every analysis script takes the config name: `support_model_comparison('config_w25_w27_specific')`.
`load_analysis_config.m` adds `configs/analysis` to the path and fills defaults for newer fields. With several
configs present a name is required.
- Outputs go to `<fanlab root>/<cfg.save_subdir>/<cfg.filestr>/` (call it `save_dir`). Give each preparation
its own `filestr` so outputs don't mix.
- Paths: `setup_analysis_paths.m` picks the root (`/Volumes/fanlab` Mac, `/mnt/fanlab` server, `Z:\` Windows);
paths saved on another machine are mapped by `to_local_path.m`.

Main `cfg` fields: `models` (dirnames under each session), `sessions_file` / `sel_sessions` /
`invert_sel_sessions` (which sessions), `use_template` (read `template_mask_results/` files),
`exclude_no_signal`, `exclude_artifacts`, `exclude_cell_if_any_artifact`, `artifact_max_sigma`,
`stim_mode`, `training_windows`, noise-window settings (`noise_len`, `alt_noise_lens`, `spike_margin`,
`stim_margin`, ...), `snippet_len`, `sta_half_win`.

Paths can use placeholders: `cfg.dataset` fills `{dataset}` and `cfg.psnr_cutoff` (e.g. 17) fills `{psnr}` as `psnr17`
(empty = nothing), in `cfg.sessions_file`, `cfg.psnr_audit_dir` and the csv paths in `cfg.training_windows`, e.g.
`'SUPPORT-denoising/datasets/{dataset}/total_sessions_{psnr}.mat'` -> `.../BTSP/total_sessions_psnr17.mat`.

**Several datasets in one run** (`configs/analysis/config_across_datasets.m`): `cfg.dataset = {'DSI','BTSP'}` (and
optionally `cfg.psnr_cutoff = {15, 17}`, one per dataset). The sessions files (and PSNR-audit folders) of all datasets are
pooled by `load_session_list.m` (shared fields only; a cell in two lists is kept once) and every cell gets a `dataset`
label, stored in `recs.mat` / `metrics.mat` / `gains.mat`. `cfg.models` must exist for every session. Outputs then split by
dataset: `model_summary_by_dataset.csv`, `gains_median_summary_by_dataset.csv`, `trained_vs_heldout.csv` (a `dataset`
column, plus an `all` row), `psnr_snr_by_model.png` (one row of panels per dataset), `gain_summary.png` (marker = dataset),
and per-cell figures in `<dataset>/` subfolders. `training_windows` needs explicit csv paths (one per model) in this mode.

## 1. Running on the server

```bash
./run_headless_analysis.sh -c <config> <command>      # e.g. support_model_comparison
./run_headless_analysis.sh -c <config>                # no command = select_noise_windows
./run_headless_analysis.sh -x -c <config> <command>   # dry run
```

Runs `matlab -batch` in a detached tmux session over SSH. Logs and the exact command go to
`code/logs/<tag>_<timestamp>.{log,m}`. `-c` rewrites a bare command name to `name('<config>')`;
for commands with arguments, put the config in yourself. `-n TAG` sets the job name (capped at 47 chars).
Kill a job: `ssh knswift@10.93.5.151 tmux kill-session -t <session name>`.

## 2. Pipeline, in order


| #   | Command                     | Interactive?  | Needs              |
| --- | --------------------------- | ------------- | ------------------ |
| 1   | `select_noise_windows`      | no            | processed sessions |
| 2   | `review_noise_windows`      | yes (display) | 1                  |
| 3   | `support_model_comparison`  | no            | 1 (and 2 if done)  |
| 4   | `model_comparison_plots`    | no            | 3                  |
| 5   | `dataset_summary`           | no            | 3, 4               |
| 6   | `stim_vs_nostim_comparison` | no            | 3, 4               |




### 1. `select_noise_windows` - automatic noise window per cell

- Loads sessions (`load_session_list`: `cfg.sessions_file`, then the `sel_sessions` filter; drops sessions with
no `support_*` folder yet).
- **PSNR audit reuse:** if `datasets/<cfg.dataset>/psnr_audit/psnr_audit_summary.mat|csv` exists (or `cfg.psnr_audit_dir`),
  its noise windows (`noise_start`, `noise_len_used`) are used instead of picking new ones (`load_psnr_audit.m`;
  flag `psnr_audit`, not a review reason). Unreviewed `auto` rows already in `noise_regions.mat` are replaced; cells you
  confirmed / set manually / marked no_signal keep your window; cells the audit found no window for are picked as below.
  Turn off with `cfg.reuse_psnr_audit = false`. The audit's window is shorter than 1000 frames, so the alt-length PSNR may be NaN.
- Per cell, loads the raw trace, spikes and the stim mask (`load_stim_mask`: blue-light frames above
`cfg.stim_thresh`), then `auto_noise_window` picks ONE window (`cfg.noise_len`, default 500 frames):
at least `spike_margin` from any spike and `stim_margin` from any stim frame, from the half of candidates with
least linear drift, and the one closest to the median std (a typical window, not the quietest).
- Fallbacks if no window fits: cleaned traces, then shorter windows down to `min_noise_len`; if stim is on for
at least `continuous_stim_frac` of the recording the stim rule is dropped.
- Resume-safe (saves every 25 cells); cells needing a human look are flagged.
- Writes `noise_regions.mat` (table `noise`: cell_hash, session_path, cell_id, start, status
auto/confirmed/manual/needs_manual, flag, n_valid, noise_std, no_signal, valid_len, source).



### 2. `review_noise_windows` - interactive review

Run in MATLAB with a display. Walks needs_manual, flagged cells, then the rest; click a new window start,
`l` switches window length, `n` marks the cell `no_signal` (excluded later if `cfg.exclude_no_signal`),
`q` quits (decisions save immediately). Edits `noise_regions.mat`; rerun step 3 afterwards (rows with a
changed window are recomputed automatically).

### 3. `support_model_comparison` - the metrics

1. Loads sessions and noise windows; drops `no_signal` cells.
2. **Artifact check** (`flag_trace_artifacts`, if `cfg.exclude_artifacts`): for every cell x trace (raw and each
  model), ratio = max |deviation from median| / (1.4826 x MAD) on the trace as given. Above
   `cfg.artifact_max_sigma` (50) = artifact. With `cfg.exclude_cell_if_any_artifact` the whole cell is dropped if
   raw or any model is flagged; otherwise only raw drops the cell and a flagged model drops just that row.
   Ratios cache in `artifact_flags.mat` (a row recomputes if its trace file changes).
   Writes `excluded_artifact_cells.csv` (raw flagged) and `rerun_template_mask.mat/.csv` (flagged model traces).
3. **Stim handling** (`cfg.stim_mode`):
  - `'all'`: every cell, every spike (default).
  - `'nonstim_sessions'`: only cells in recordings with no stim at all (via `classify_sessions_by_stim`).
  - `'nonstim_periods'`: all cells, but spike height / waveform / STA only from spikes with no stim frame within
  `stim_margin`. The noise window is already stim-free.
  - `'auto'`: sessions if any no-stim recording exists, else periods.
4. `recs.mat`: one struct per cell (session info, spike times from the raw root spike file, noise window,
  firing rate).
5. `metrics.mat`: one row per cell x model (`raw` is a model). Per trace (`compute_trace_metrics`, NO detrending):
  `noise_std` = std over the noise window; `waveform` = mean of +/-`snippet_len` snippets around the spikes;
   `spike_height` = its peak; `psnr_db` = 20 log10(height / noise_std); `psnr_db_alt` at `alt_noise_lens`;
   `sta` (`compute_sta`, spike-triggered average using the model's own spike widths); then
   `waveform_r_vs_raw` and `sta_r_vs_raw` (Pearson r vs the same cell's raw). Also a `trained` column
   (`flag_trained_cells`, see below). The stim mode used is saved in `metrics.Properties.UserData.stim_mode`;
   changing into/out of `nonstim_periods` recomputes everything.
6. Writes `model_summary.csv/.mat` (per model: n cells and median PSNR, change vs raw, retention, noise reduction,
  SNR gain, waveform/STA r) and `psnr_snr_by_model.png` (denoised vs raw PSNR per cell). With
   `cfg.training_windows` set it has one panel per model, dots colored seen (in that model's training windows)
   vs unseen, and also writes `trained_vs_heldout.csv` (per model, seen vs unseen: n cells and median PSNR,
   change vs raw, retention, noise reduction, SNR gain). Without it, one panel colored by model.
7. **Single-pixel SNR** (opt-in, `cfg.pixel_snr = true`; the spike PSNR above is always computed, this is added
   next to it). Eom et al. 2023 report the average single-pixel SNR over cell pixels (Fig. 3d) and, with no ground
   truth, define SNR(x) = 10 log10(max(x) / std(x)) (Methods, Performance metrics; they apply it after baseline
   correction). `compute_recording_pixel_snr` runs each movie through the same preprocessing as `ICA_Pre` /
   `ICA_Choose` (template mode) up to the step that collapses pixels into one trace, then uses the pixels instead:
   1. drop the first `cfg.pixel_skip_frames` (10) frames, double (`load_roi_movie`);
   2. background subtraction (`preprocess_roi_movie`): ring (`subtractRingXtalk`) if the movie's folder has
      `RingMaskAndSignal.fig`, otherwise the corner-box mean trace; both subtract one number per frame;
   3. crop around the cell (ROI bounding box + 5 px, from `Masks.mat`; `load_roi_geometry`);
   4. footprint = the template of the `'T'` branch rebuilt at full resolution: crop mean image, min-max
      normalized, values below 0.4 zeroed, footprint pixels = nonzero. The 2x2 block average of the rebuilt
      weights must match the stored `ICAImgs` in `Masks_BestIcaImgs_template.mat`, otherwise the cell is skipped
      with a warning (e.g. a hand-redrawn ROI);
   5. photobleaching correction of the crop, `pblc(vm(crop))`.
   Not applied, since they act on the aggregated trace: template weighting, z-scoring, high-pass, SLM-off filling.
   Per cell x model (`compute_pixel_metrics`), per footprint pixel over the whole trace, no further baseline
   correction, detrending or sign flip, so max(x) includes the DC offset; dB values are comparable between models
   of the same recording, not with the paper's numbers. Two footprints: each model's own template
   (`pixel_snr_db`, `pixel_snr_db_median`, `n_roi_pixels`, `n_pixel_nonpositive`) and the raw movie's template for
   every model, i.e. identical pixels across models (the same four with `_rawfp`). `n_pixel_nonpositive` = pixels
   with max <= 0, left out of the means.
   Adds those columns to `metrics.mat`, `median_pixel_snr_db` / `median_delta_pixel_snr_db` (and `_rawfp_`) to
   `model_summary.csv`, and `pixel_snr_by_model.png` (one panel per footprint). It loads every movie of every
   recording as double (about 4.6 GB for 30,000 frames of 200x96) plus the raw one, so expect it to be slow and
   memory-hungry. Rows already done are skipped on later runs.

Caches: `recs.mat` and `metrics.mat` are incremental. Set `rerun = true` in the script, or delete them (plus
`artifact_flags.mat`), after changing how metrics are computed.

### 4. `model_comparison_plots`

- **Gains per cell vs raw** (`gains.mat`, `gains.csv`, `gains_median_summary.csv`):
  - retention = spike_height_model / spike_height_raw
  - noise reduction = noise_std_raw / noise_std_model
  - total SNR gain = retention x noise reduction (its dB value equals the PSNR change; the script prints the check)
  Cells with negative retention are left out of the plots.
- `gain_summary.png`: retention vs noise-reduction scatter with iso-gain lines, plus per-model swarms of
retention, noise reduction and SNR gain (median in black; black ring = trained on).
- **Per-cell trace figures** (3 x 4 tiles): whole trace stacked (raw on top, units of raw spike height, noise window
in yellow, stim in blue), median-preserved spike over all spikes, the same for non-stim spikes (only if the
recording has stim), zoomed mean waveform, gain dots, full mean waveform. Traces are plotted as given; only
display offsets are applied.
  - Recordings with no stim are saved in `nonstim_recordings/<fov>/`, others in `<fov>/` folders.
  - If metrics were made with `nonstim_periods`: figures go under `nonstim_periods/`, stim periods (+/- margin)
  are cut out of the trace, and only cells with spikes outside stim get a figure.
  - `resume` skips figures newer than `layout_time` (bump it in the script when the layout changes).



### 5. `dataset_summary`

Pooled figures per cell: `summary_overview.png` (grand-average waveform, noise spectra, paired PSNR, gain CIs),
`summary_stim_vs_nonstim.png` (waveform and per-spike preservation near vs far from stim), cache `summary_data.mat`.

### 6. `stim_vs_nostim_comparison`

Older stim comparison: classifies each session as no_stim / has_stim / unknown (`classify_sessions_by_stim` -> `stim_regions.mat`),
then writes `stim_group_metrics.csv`, `stim_vs_nostim.png` (metric panels per model with rank-sum p), the PSNR-vs-raw
figures `stim_vs_nostim_psnr_by_model.png` / `_by_group.png`, and `stim_vs_nostim_outliers.csv` (robust-z outliers).
It is not `stim_mode`-aware: use it with `stim_mode = 'all'`.

## 3. Rerunning flagged recordings (preprocessing side)

Flagged model traces are listed in `rerun_template_mask.csv`. From `code/`:

```bash
./run_headless_both.sh -c optoCCKBC_BTSP_rerun
```

reruns ICA Pre / ICA Choose / spike selection only for the recordings flagged for each model dir
(`preprocessing_headless(..., rerun_flagged=...)`); configs live in `configs/preprocessing/`.
`optoCCKBC_BTSP_spikes.sh` / `w25_w27_specific_spikes.sh` rerun only step 6. Afterwards rerun step 3.

## 4. Metric definitions (quick reference)

- **PSNR** = 20 log10(peak of mean spike waveform / std of noise window), same spikes and window for raw and
models.
- **Spike retention** = model peak / raw peak. **Noise reduction** = raw noise std / model noise std.
**Total SNR gain** = product of the two.
- No detrending: slow / subthreshold activity stays in the noise window and the waveform. Subthreshold
preservation itself is not measured.



## 5. Gotchas

- Model spike times are copied from raw: raw side reads the ROOT `<session>/inter_spikeT_spikeW.mat`
(`load_spikes.m`), not the one in `template_mask_results/`.
- `cfg.stim_mode` is read by step 4 from `metrics.mat`; if you change it, rerun step 3 first (step 4 warns on a mismatch).
- `cfg.training_windows = {{model_dirname, selected_windows.csv}}` is empty in both configs until the model -> dataset
mapping is filled in; cells are matched on session_path + cell_id.
- Job names over 63 characters break MATLAB's `run`; the launchers cap the tag at 47.

