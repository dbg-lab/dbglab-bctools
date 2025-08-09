#!/bin/bash

# =============================================================================
# TCSL259 Pipeline Example
# =============================================================================
# This is an example wrapper script that shows how to configure and run
# the barcode pipeline for a specific experiment (TCSL259).
#
# Copy this script and modify the parameters below for your own experiments.
# =============================================================================

# Required parameters - customize these for your experiment
export S3_PATH="s3://dbglab-tcsl/tcsl259"
export FILE_PATTERN="TCSL259_.*_L006"
export OUT_DIR="~/tcsl259/out"
export STATS_DIR="~/tcsl259/stats"

# Parallelization settings - adjust based on your workload and hardware
export PARALLEL_FILES=12    # Number of samples to process concurrently
export UGREP_THREADS=4      # Threads for all ugrep operations (filtering and pattern matching)
export SORT_THREADS=4       # Threads for sorting within each sample

# Tuning guide, based on available cores and number of samples:
# - Many small files: High PARALLEL_FILES (8-16), Lower UGREP_THREADS/SORT_THREADS (1-2)
# - Few large files: Lower PARALLEL_FILES (2-4), Higher UGREP_THREADS/SORT_THREADS (8-16)
# PARALLEL_FILES x UGREP_THREADS/SORT_THREADS should be about the number of cores available

# Directory configuration
export TMP_DIR="~/data"  # Temporary directory for sorting (use fast storage if available)

# Optional: Barcode matching parameters (showing defaults)
# Only customize these if your experiment uses different barcode adjacent regions
export BC_PREFIX="ACCCAGGTCCTG"
export BC_SUFFIX="TCGGCTGCTTTA"
export BC_LEN_MIN=59
export BC_LEN_MAX=71

# Optional: For testing - limit to fewer reads (uncomment to enable)
#export MAX_READS=10000  # Process only first 10,000 reads per sample (comment out for full run)

echo "Configuration complete. Running pipeline..."
echo ""

# Run the pipeline
./run_bc_pipeline.sh