
import pandas as pd
import argparse
import gzip
import sys

def process_gzipped_csv(file_path, min_count):
    # Read the gzipped CSV into a DataFrame
    df = pd.read_csv(file_path, compression='gzip')
    
    # Group by 'costim_bc_o' and 'sl_num' and sum the 'count' column
    grouped_df = df.groupby(['costim_bc_o', 'sl_num'])['count'].sum().reset_index()
    
    # Filter rows based on the min_count
    grouped_df = grouped_df[grouped_df['count'] >= min_count]
    
    # Write result to stdout as CSV
    grouped_df.to_csv(sys.stdout, index=False)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process a gzipped CSV and group by columns.')
    parser.add_argument('file_path', type=str, help='Path to the gzipped CSV file.')
    parser.add_argument('--min-count', type=int, default=0, help='Minimum count for inclusion in the output.')
    
    args = parser.parse_args()
    
    process_gzipped_csv(args.file_path, args.min_count)
