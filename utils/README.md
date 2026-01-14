# Utils info

## Main Functions

### discover_sessions.m

**Purpose**: Discovers and catalogs all imaging sessions for a given animal preparation from raw data directories.

**Functionality**:
- Recursively searches through animal directories to find all imaging sessions
- Supports both string paths and `containers.Map` objects for flexible data organization
- Checks for `Sq_camera.bin` file to identify valid sessions
- Caches discovered sessions to avoid redundant file system operations
- Handles exclusion of specific session names/dates
- Processes directory structure: `animal/date/slice/FOV/session/`

**Inputs**:
- `raw_root`: String path or `containers.Map` object specifying root directory(ies) containing animal data
  - If string: Path to directory containing animal subdirectories
  - If `containers.Map`: Map with animal IDs as keys and their root paths as values
- `animal_id`: (Optional) String specifying animal preparation ID/prefix to filter by
  - Uses prefix matching (case-insensitive)
  - If empty, processes all animals found
- `save_dir`: (Optional) Directory to save/load cached sessions
  - If provided and cached file exists, loads from cache instead of re-discovering
  - Saves discovered sessions as `sessions_[animal_id].mat`
- `exclude_session_names`: (Optional) Cell array or string of session names/dates to exclude
  - Sessions containing any excluded string will be skipped

**Output**:
- `sessions`: Struct array with fields:
  - `anim_id`: Animal ID string
  - `session_path`: Full path to session directory
  - `session_name`: Session directory name
  - `FOV`: FOV number (numeric)

**Directory Structure Expected**:
```
raw_root/
  animal_id/
    date/
      slice/
        FOV1/
          session_name/
            Sq_camera.bin  ← Required file
        FOV2/
          session_name/
            Sq_camera.bin
```

**Usage Examples**:
```matlab
% Simple discovery from single root
sessions = discover_sessions('/Volumes/fanlab/Data', 'cck-gevi-w03');

% Using containers.Map for multiple roots
custom_roots = containers.Map( ...
    {'cck-gevi-w03', 'cck-gevi-w05'}, ...
    {'/path/to/w03', '/path/to/w05'} ...
);
sessions = discover_sessions(custom_roots, 'cck-gevi');

% With caching
sessions = discover_sessions(raw_root, animal_id, '/path/to/save');

% Excluding specific dates
sessions = discover_sessions(raw_root, animal_id, save_dir, {'2025-01-01', 'bad_session'});
```

**Performance Notes**:
- First run scans file system and may take time for large datasets
- Subsequent runs with same `save_dir` and `animal_id` load from cache (much faster)
- Cached files are named `sessions_[animal_id].mat`

---

### generate_sessions_struct.m

**Purpose**: Filters discovered sessions based on specific criteria (FOV, slice, session IDs) to create a subset for processing.

**Functionality**:
- Takes output from `discover_sessions.m` and applies multiple filters
- Filters by session IDs (dates), FOV numbers, and slice names/indices
- Creates filtered struct array ready for batch processing
- Optionally saves filtered sessions to disk

**Inputs**:
- `discovered_sessions`: Struct array from `discover_sessions.m` with fields:
  - `anim_id`, `session_path`, `session_name`, `FOV`
  - Additional fields may be present (e.g., `cell_id`, `cell_hash` for preprocessed data)
- `path`: Struct with fields:
  - `sess_ids`: (Optional) Cell array of session IDs to include
    - Session ID is extracted from `session_path` (typically the date directory)
    - Only sessions matching these IDs are kept
  - `save_dir`: (Optional) Directory to save filtered sessions
- `sel_FOVs`: (Optional) Vector of FOV numbers to include
  - If empty or not provided, all FOVs are included
  - Example: `[1, 2, 3]` includes only FOVs 1, 2, and 3
- `sel_slices`: (Optional) Cell array of slice names, vector of slice indices, or single string
  - If cell array: Exact match with slice names (e.g., `{'Slice1', 'Slice2'}`)
  - If numeric: Extracts numbers from slice names and matches (e.g., `[1, 2]` matches 'Slice1', 'Slice2')
  - If empty or not provided, all slices are included
- `save_flag`: (Optional) Logical flag to save filtered sessions
  - If `true` and `path.save_dir` is provided, saves as `sessions.mat`

**Output**:
- `sessions`: Filtered struct array with same fields as input
  - Only sessions matching all specified criteria are included
  - If slice filtering is used, adds `slice` field to output structs

**Filtering Logic**:
- All filters are applied with AND logic (session must match ALL criteria)
- Session ID filter: Extracts date from `session_path` and matches against `path.sess_ids`
- FOV filter: Direct numeric comparison
- Slice filter: Extracts slice name from path and matches against `sel_slices`

**Usage Examples**:
```matlab
% Discover all sessions
all_sessions = discover_sessions(raw_root, animal_id);

% Filter by specific session dates
path.sess_ids = {'2025-01-13-VR-V_blue', '2025-01-14-VR-V_blue'};
sessions = generate_sessions_struct(all_sessions, path);

% Filter by FOV only
sessions = generate_sessions_struct(all_sessions, [], [1, 2]);

% Filter by slice names
sessions = generate_sessions_struct(all_sessions, [], [], {'Slice1', 'Slice2'});

% Filter by slice numbers
sessions = generate_sessions_struct(all_sessions, [], [], [1, 2]);

% Combined filtering: specific sessions, FOVs 1-2, and save
path.sess_ids = {'2025-01-13-VR-V_blue'};
path.save_dir = '/path/to/save';
sessions = generate_sessions_struct(all_sessions, path, [1, 2], [], true);
```

**Typical Workflow**:
```matlab
% Step 1: Discover all sessions
all_sessions = discover_sessions(path.root.data, animal_id, path.root.data);

% Step 2: Convert paths for current OS
all_sessions = convert_struct_paths(all_sessions, root_path);

% Step 3: Filter to specific sessions
path.sess_ids = {'session1', 'session2'};
sel_sessions = generate_sessions_struct(all_sessions, path, sel_FOVs, sel_slices);
```

---

### filter_sessions_for_support.m

**Purpose**: Filters sessions to only include those that have SUPPORT denoised data available.

**Functionality**:
- Checks for existence of SUPPORT output files in session directories
- Supports both pre-motion and post-motion correction workflows
- Looks for target file in `support/` subdirectory or `support/[motion_corr]/` subdirectory

**Inputs**:
- `sessions`: Struct array from `discover_sessions.m`
- `motion_corr`: String, `'pre-motion'` or `'post-motion'`
  - Determines subdirectory structure to check
- `target_file`: (Optional) Name of target file to check for
  - Default: `'denoised.tiff'`

**Output**:
- `support_sessions`: Filtered struct array containing only sessions with SUPPORT data

**Directory Structure Checked**:
- Post-motion: `session_path/support/post-motion/denoised.tiff`
- Pre-motion: `session_path/support/denoised.tiff`

**Usage Examples**:
```matlab
% Filter for sessions with post-motion SUPPORT data
support_sessions = filter_sessions_for_support(sessions, 'post-motion');

% Filter for sessions with pre-motion SUPPORT data
support_sessions = filter_sessions_for_support(sessions, 'pre-motion');

% Check for different target file
support_sessions = filter_sessions_for_support(sessions, 'post-motion', 'raw.tiff');
```
---

## Typical Workflow

### Complete Session Discovery and Filtering Pipeline

```matlab
% 1. Set up paths
if ismac || isunix
    root_path = '/Volumes/fanlab';
elseif ispc
    root_path = 'Z:';
end

path.root.data = fullfile(root_path, 'Labmembers', 'Kohl', 'CCK');
path.anim_ids = {'cck-gevi-w03'};
path.sess_ids = {'2025-01-13-VR-V_blue'};

% 2. Discover all sessions for animal
all_sessions = discover_sessions(path.root.data, path.anim_ids{1}, path.root.data);

% 3. Convert paths to current OS
all_sessions = convert_struct_paths(all_sessions, root_path);

% 4. Filter to specific sessions, FOVs, slices
sel_FOVs = [1, 2];
sel_slices = [];
sel_sessions = generate_sessions_struct(all_sessions, path, sel_FOVs, sel_slices);

% 5. (Optional) Filter for sessions with SUPPORT data
support_sessions = filter_sessions_for_support(sel_sessions, 'post-motion');

% 6. Process sessions
for s = 1:numel(sel_sessions)
    session_path = sel_sessions(s).session_path;
    % ... processing code ...
end
```

---

## File Dependencies

### Input Files (for discover_sessions):
- `Sq_camera.bin`: Required file in each session directory to identify valid sessions
- Directory structure: `animal/date/slice/FOV/session/`

### Generated Files:
- `sessions_[animal_id].mat`: Cached session discovery results (if `save_dir` provided)
- `sessions.mat`: Filtered sessions (if `save_flag == true` in `generate_sessions_struct`)

---

## Notes

- **Caching**: `discover_sessions` caches results to avoid redundant file system scans. Delete cache files to force re-discovery.
- **Path Conversion**: Always use `convert_struct_paths` when loading sessions saved on a different OS.
