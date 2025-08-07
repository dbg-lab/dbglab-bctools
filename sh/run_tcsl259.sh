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
export PARALLEL_JOBS=4

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