import sys
import pandas as pd
import concurrent.futures
import argparse

HEADER_COLS = ['itam_bc_o', 'itam_umi_o', 'costim_bc_o', 'costim_umi_o', 'sl_num']

get_df_name = lambda df_i: '|'.join(set(df_i.columns) - set(HEADER_COLS))

def merge_dataframes(pair):
    """
    Merge two dataframes based on common columns.

    Args:
        pair (tuple): A tuple containing two dataframes.

    Returns:
        pd.DataFrame: The merged dataframe.
    """
    df1, df2 = pair

    # Get the names of the dataframes
    df1_name = get_df_name(df1)
    df2_name = get_df_name(df2)

    if args.verbose:
        print(f"Merging: {df1_name} & {df2_name}", file=sys.stderr)

    merged_df = pd.merge(df1, df2, on=HEADER_COLS, how='outer')

    if args.verbose:
        print(f"Done: {df1_name} & {df2_name}", file=sys.stderr)
        print(f"New DF: {get_df_name(merged_df)}", file=sys.stderr)

    return merged_df

def reduce_dataframes(dfs):
    """
    Reduce a list of dataframes by merging them iteratively.

    Args:
        dfs (list): A list of dataframes.

    Returns:
        pd.DataFrame: The final merged dataframe.
    """
    paired_dfs = list(zip(dfs[::2], dfs[1::2]))  # Pair up the initial dataframes
    round_num = 0
    odd_dfs = []

    if len(dfs) % 2 == 1:
        odd_dfs.append(dfs[-1])

    while True:
        if args.verbose:
            print(f"Currently: {len(paired_dfs)} pairs of dataframes.", file=sys.stderr)

        merged_dfs = []

        # Create a ThreadPoolExecutor
        with concurrent.futures.ThreadPoolExecutor() as executor:
            # Pair up the dataframes and merge them
            merged_dfs = list(executor.map(merge_dataframes, paired_dfs))

        # if there is a leftover df, add it to merged_dfs
        if len(odd_dfs) > 0:
            merged_dfs.append(odd_dfs.pop())

        if args.verbose:
            print(f"Merged DFs: {len(merged_dfs)}", file=sys.stderr)
            print(f"Round {round_num} done: {len(merged_dfs)} merged dataframes:", file=sys.stderr)
            for i, df_i in enumerate(merged_dfs):
                print(f"{i}:\t{get_df_name(df_i)}\t{df_i.shape[0]}", file=sys.stderr)

        paired_dfs = list(zip(merged_dfs[::2], merged_dfs[1::2]))  # Update the paired dataframes

        if len(merged_dfs) == 1:
            break

        # if there is an odd df after pairing, then pop and save it
        if len(merged_dfs) % 2 == 1:
            odd_dfs.append(merged_dfs.pop())

        else:
            round_num += 1

    return merged_dfs[0]

def load_csv_file(file_name):
    if args.verbose:
        print(f"Loading: {file_name}", file=sys.stderr)

    df = pd.read_csv(file_name)
    df = df.drop('sl_o', axis=1)

    # After dropping sl_o, group by all columns except 'count',
    # and aggregate by summing the values in 'count'
    df = df.groupby(HEADER_COLS).agg({'count': 'sum'}).reset_index()

    count_col = 'TCSL234rs_' + str(file_name)
    df = df.rename(columns={'count': count_col})

    # Convert DNA cols from object to string data type
    object_cols = df.select_dtypes(include='object').columns
    df[object_cols] = df[object_cols].astype('string[pyarrow]')

    return df


def main(file_names, min_merge_count):
    """
    Main function to process the files and generate the merged dataframe.

    Args:
        file_names (list): A list of file names to process.
        min_merge_count (int): The minimum merge count threshold.

    Returns:
        pd.DataFrame: The merged dataframe.
    """
    # List to store the DataFrames for each file
    dfs = []

    # Load each file into a DataFrame and rename the 'count' column
    with concurrent.futures.ThreadPoolExecutor() as executor:
        dfs = list(executor.map(load_csv_file, file_names))

    merged_df = reduce_dataframes(dfs)

    count_cols = list(set(merged_df.columns) - set(HEADER_COLS))

    # Replace NaN values in count columns with 0
    merged_df = merged_df.fillna(value={i: 0 for i in count_cols})

    # Convert count columns to integers
    merged_df[count_cols] = merged_df[count_cols].astype(int)

    # Create a new column 'total' representing the sum of all count columns
    merged_df['total'] = merged_df.loc[:, count_cols].sum(axis=1)
    merged_df = merged_df.sort_values(by='total', ascending=False)

    # Create a new column 'n_samples' representing the number of non-zero count rows
    merged_df['n_samples'] = (merged_df[count_cols] > 0).sum(axis=1)

    merged_df = merged_df.sort_values(by='total', ascending=False)

    return merged_df

if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Merge and process dataframes")
    parser.add_argument("file_names", nargs='+', type=str, help="List of file names to process")
    parser.add_argument("--min-merge-count", type=int, default=5, help="Minimum merge count threshold")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose/debug mode")
    args = parser.parse_args()

    merged_df = main(args.file_names, args.min_merge_count)
    merged_df.to_csv(sys.stdout, index=False)
