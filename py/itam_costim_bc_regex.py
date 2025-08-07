import regex
import gzip
import sys
import pandas as pd
from collections import defaultdict


#CGATGTTGAAGAAAACCCAGGTCCT GGC TCA GGA TCG GGT TCA GGT TCT GGGCCT TCAGGTAGT CGTGACGTCGGGAGT AGTTCGATGAGTTTG TCGGCTGCTTTA
#CGATGTTGAAGAAAACCCGTGTCCT G C TCT GGA TCC GGG TCT GGT TCT GGGCCT GAATCCAGC GGCGGAAGTCCTCGT GCCCATCACGGCCAT TCGGCTGCTTTA
#        AACCAGGTCCTGGATAA TGA TCC GGA TCA TGA TCCTGG CCTCCATCACTCTTGGCTTGGAGAGCGCGTAAAAGCTGTGGTTCGGCTGCTTTA
#       AACCAGGTCCTGGATCAGGATCAGGGTGTGGCTCCGTTCCTGTAAACTCGTTGGCTGTGAGAGCGAGTTCCAATAGTGTCTCGGCTGCTATA
TEST_STR = "2543 CGATACTGAAGAAAACCCAGGTCCT GGG TCT GGT TCA GGG TCC GGT TCC GGGCCT TCAGGTAGT CGTGACGTCGGGAGTATGTTTAAGTCGAATTCGGCTGCTTTA"

SL_SEQS = [('90',"GGTTCT"), ('30',"GCGCCACTGCACCTA"), ('31','TTGGCTGGGAGAGCG'), ('34','CCACGGCCTGGAACA'), ('60',"CGTGACGTCGGGAGT"), ('63',"GGCGGAAGTCCTCGT")]
NAMED_SL_SEQS = ['>'.join((str(i[0]), i[1])) for i in SL_SEQS]
MAX_MATCH_DIST = 8
MIN_COUNT = 1
MAX_SEQS = float('inf')

# for primordium reads, keep the original bc region - do not deduplicate or aggregate counts
KEEP_BC = False

def compile_bc_regex():

    pre_str = "ACCCAGGTCCT"
    itam_bc = "GG.TC.GG."
    itam_umi = "TC.GG.TC.GG.TC."
    jct_str = "GGGCCT"
    post_str = "TCGGCTGCTTTA"
    costim_bc = "[ATGCN]{9}"
    costim_umi = "[ATGCN]{15}"
    sl_str_set = (
        '((?P<sublibrary_' +
        ')|(?P<sublibrary_'.join(NAMED_SL_SEQS) + '))'
    )
    max_fuzzy_str = f"{{e<={MAX_MATCH_DIST}}}"

    bc_regex_compiled = regex.compile(
        fr"({pre_str}(?P<itam_bc_o>{itam_bc})" +
        fr"(?P<itam_umi_o>{itam_umi})" + 
        fr"{jct_str}(?P<costim_bc_o>{costim_bc})" +
        fr"{sl_str_set}(?P<costim_umi_o>{costim_umi})" +
        fr"{post_str}){max_fuzzy_str}")
    
    return(bc_regex_compiled)


def process_bc_seq_line(bc_regex_compiled, seq_str, line_count):

    bc_regex_match = bc_regex_compiled.match(seq_str)
    
    if bc_regex_match == None:
        return None
    else:
        match_dict = bc_regex_match.groupdict()

    # compress sublibrary keys into number and count
    sublibrary_keys = [key for key in match_dict.keys() if key.startswith('sublibrary_')]
    sublibrary_key = next(key for key in sublibrary_keys if match_dict[key] is not None)
    sublibrary_value = sublibrary_key.split('_')[-1]
    sublibrary_string = match_dict[sublibrary_key]

    for key in sublibrary_keys:
        del match_dict[key]

    match_dict['sl_o'] = sublibrary_string
    match_dict['sl_num'] = int(sublibrary_value)
    
    # add line count
    match_dict['count'] = int(line_count)
    
    return(match_dict)

def main(input_path):
    
    # compile bc regex
    bc_regex_compiled = compile_bc_regex()
    
    # check if input is a file or stdin
    if input_path == '-':
        # stdin
        if sys.stdin.isatty():
            print('Error: No input detected on stdin', file=sys.stderr)
            sys.exit(1)
        else:
            bc_file = sys.stdin
    else:
        # file
        # try opening as gzip first
        try:
            bc_file = gzip.open(input_path, 'rt')
            bc_file.peek(1) # This is a hacky way to trigger the error on non-gzip files
        except OSError:
            # if not a gzip file, open as regular file
            bc_file = open(input_path, 'rt')

    # Initialize an empty list to store the dictionaries
    bc_table_list = []
    stats = defaultdict(int)
    no_counts = None

    # Process each line using the provided function
    for line in bc_file:

        line_parts = line.split()
        
        # check if raw seqs instead of counts
        if len(line_parts) == 1:

            if no_counts != True:
                print('Warning: input appears to be seqs only instead of unique counts.\n' + \
                    'We will assume each seq is 1 count.', file=sys.stderr)

            line_count = 1
            no_counts = True
            seq_str = line_parts[0]
        else:
            # grab bc count, even if no regex match
            line_count = int(line_parts[0])
            seq_str = line_parts[1]
            no_counts = False
        
        stats['total_lines'] += 1
        stats['total_counts'] += line_count

        if line_count < MIN_COUNT:
            stats['skipped_lines'] += 1
            stats['skipped_counts'] += line_count
            continue
        
        match_dict = process_bc_seq_line(bc_regex_compiled, seq_str, line_count)
        
        if match_dict is None:
            #print(f"No match for:{line}")
            match_dict = {key:None for key in bc_regex_compiled.groupindex.keys()}
            match_dict['count'] = line_count

            stats['unmatched_lines'] += 1
            stats['unmatched_counts'] += line_count
        else:
            stats['matched_lines'] += 1
            stats['matched_counts'] += line_count

        if KEEP_BC:
            match_dict['bc_region'] = seq_str

        bc_table_list.append(match_dict)

        if stats['total_lines'] > MAX_SEQS: break

    # Create a DataFrame from the list of dictionaries
    df = pd.DataFrame(bc_table_list)

    # Reorder the columns based on the header
    header = ['count', 'itam_bc_o', 'itam_umi_o', 'costim_bc_o', 'costim_umi_o', 'sl_o', 'sl_num']

    if KEEP_BC:
            header.append('bc_region')

    # Group by all columns except 'count', and aggregate by summing the values in 'count'
    # Do not do this if keeping original barcode sequence regions
    if not KEEP_BC:
        df = df.groupby(header[1:]).agg({'count': 'sum'}).reset_index()
        # Sort the DataFrame by the 'count' column in descending order
        df = df.sort_values('count', ascending=False)

    df = df[header]

    stats['merged_lines'] = df.shape[0]

    # Export the DataFrame to a CSV file
    df.to_csv(sys.stdout, index=False)

    # Print stats to stderr
    print(f"Processing of {input_path} completed.", file=sys.stderr)

    # Find the maximum width of the keys for left justification
    max_key_width = max(len(key) for key in stats.keys())

    # Print each key/value pair
    for key, value in stats.items():

        # Calculate the percentage
        if 'lines' in key:
            percentage = (value / stats['total_lines']) * 100
        else:
            percentage = (value / stats['total_counts']) * 100

        # Format the output with left and right justification
        output = '{:<{}}{:>10}{:>15.2f}%'.format(key, max_key_width, value, percentage)
        print(output, file=sys.stderr)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 itam_costim_bc_regex.py <input_path>")
        sys.exit(1)

    input_path = sys.argv[1]
    main(input_path)