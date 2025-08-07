#!/bin/bash

# =============================================================================
# Barcode Pipeline Functions
# =============================================================================
# These functions expect the following variables to be set by the calling script:
# - S3_PATH: S3 bucket path for input files
# - OUT_DIR: Local output directory (all outputs are saved locally)
# - STATS_DIR: Local stats directory  
# - PY_DIR: Directory containing Python scripts
# - TMP_DIR: Temporary directory for sorting (only used by paired-end pipeline)
#
# Optional parameters (have defaults):
# - BC_PREFIX: DNA prefix sequence for barcode matching (default: ACCCAGGTCCTG)
# - BC_SUFFIX: DNA suffix sequence for barcode matching (default: TCGGCTGCTTTA)  
# - BC_LEN_MIN: Minimum barcode region length (default: 59)
# - BC_LEN_MAX: Maximum barcode region length (default: 71)
# - MAX_READS: If set, limit processing to this many reads (useful for testing)
# =============================================================================

# Program paths (set defaults, can be overridden)
FLASH2=${FLASH2:-~/FLASH2-2.2.00/flash2}

# Set TMP_DIR default if not provided by calling script
TMP_DIR=${TMP_DIR:-~/data}

# Barcode matching parameters (can be overridden)
BC_PREFIX=${BC_PREFIX:-ACCCAGGTCCTG}
BC_SUFFIX=${BC_SUFFIX:-TCGGCTGCTTTA}
BC_LEN_MIN=${BC_LEN_MIN:-59}
BC_LEN_MAX=${BC_LEN_MAX:-71}

# Testing parameter (can be overridden)
MAX_READS=${MAX_READS:-}  # If set, limit to this many reads (useful for testing)

fuzzy_bc_region_match() {
    prefix=$1
    pipeline=$2

    # Checking if R1 file exists in S3
    aws s3 ls "$S3_PATH/${prefix}_R1_001.fastq.gz" || {
        echo "R1 fastq file is missing: $S3_PATH/${prefix}_R1_001.fastq.gz"
        return
    }
    
    # Only check R2 for paired-end pipeline
    if [[ "$pipeline" == "fuzzy_bc_pipeline" ]]; then
        aws s3 ls "$S3_PATH/${prefix}_R2_001.fastq.gz" || {
            echo "R2 fastq file is missing: $S3_PATH/${prefix}_R2_001.fastq.gz"
            return
        }
    fi

    # Check if the output file exists locally
    if [ ! -f "$OUT_DIR/${prefix}_bc_region.txt.gz" ]; then
        # Added function call to run the pipeline
        $pipeline "$prefix"
    else
        # Check if the output file is empty
        if [ ! -s "$OUT_DIR/${prefix}_bc_region.txt.gz" ]; then
            echo "Output file $OUT_DIR/${prefix}_bc_region.txt.gz is empty. Deleting files and rerunning..."

            # Deleting all files in the STATS_DIR and OUT_DIR for the prefix
            rm "$STATS_DIR/${prefix}"*
            rm "$OUT_DIR/${prefix}"*

            # Added function call to run the pipeline
            $pipeline "$prefix"
        else
            echo "Fuzzy BC region match output $OUT_DIR/${prefix}_bc_region.txt.gz already exists."
        fi
    fi
}

fuzzy_bc_pipeline() {
    prefix=$1

    echo "Running fuzzy BC region match for $prefix..."

    # Pipe data from S3 into the FLASH2 command
    $FLASH2 \
        -c \
        -r 150 \
        -f 130 \
        -O \
        <(aws s3 cp "$S3_PATH/${prefix}_R1_001.fastq.gz" - | zcat - | { if [[ -n "$MAX_READS" ]]; then head -$((4 * MAX_READS)); else cat; fi; }) \
        <(aws s3 cp "$S3_PATH/${prefix}_R2_001.fastq.gz" - | zcat - | { if [[ -n "$MAX_READS" ]]; then head -$((4 * MAX_READS)); else cat; fi; }) \
        2> $STATS_DIR/${prefix}_flash_stderr.txt \
    | tee >(wc -l | awk '{print $1/4}'> $STATS_DIR/${prefix}.fq_linecount.txt) \
    | grep -P '^[ATGCN]+$' \
    | ugrep -Z6 -o "${BC_PREFIX}.{${BC_LEN_MIN},${BC_LEN_MAX}}${BC_SUFFIX}" \
    | ugrep -Z4 -o "${BC_PREFIX}.*" \
    | tee >(wc -l > $STATS_DIR/${prefix}.out_linecount.txt) \
    | tee >(awk 'NR % 10000 == 0 {
        print "[" strftime("%H:%M:%S") "] '$prefix': processed " NR " sequences"; fflush()}' \
            > $STATS_DIR/${prefix}.progress.log) \
    | sort --temporary-directory=$TMP_DIR - | uniq -c \
    | tee >(gzip > $OUT_DIR/${prefix}_bc_region.txt.gz) \
    | python3 $PY_DIR/itam_costim_bc_regex.py - \
        2> $STATS_DIR/${prefix}_bc_regex.txt \
    | gzip - > $OUT_DIR/${prefix}_bc_table.csv.gz

    echo "Fuzzy BC region match completed for $prefix"
}

fuzzy_bc_pipeline_read1() {
    prefix=$1

    echo "Running R1-only fuzzy BC region match for $prefix..."

    # Pipe data from S3 into ugrep search for the barcode region
    aws s3 cp "$S3_PATH/${prefix}_R1_001.fastq.gz" - | zcat - \
    | { if [[ -n "$MAX_READS" ]]; then head -$((4 * MAX_READS)); else cat; fi; } \
    | tee >(wc -l | awk '{print $1/4}'> $STATS_DIR/${prefix}.fq_linecount.txt) \
    | grep -P '^[ATGCN]+$' \
    | ugrep -Z6 -o "${BC_PREFIX}.{${BC_LEN_MIN},${BC_LEN_MAX}}${BC_SUFFIX}" \
    | ugrep -Z4 -o "${BC_PREFIX}.*" \
    | tee >(wc -l > $STATS_DIR/${prefix}.out_linecount.txt) \
    | tee >(awk 'NR % 10000 == 0 {
        print "[" strftime("%H:%M:%S") "] '$prefix': processed " NR " sequences"; fflush()}' \
            > $STATS_DIR/${prefix}.progress.log) \
    | sort --temporary-directory=$TMP_DIR | uniq -c \
    | tee >(gzip > $OUT_DIR/${prefix}_bc_region.txt.gz) \
    | python3 $PY_DIR/itam_costim_bc_regex.py - \
        2> $STATS_DIR/${prefix}_bc_regex.txt \
    | gzip - > $OUT_DIR/${prefix}_bc_table.csv.gz

    echo "Fuzzy R1-only BC region match completed for $prefix"
}
