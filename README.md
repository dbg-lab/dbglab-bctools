# dbglab-bctools

Bioinformatics tools for barcode processing and NGS data analysis.

## Pipeline Scripts

### Main Pipeline
- `sh/run_bc_pipeline.sh` - Main barcode processing pipeline runner
- `sh/bc_pipeline_fxns.sh` - Core pipeline functions
- `sh/run_tcsl259.sh` - Example configuration script for TCSL259 experiment

### Python Scripts
- `py/itam_costim_bc_regex.py` - Barcode regex processing and extraction
- `py/merge_bc_dfs.py` - Merge results across samples

## Usage

1. **Copy and customize the example script:**
   ```bash
   cp sh/run_tcsl259.sh sh/run_myexperiment.sh
   # Edit parameters for your experiment
   ```

2. **Set your parameters:**
   ```bash
   export S3_PATH="s3://your-bucket/path"
   export FILE_PATTERN="YOUR_EXP_.*_L006"
   export OUT_DIR="~/myexp/out"
   export STATS_DIR="~/myexp/stats"
   ```

3. **Run the pipeline:**
   ```bash
   ./sh/run_bc_pipeline.sh
   ```

4. **Optimize for your workload:**
   ```bash
   # For many small files (default):
   export PARALLEL_FILES=16  # Process many files concurrently
   
   # For few large files:
   export PARALLEL_FILES=4   # Fewer concurrent files  
   export UGREP_THREADS=8    # More threads per file
   export SORT_THREADS=8     # More threads for sorting
   ```

## Pipeline Overview

The pipeline processes FASTQ files from S3 to extract and count structured barcode combinations across many samples. For each sample, it:

1. Downloads FASTQ data from S3
2. Extracts barcode regions using regex patterns
3. Counts unique barcode combinations
4. Merges results across all samples

## Outputs

- **`{sample}_bc_region.txt.gz`** - Raw barcode regions with counts (before regex parsing)
- **`{sample}_bc_table.csv.gz`** - Structured barcode data per sample with columns:
  - `count`, `itam_bc_o`, `itam_umi_o`, `costim_bc_o`, `costim_umi_o`, `sl_o`, `sl_num`
- **`merged_df.csv.gz`** - Combined barcode counts across all samples

## Data Transfer

See `RCLONE.md` for efficient methods to transfer raw sequencing data from SFTP servers to S3 before running the pipeline.

## Key Parameters

- `S3_PATH` - S3 bucket containing FASTQ files
- `FILE_PATTERN` - Regex pattern to match sample files
- `OUT_DIR`, `STATS_DIR` - Local output directories
- `MAX_READS` - Limit reads for testing (optional)
- `BC_PREFIX`, `BC_SUFFIX` - Barcode flanking sequences
- `BC_LEN_MIN`, `BC_LEN_MAX` - Barcode region length range

### Parallelization Parameters

- `PARALLEL_FILES` - Number of samples to process concurrently (default: half of CPU cores)
- `UGREP_THREADS` - Number of threads for all ugrep operations (default: 4)
- `SORT_THREADS` - Number of threads for sorting operations (default: 4)

## Requirements

- AWS CLI configured with S3 access
- GNU `parallel` for concurrent processing
- `ugrep` for pattern matching
- Python 3 with pandas, regex packages

## Notes

- Barcode structure is currently hardcoded in `itam_costim_bc_regex.py` 
- Pipeline automatically skips existing outputs and merges successful results
- **Storage warning**: Pipeline downloads and processes data locally - ensure sufficient EBS storage or processing will fail

## Future Improvements

- Parameterize barcode structure for different experiments (move from Python script to shell parameters)
- Add clean EBS → S3 data transfer handling to avoid local storage limitations

## Legacy Scripts

See `old/` directory for previous SFTP-based scripts and utilities. 