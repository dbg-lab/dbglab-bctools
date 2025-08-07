#!/bin/bash

# Define SFTP server parameters
SFTP_USER=hiseq_user
SFTP_HOST=fastq.ucsf.edu
SFTP_DIR=/SSD/20231004_LH00132_0158_A225GLLLT3_10B_300/DBGKTR09
SFTP_PASS=b1gdata

# Define AWS S3 bucket details
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/cytokine

# Define AWS S3 bucket details
S3_BUCKET=roybal-tcsl
S3_PREFIX=tcsl_aav/ngs/illumina_30/cytokine

# Define local dirs and progreams
FLASH2=~/FLASH2-2.2.00/flash2
BWA=~/bwa/bwa
SAMTOOLS=~/samtools/samtools

PY_DIR=~/tcsl236/py
STATS_DIR=~/tcsl236_il30_cyto/stats
FA_DIR=~/tcsl236/fa
OUT_DIR=~/tcsl236_il30_cyto/out

TMP_DIR=~/data

# Function to upload a single file to S3
upload_to_s3() {
    local file=$1
    file=$(echo "$file" | sed 's/ *$//')  # This trims trailing spaces
    echo "Transferring file ${file}"
    
    # Check if the file already exists in S3
    if aws s3api head-object --bucket "${S3_BUCKET}" --key "${S3_PREFIX}/${file}" &> /dev/null; then
        echo "WARNING: File ${file} already exists in S3. Skipping transfer."
        return
    fi

    # Download the file from SFTP server to local disk
    sshpass -p ${SFTP_PASS} sftp -oBatchMode=no \
        -oStrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR}/${file} /large_tmp
    echo "File ${file} transferred to local disk."

    # Upload to S3
    aws s3 cp ${file} ${S3_PATH}/${file}
    echo "File ${file} transferred to S3."
    
    # Get local file size
    local_size=$(stat -c%s "${file}")
    # Get S3 file size
    s3_size=$(aws s3api head-object --bucket "${S3_BUCKET}" --key "${S3_PREFIX}/${file}" | jq -r .ContentLength)
    if [ "$local_size" == "$s3_size" ]; then
        echo "File sizes match. Deleting local file."
        rm ${file}
    else
        echo "WARNING: File sizes do not match for file ${file}."
    fi
}

# Function to download and sample FASTQ files
download_fastq_sample() {
    local file=$1
    local n_records=${2:-1000}  # Default to 1000 records if not specified
    local output_dir=${3:-./samples}  # Default to ./samples if not specified
    
    file=$(echo "$file" | sed 's/ *$//')  # This trims trailing spaces
    echo "Sampling ${n_records} records from file ${file}"
    
    # Check if file appears to be a FASTQ file
    if [[ ! "$file" =~ \.fastq\.gz$ ]]; then
        echo "WARNING: File ${file} does not appear to be a gzipped FASTQ file. Skipping."
        return
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "${output_dir}"
    
    # Generate output filename
    local base_name=$(basename "${file}" .fastq.gz)
    local output_file="${output_dir}/${base_name}.head${n_records}.fastq.gz"
    
    # Check if the sampled file already exists
    if [ -f "${output_file}" ]; then
        echo "WARNING: Sampled file ${output_file} already exists. Skipping."
        return
    fi
    
    # Calculate number of lines to extract (4 lines per FASTQ record)
    local n_lines=$((n_records * 4))
    
    echo "Downloading and sampling first ${n_records} records (${n_lines} lines) from ${file}..."
    
    # Download file from SFTP, decompress, take first N records, and re-compress
    sshpass -p ${SFTP_PASS} sftp -oBatchMode=no \
        -oStrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR}/${file} - \
        | zcat \
        | head -n ${n_lines} \
        | gzip > "${output_file}"
    
    # Check if the output file was created successfully
    if [ -f "${output_file}" ] && [ -s "${output_file}" ]; then
        local output_size=$(stat -c%s "${output_file}")
        echo "Successfully created sampled file ${output_file} (${output_size} bytes)"
    else
        echo "ERROR: Failed to create sampled file ${output_file}"
        return 1
    fi
}

fuzzy_bc_region_match() {
    prefix=$1
    pipeline=$2

    # Checking if files exist in S3
    aws s3 ls "$S3_PATH/${prefix}_R1_001.fastq.gz" || {
        echo "R1 fastq file is missing: $S3_PATH/${prefix}_R1_001.fastq.gz"
        return
    }
    
    aws s3 ls "$S3_PATH/${prefix}_R2_001.fastq.gz" || {
        echo "R2 fastq file is missing: $S3_PATH/${prefix}_R2_001.fastq.gz"
        return
    }

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

    # Your existing pipeline command here
    $FLASH2 \
        -c \
        -r 150 \
        -f 130 \
        -O \
        <(aws s3 cp "$S3_PATH/${prefix}_R1_001.fastq.gz" - | zcat -) \
        <(aws s3 cp "$S3_PATH/${prefix}_R2_001.fastq.gz" - | zcat -) \
        2> $STATS_DIR/${prefix}_flash_stderr.txt \
    | tee >(wc -l | awk '{print $1/4}'> $STATS_DIR/${prefix}.fq_linecount.txt) \
    | grep -P '^[ATGCN]+$' \
    | ugrep -Z6 -o 'ACCCAGGTCCTG.{59,71}TCGGCTGCTTTA' \
    | ugrep -Z4 -o 'ACCCAGGTCCTG.*' \
    | tee >(wc -l > $STATS_DIR/${prefix}.out_linecount.txt) \
    | sort --temporary-directory=$TMP_DIR - | uniq -c \
    | tee >(cat - > $OUT_DIR/${prefix}_bc_region.txt.gz) \
    | python3 $PY_DIR/itam_costim_bc_regex.py - \
        2> $STATS_DIR/${prefix}_bc_regex.txt \
    | gzip - > $OUT_DIR/${prefix}_bc_table.csv.gz

    echo "Fuzzy BC region match completed for $prefix"
}

fuzzy_bc_pipeline_read1() {
    prefix=$1

    echo "Running R1-only fuzzy BC region match for $prefix..."

    # Pipe data from S3 into the FLASH2 command
    aws s3 cp "$S3_PATH/${prefix}_R1_001.fastq.gz" - | zcat - \
    | tee >(wc -l | awk '{print $1/4}'> $STATS_DIR/${prefix}.fq_linecount.txt) \
    | grep -P '^[ATGCN]+$' \
    | ugrep -Z6 -o 'ACCCAGGTCCTG.{59,71}TCGGCTGCTTTA' \
    | ugrep -Z4 -o 'ACCCAGGTCCTG.*' \
    | tee >(wc -l > $STATS_DIR/${prefix}.out_linecount.txt) \
    | sort | uniq -c \
    | tee >(cat - > $OUT_DIR/${prefix}_bc_region.txt.gz) \
    | python3 $PY_DIR/itam_costim_bc_regex.py - \
        2> $STATS_DIR/${prefix}_bc_regex.txt \
    | gzip - > $OUT_DIR/${prefix}_bc_table.csv.gz

    echo "Fuzzy R1-only BC region match completed for $prefix"
}

fuzzy_bc_pipeline_read1_s3() {
    prefix=$1

    echo "Running R1-only fuzzy BC region match for $prefix..."

    # Pipe data from S3 into the FLASH2 command
    aws s3 cp "$S3_PATH/${prefix}_R1_001.fastq.gz" - | zcat - \
    | tee >(wc -l | awk '{print $1/4}'> $STATS_DIR/${prefix}.fq_linecount.txt) \
    | grep -P '^[ATGCN]+$' \
    | ugrep -Z6 -o 'ACCCAGGTCCTG.{59,71}TCGGCTGCTTTA' \
    | ugrep -Z4 -o 'ACCCAGGTCCTG.*' \
    | tee >(wc -l > $STATS_DIR/${prefix}.out_linecount.txt) \
    | sort | uniq -c \
    | tee >(aws s3 cp - $S3_OUT_PATH/${prefix}_bc_region.txt.gz) \
    | python3 $PY_DIR/itam_costim_bc_regex.py - \
        2> $STATS_DIR/${prefix}_bc_regex.txt \
    | gzip - | aws s3 cp - $S3_OUT_PATH/${prefix}_bc_table.csv.gz

    echo "Fuzzy R1-only BC region match completed for $prefix"
}

export -f upload_to_s3
export -f download_fastq_sample
export SFTP_USER SFTP_PASS SFTP_HOST SFTP_DIR S3_PATH S3_BUCKET S3_PREFIX

export -f fuzzy_bc_region_match 
export -f fuzzy_bc_pipeline 
export -f fuzzy_bc_pipeline_read1
export -f fuzzy_bc_pipeline_read1_s3
export STATS_DIR FLASH2 PY_DIR FQ_DIR OUT_DIR S3_OUT_PATH

## PART 1: copy files from CAT to S3

    # Get the list of files and pass each to upload_to_s3
    # ---- DBGKTR09
    SFTP_DIR=/SSD/20231004_LH00132_0158_A225GLLLT3_10B_300/DBGKTR09
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/cytokine
    S3_PREFIX=tcsl_aav/ngs/illumina_30/cytokine

    export SFTP_DIR S3_PATH S3_PREFIX

    echo "Getting file list from SFTP server..."
    echo "ls" | \
        sshpass -p ${SFTP_PASS} -- \
        sftp -q -o StrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR} \
            | grep -v 'sftp>' \
            | parallel -j6 upload_to_s3

    # ---- DBGKTR10
    SFTP_DIR=/SSD/20231004_LH00132_0158_A225GLLLT3_10B_300/DBGKTR10


    echo "Getting file list from SFTP server..."
    echo "ls" | \
        sshpass -p ${SFTP_PASS} -- \
        sftp -q -o StrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR} \
            | grep -v 'sftp>' \
            | parallel -j6 upload_to_s3

    # ---- DBGKTR11
    SFTP_DIR=/SSD/20231004_LH00132_0158_A225GLLLT3_10B_300/DBGKTR11
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/repstim_repool2
    S3_PREFIX=tcsl_aav/ngs/illumina_30/repstim_repool2

    export SFTP_DIR S3_PATH S3_PREFIX


    echo "Getting file list from SFTP server..."
    echo "ls" | \
        sshpass -p ${SFTP_PASS} -- \
        sftp -q -o StrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR} \
            | grep -v 'sftp>' \
            | parallel -j5 upload_to_s3

    # ---- Undetermined samples
    SFTP_DIR=/SSD/20231004_LH00132_0158_A225GLLLT3_10B_300
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
    S3_PREFIX=tcsl_aav/ngs/illumina_30

    export SFTP_DIR S3_PATH S3_PREFIX

    echo "Getting file list from SFTP server..."
    echo "ls -lah" | \
        sshpass -p ${SFTP_PASS} -- \
        sftp -q -o StrictHostKeyChecking=no ${SFTP_USER}@${SFTP_HOST}:${SFTP_DIR} \
            | grep -v 'sftp>' | perl -pe 's/\s+/\n/g' | grep -P 'Undetermined.*L007' \
            | parallel -j2 upload_to_s3

## PART 2: additional samples that were missed in the sample list

    # "TAGGCATG+CGGAGAGA" : 26948780,
    # "TAGGCATG+ATAGAGAG" : 26676960,
    # "TAGGCATG+TATGCAGT" : 26103240,
    # "TAGGCATG+TACTCATT" : 22896760,
    # "TAGGCATG+AGAGGATA" : 21010100,
    # "TAGGCATG+ATTAGACG" : 20856280,
    # "TAGGCATG+AGGCTTAG" : 19615060,
    # "TAGGCATG+CTCCTTAC" : 16866400,

    # TCSL236_final_diff_A-A06_MN_80_s2_a_S224_L007   TAGGCATG-ATAGAGAG
    # TCSL236_final_diff_A-B06_MN_81_s2_b_S225_L007   TAGGCATG-AGAGGATA
    # TCSL236_final_diff_A-C06_MN_82_s2_c_S226_L007   TAGGCATG-CTCCTTAC
    # TCSL236_final_diff_A-D06_MN_83_s2_d_S227_L007   TAGGCATG-TATGCAGT
    # TCSL236_final_diff_A-E06_MN_84_s4_a_S228_L007   TAGGCATG-TACTCCTT
    # TCSL236_final_diff_A-F06_MN_85_s4_b_S229_L007   TAGGCATG-AGGCTTAG
    # TCSL236_final_diff_A-G06_MN_86_s4_c_S230_L007   TAGGCATG-ATTAGACG
    # TCSL236_final_diff_A-H06_MN_87_s4_d_S231_L007   TAGGCATG-CGGAGAGA

    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
    
    ~/fastq-multx-1.4.3/fastq-multx -B <( aws s3 cp $S3_PATH/missing_sample_demux.txt -) \
        <(aws s3 cp "$S3_PATH/Undetermined_S0_L007_R2_001.fastq.gz" - | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i1) = /^(\S+ \d:N:0:)([^+]+)\+/; print "$id\n$i1\n+\n", "F" x length($i1), "\n"; }') \
        <(aws s3 cp "$S3_PATH/Undetermined_S0_L007_R2_001.fastq.gz" - | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i2) = /^(\S+ \d:N:0:)[^+]+\+([^+]+)\n$/; print "$id\n$i2\n+\n" . "F" x length($i2) . "\n"; }') \
        <(aws s3 cp "$S3_PATH/Undetermined_S0_L007_R1_001.fastq.gz" - | zcat) \
        <(aws s3 cp "$S3_PATH/Undetermined_S0_L007_R2_001.fastq.gz" - | zcat) \
        -o n/a -o n/a \
        -o /large_tmp/%_R1_001.fastq.gz \
        -o /large_tmp/%_R2_001.fastq.gz

    ls  ~/tcsl236_il30_finaldiff/fq/missing/*L007* | grep -Po 'TCSL236_final_diff_.*L007.*' | parallel "aws s3 cp {} $S3_PATH/final_diff/{}"

## PART 3: fuzzy barcode matching
    mkdir -p $OUT_DIR $STATS_DIR

    # ---- DBGKTR09
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/cytokine
    S3_PREFIX=tcsl_aav/ngs/illumina_30/cytokine
    mkdir -p $OUT_DIR $STATS_DIR

    aws s3 ls $S3_PATH/ | grep -Po 'TCSL236_cytokine_.*L008' | uniq | sort \
        | parallel --jobs 4 "fuzzy_bc_region_match {} fuzzy_bc_pipeline"

    # ---- DBGKTR10
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/final_diff
    S3_PREFIX=tcsl_aav/ngs/illumina_30/final_diff
    STATS_DIR=~/tcsl236_il30_finaldiff/stats
    OUT_DIR=~/tcsl236_il30_finaldiff/out
    S3_OUT_PATH=$S3_PATH/out

    mkdir -p $OUT_DIR $STATS_DIR
    export $OUT_DIR $S3_OUT_PATH $STATS_DIR

    grep Error * | grep -Po 'TCSL236_.*_L007' | uniq | sort \
        | parallel "fuzzy_bc_region_match {} fuzzy_bc_pipeline_read1_s3"

    aws s3 ls $S3_PATH/ | parallel --dry-run --rpl '{rm_suffix} s/\.csv\.gz$//' "python3 ../tcsl236/py/merge_counts_by_bc.py {} --min-count 2 | gzip > {rm_suffix}.bc_merged.csv.gz"

    python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $OUT_DIR/*table.csv.gz | gzip - > $OUT_DIR/merged_df.csv.gz

    # ---- DBGKTR11
    S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/repstim_repool2
    S3_PREFIX=tcsl_aav/ngs/illumina_30/repstim_repool2
    STATS_DIR=~/tcsl236_il30_repstim/stats
    OUT_DIR=~/tcsl236_il30_repstim/out

    mkdir -p $OUT_DIR $STATS_DIR

    aws s3 ls $S3_PATH/ | grep -Po 'TCSL236_repstim_.*L006' | uniq | sort \
        | parallel --jobs 28 "fuzzy_bc_region_match {} fuzzy_bc_pipeline"

    ls $OUT_DIR/*.csv.gz | parallel --rpl '{rm_suffix} s/\.csv\.gz$//' "python3 ../tcsl236/py/merge_counts_by_bc.py {} --min-count 2 | gzip > {rm_suffix}.bc_merged.csv.gz"

    python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $OUT_DIR/*table.csv.gz | gzip - > $OUT_DIR/merged_df.csv.gz

 
#######
ls  ~/tcsl236/fq/missing/ | grep -Po 'TCSL236_final_diff_.*L007' | uniq | sort \
    | parallel --jobs 4 fuzzy_bc_region_match_read1

# convert umis to bc merged counts
ls out/*.csv.gz | parallel --dry-run --rpl '{rm_suffix} s/\.csv\.gz$//' "python3 ../tcsl236/py/merge_counts_by_bc.py {} --min-count 2 | gzip > {rm_suffix}.bc_merged.csv.gz"

# merge data
python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose out/*table.csv.gz | gzip - > out/merged_df.csv.gz


######
# copying unmapped data 1/2/24

echo "/tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L006_R1_001.fastq.gz 
    /tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L006_R2_001.fastq.gz 
    /tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L007_R1_001.fastq.gz 
    /tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L007_R2_001.fastq.gz 
    /tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L008_R1_001.fastq.gz
    /tortoise/20231004_LH00132_0158_A225GLLLT3_10B_300/Undetermined_S0_L008_R2_001.fastq.gz" \
    | tr -d '    ' \
    | parallel -j 6 sshpass -p 'b1gdata' scp hiseq_user@fastq.ucsf.edu:{} ~/data/ &

#copy them to s3, check and then delete
(cd ~/data/ && ls *L006* *L008*) | parallel -j 6 aws s3 cp ~/data/{} $S3_PATH/{} &

# demux additional found samples. I found weird errors with the piped approach, so will do this on disk
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30

# --------- MV L006 Undetermined, and match, then move back to S3

S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
aws s3 cp "$S3_PATH/Undetermined_S0_L006_R1_001.fastq.gz" - | tee Undetermined_S0_L006_R1_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i1) = /^(\S+ \d:N:0:)([^+]+)\+/; print "$id\n$i1\n+\n", "F" x length($i1), "\n"; }' | gzip > Undetermined_S0_L006_I1_001.fastq.gz &
aws s3 cp "$S3_PATH/Undetermined_S0_L006_R2_001.fastq.gz" - | tee Undetermined_S0_L006_R2_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i2) = /^(\S+ \d:N:0:)[^+]+\+([^+]+)\n$/; print "$id\n$i2\n+\n" . "F" x length($i2) . "\n"; }' | gzip > Undetermined_S0_L006_I2_001.fastq.gz &

~/fastq-multx-1.4.3/fastq-multx -B <( aws s3 cp $S3_PATH/missing_sample_demux_all.txt - | grep L006) \
    <(zcat Undetermined_S0_L006_R1_001.fastq.gz | perl -ne 'if($. % 4 == 1) { ($id, $i1) = /^(\S+ \d:N:0:)([^+]+)\+/; print "$id\n$i1\n+\n", "F" x length($i1), "\n"; }') \
    <(zcat Undetermined_S0_L006_R2_001.fastq.gz | perl -ne 'if($. % 4 == 1) { ($id, $i2) = /^(\S+ \d:N:0:)[^+]+\+([^+]+)\n$/; print "$id\n$i2\n+\n" . "F" x length($i2) . "\n"; }') \
    Undetermined_S0_L006_R1_001.fastq.gz \
    Undetermined_S0_L006_R2_001.fastq.gz \
    -o n/a -o n/a \
    -o ~/data/%_R1_001.fastq.gz \
    -o ~/data/%_R2_001.fastq.gz

rm ~/data/Undetermined_*L006*.fastq.gz
rm ~/data/unmatched*L006*.fastq.gz

ls *L006* | parallel aws s3 cp ~/data/{} $S3_PATH/repstim_repool2/missing/{} &

# --------- MV L008 Undetermined, and match, then move back to S3

S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
aws s3 cp "$S3_PATH/Undetermined_S0_L008_R1_001.fastq.gz" - | tee Undetermined_S0_L008_R1_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i1) = /^(\S+ \d:N:0:)([^+]+)\+/; print "$id\n$i1\n+\n", "F" x length($i1), "\n"; }' | gzip > Undetermined_S0_L008_I1_001.fastq.gz &
aws s3 cp "$S3_PATH/Undetermined_S0_L008_R2_001.fastq.gz" - | tee Undetermined_S0_L008_R2_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i2) = /^(\S+ \d:N:0:)[^+]+\+([^+]+)\n$/; print "$id\n$i2\n+\n" . "F" x length($i2) . "\n"; }' | gzip > Undetermined_S0_L008_I2_001.fastq.gz &

~/fastq-multx-1.4.3/fastq-multx -B <( aws s3 cp $S3_PATH/missing_sample_demux_all.txt - | grep L008) \
    Undetermined_S0_L008_I1_001.fastq.gz \
    Undetermined_S0_L008_I2_001.fastq.gz \
    Undetermined_S0_L008_R1_001.fastq.gz \
    Undetermined_S0_L008_R2_001.fastq.gz \
    -o n/a -o n/a \
    -o ~/data/%_R1_001.fastq.gz \
    -o ~/data/%_R2_001.fastq.gz

# Missing C08 and F09 - need to retry - keep getting corrupted zip files

rm ~/data/Undetermined_*L008*.fastq.gz
rm ~/data/unmatched*L008*.fastq.gz

ls *L008* | parallel aws s3 cp ~/data/{} $S3_PATH/cytokine/missing/{} &

# --------- MV L007 Undetermined, and match, then move back to S3

S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
aws s3 cp "$S3_PATH/Undetermined_S0_L007_R1_001.fastq.gz" - | tee Undetermined_S0_L007_R1_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i1) = /^(\S+ \d:N:0:)([^+]+)\+/; print "$id\n$i1\n+\n", "F" x length($i1), "\n"; }' | gzip > Undetermined_S0_L007_I1_001.fastq.gz &
aws s3 cp "$S3_PATH/Undetermined_S0_L007_R2_001.fastq.gz" - | tee Undetermined_S0_L007_R2_001.fastq.gz | zcat | perl -ne 'if($. % 4 == 1) { ($id, $i2) = /^(\S+ \d:N:0:)[^+]+\+([^+]+)\n$/; print "$id\n$i2\n+\n" . "F" x length($i2) . "\n"; }' | gzip > Undetermined_S0_L007_I2_001.fastq.gz &

~/fastq-multx-1.4.3/fastq-multx -B <( aws s3 cp $S3_PATH/missing_sample_demux_all.txt - | grep L007) \
    Undetermined_S0_L007_I1_001.fastq.gz \
    Undetermined_S0_L007_I2_001.fastq.gz \
    Undetermined_S0_L007_R1_001.fastq.gz \
    Undetermined_S0_L007_R2_001.fastq.gz \
    -o n/a -o n/a \
    -o ~/data/%_R1_001.fastq.gz \
    -o ~/data/%_R2_001.fastq.gz

rm ~/data/Undetermined_*L007*.fastq.gz
rm ~/data/unmatched*L007*.fastq.gz

ls *L007* | parallel aws s3 cp ~/data/{} $S3_PATH/final_diff/missing/{} &

# ---- L006 DBGKTR11 bc fuzzy region match
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/repstim_repool2/missing
S3_PREFIX=tcsl_aav/ngs/illumina_30/repstim_repool2/missing
STATS_DIR=~/data/tcsl236_il30_repstim/stats
OUT_DIR=~/data/tcsl236_il30_repstim/out

mkdir -p $OUT_DIR $STATS_DIR

TMP_DIR= ~/data
export OUT_DIR S3_OUT_PATH S3_PREFIX STATS_DIR TMP_DIR

aws s3 ls $S3_PATH/ | grep -Po 'TCSL236_repstim_.*L006' | uniq | sort \
    | parallel --jobs 28 "fuzzy_bc_region_match {} fuzzy_bc_pipeline"

ls $OUT_DIR/*.csv.gz | parallel --rpl '{rm_suffix} s/\.csv\.gz$//' "python3 ../tcsl236/py/merge_counts_by_bc.py {} --min-count 1 | gzip > {rm_suffix}.bc_merged.csv.gz"

python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $OUT_DIR/*table.csv.gz | gzip - > $OUT_DIR/merged_df.csv.gz

# ---- L008 DBGKTR09 bc fuzzy region match
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/cytokine/missing
S3_PREFIX=tcsl_aav/ngs/illumina_30/cytokine/missing
STATS_DIR=~/data/tcsl236_il30_cyto/stats
OUT_DIR=~/data/tcsl236_il30_cyto/out

mkdir -p $OUT_DIR $STATS_DIR

TMP_DIR= ~/data
export OUT_DIR S3_OUT_PATH S3_PREFIX STATS_DIR TMP_DIR

aws s3 ls $S3_PATH/ | grep -Po 'TCSL236_*_.*L008' | uniq | sort \
    | parallel --jobs 28 "fuzzy_bc_region_match {} fuzzy_bc_pipeline"

ls $OUT_DIR/*.csv.gz | parallel --rpl '{rm_suffix} s/\.csv\.gz$//' "python3 ../tcsl236/py/merge_counts_by_bc.py {} --min-count 1 | gzip > {rm_suffix}.bc_merged.csv.gz"

python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $OUT_DIR/*table.csv.gz | gzip - > $OUT_DIR/merged_df.csv.gz

# ---- L007 DBGKTR10 bc fuzzy region match
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30/final_diff/missing
S3_PREFIX=tcsl_aav/ngs/illumina_30/final_diff/missing
STATS_DIR=~/data/tcsl236_il30_finaldiff/stats
OUT_DIR=~/data/tcsl236_il30_finaldiff/out

mkdir -p $OUT_DIR $STATS_DIR

TMP_DIR= ~/data
export OUT_DIR S3_OUT_PATH S3_PREFIX STATS_DIR TMP_DIR

aws s3 ls $S3_PATH/ | grep -Po 'TCSL236_*_.*L007' | uniq | sort \
    | parallel --jobs 28 "fuzzy_bc_region_match {} fuzzy_bc_pipeline_read1_s3"

## merge all

FINALDIFF_DIR=~/data/tcsl236_il30_finaldiff/out
CYTOKINE_DIR=~/data/tcsl236_il30_cyto/out
REPSTIM_DIR=~/data/tcsl236_il30_repstim/out

python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $FINALDIFF_DIR/*table.csv.gz | gzip - > $FINALDIFF_DIR/merged_df.csv.gz &
python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $CYTOKINE_DIR/*table.csv.gz | gzip - > $CYTOKINE_DIR/merged_df.csv.gz &
python3 ~/tcsl236/py/merge_bc_dfs.py --min-merge-count 1 --verbose $REPSTIM_DIR/*table.csv.gz | gzip - > $REPSTIM_DIR/merged_df.csv.gz &


##########

# Ok, new task. Using bash, I'd like to do the following:

# 1.  Get paths on S3 to all files within a certain directory either ending in `_bc_table.csv.gz` or called merged_df.csv.gz. They can be multiple levels deep from the starting directory.
# 2. Copy via aws s3 cp all of these files to a local disk location, preserving the directory structure.
# 3. Ideally, do this with GNU parallel.

#!/bin/bash

# Define S3 bucket and directory
S3_PATH=s3://roybal-tcsl/tcsl_aav/ngs/illumina_30
LOCAL_DIR=/Users/dbg/Library/CloudStorage/Box-Box/tcsl/ngs_data/2023.09.28.illumina_30/out

# Function to copy a file from S3 to local directory
copy_file() {
    file_path=$1
    # Create the necessary local directory structure
    file_dir=$(dirname "${LOCAL_DIR}/${file_path}")
    mkdir -p "${file_dir}"
    # Then copy the file from S3 to the local directory
    echo "Copying ${S3_PATH}/${file_path} to ${LOCAL_DIR}/${file_path}"
    aws s3 cp ${S3_PATH}/${file_path} "${LOCAL_DIR}/${file_path}"
}

export -f copy_file
export S3_PATH
export LOCAL_DIR

# List, filter, and copy files using GNU parallel
aws s3 ls $S3_PATH --recursive | \
    awk '{print $4}' | \
    grep -E "(_bc_table.csv.gz|merged_df.csv.gz)$" | \
    perl -pe 's/.*illumina_30\///' | \
    parallel -j 8 copy_file {}

### local run of merge_bc_dfs across all samples

source ~/pyenvs/tcsl/bin/activate

PY_DIR=/Users/dbg/Library/CloudStorage/Box-Box/tcsl/ngs_data/2023.09.12.illumina_28/py
IL30_DIR=/Users/dbg/Library/CloudStorage/Box-Box/tcsl/ngs_data/2023.09.28.illumina_30
FINAL_DIFF_DIR=${IL30_DIR}/out/final_diff/out

python3 $PY_DIR/merge_bc_dfs.py --min-merge-count 1 --verbose ${FINAL_DIFF_DIR}/*table.csv.gz \
    | gzip - > \
    $FINAL_DIFF_DIR/merged_df.csv.gz &


