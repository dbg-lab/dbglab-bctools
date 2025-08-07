#!/bin/bash

# =============================================================================
# Simple Barcode Pipeline Runner
# =============================================================================
# A minimal script that runs the fuzzy barcode matching pipeline using
# bash pipelines and GNU parallel in the spirit of Unix tools.
#
# Usage: 
#   # Set parameters in your shell:
#   export S3_PATH="s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/repstim_repool2"
#   export FILE_PATTERN="TCSL236_repstim_.*L006"
#   export OUT_DIR="~/tcsl236_il30_repstim/out"
#   export STATS_DIR="~/tcsl236_il30_repstim/stats"
#   export PARALLEL_JOBS=28
#   ./run_bc_pipeline.sh
#
# Or with command line args:
#   ./run_bc_pipeline.sh "s3://path" "file_pattern" "out_dir" "stats_dir" [jobs]
# =============================================================================

# Command line args override environment variables
if [[ $# -ge 4 ]]; then
    S3_PATH="$1"
    FILE_PATTERN="$2"
    OUT_DIR="$3"
    STATS_DIR="$4"
    PARALLEL_JOBS="${5:-28}"
fi

# Default values if not set
N_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
S3_PATH="${S3_PATH:-s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/repstim_repool2}"
FILE_PATTERN="${FILE_PATTERN:-TCSL236_repstim_.*L006}"
PIPELINE_FUNC="${PIPELINE_FUNC:-fuzzy_bc_pipeline_read1}"
PARALLEL_JOBS="${PARALLEL_JOBS:-$((N_CORES / 2))}"
OUT_DIR="${OUT_DIR:-~/tcsl236_il30_repstim/out}"
STATS_DIR="${STATS_DIR:-~/tcsl236_il30_repstim/stats}"
PY_DIR="${PY_DIR:-$(dirname "$0")/../py}"
TMP_DIR="${TMP_DIR:-~/data}"

# Expand tildes
OUT_DIR=$(eval echo "$OUT_DIR")
STATS_DIR=$(eval echo "$STATS_DIR")
PY_DIR=$(eval echo "$PY_DIR")
TMP_DIR=$(eval echo "$TMP_DIR")

echo "=== Barcode Pipeline Configuration ==="
echo "S3_PATH: $S3_PATH"
echo "FILE_PATTERN: $FILE_PATTERN"
echo "PIPELINE_FUNC: $PIPELINE_FUNC"
echo "PARALLEL_JOBS: $PARALLEL_JOBS"
echo "OUT_DIR: $OUT_DIR"
echo "STATS_DIR: $STATS_DIR"
echo "======================================"

# Setup
source "$(dirname "$0")/bc_pipeline_fxns.sh"
mkdir -p "$OUT_DIR" "$STATS_DIR"
export S3_PATH OUT_DIR STATS_DIR PY_DIR TMP_DIR BC_PREFIX BC_SUFFIX BC_LEN_MIN BC_LEN_MAX MAX_READS
export -f fuzzy_bc_region_match fuzzy_bc_pipeline fuzzy_bc_pipeline_read1

# Run the pipeline
echo "Getting file list and running pipeline..."
aws s3 ls "$S3_PATH/" | grep -Po "$FILE_PATTERN" | uniq | sort \
    | parallel --jobs "$PARALLEL_JOBS" "fuzzy_bc_region_match {} $PIPELINE_FUNC"

echo "Pipeline processing complete."

# Quick summary of results
echo ""
echo "=== Results Summary ==="
total_samples=$(aws s3 ls "$S3_PATH/" | grep -Po "$FILE_PATTERN" | uniq | wc -l)
successful_outputs=$(find "$OUT_DIR" -name "*_bc_table.csv.gz" -size +0c 2>/dev/null | wc -l)
failed_count=$((total_samples - successful_outputs))

echo "Total samples: $total_samples"
echo "Successful: $successful_outputs"
echo "Failed: $failed_count"

if [[ $failed_count -gt 0 ]]; then
    echo ""
    echo "Failed samples (no output or empty output):"
    aws s3 ls "$S3_PATH/" | grep -Po "$FILE_PATTERN" | uniq | sort | while read sample; do
        output_file="$OUT_DIR/${sample}_bc_table.csv.gz"
        if [[ ! -f "$output_file" || ! -s "$output_file" ]]; then
            echo "  - $sample"
        fi
    done
fi

# Merge results if we have successful outputs
if [[ $successful_outputs -gt 0 ]]; then
    echo ""
    echo "Merging successful results..."
    python3 "$PY_DIR/merge_bc_dfs.py" --min-merge-count 1 --verbose "$OUT_DIR"/*_bc_table.csv.gz \
        | gzip > "$OUT_DIR/merged_df.csv.gz"
    echo "Merged results saved to: $OUT_DIR/merged_df.csv.gz"
    
    if [[ $failed_count -gt 0 ]]; then
        echo ""
        echo "WARNING: $failed_count samples failed. You can re-run to retry failed samples."
    fi
else
    echo "No successful outputs to merge."
    exit 1
fi

echo "Done!" 