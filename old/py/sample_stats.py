import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.backends.backend_pdf import PdfPages
import sys

def parse_file(file_path):
    with open(file_path, 'r') as file:
        content = file.readlines()

    filenames = []
    stats = []
    current_stats = {}

    for line in content:
        if "_L001" in line:
            if current_stats:
                stats.append(current_stats)
                current_stats = {}
            filenames.append(line.strip())
        elif "unprocessed_count" in line:
            current_stats["unprocessed_count"] = int(line.split("\t")[1])
        elif "%" in line:
            parts = line.split()
            desc = parts[0]
            count = int(parts[1])
            percentage = float(parts[2].replace("%", ""))
            current_stats[desc + "_count"] = count
            current_stats[desc + "_percentage"] = percentage

    if current_stats:
        stats.append(current_stats)

    df = pd.DataFrame(stats)
    df.insert(0, "filename", filenames)
    df['set'] = df['filename'].str.extract(r'set-([A-Z])-', expand=False)
    df['well_row'] = df['filename'].str.extract(r'([A-H])\d{2}_', expand=False)
    df['well_column'] = df['filename'].str.extract(r'[A-H](\d{2})_', expand=False)
    df['well'] = df['well_row'] + df['well_column']
    df["unmatched_percentage"] = (1 - (df["matched_counts_count"] / df["unprocessed_count"])) * 100

    return df

def create_plots(df, output_pdf):
    sets_order = ["A", "B", "C", "D"]
    metrics = [
        ('unprocessed_count', 'PuBu', 'Unprocessed Reads', True),
        ('matched_counts_count', 'PuBuGn', 'Matched Reads', True),
        ('unmatched_percentage', 'Reds', 'Unmatched Percentage (%)', False)
    ]

    with PdfPages(output_pdf) as pdf_pages:
        for metric, cmap, title_suffix, use_log_scale in metrics:
            fig, axes = plt.subplots(2, 2, figsize=(30, 24))
            fig.suptitle(title_suffix, fontsize=32)

            for idx, s in enumerate(sets_order):
                ax = axes[idx//2, idx%2]
                subset_df = df[df['set'] == s]
                pivot_table = subset_df.pivot(index='well_row', columns='well_column', values=metric)
                pivot_table = pivot_table.reindex(index=pivot_table.index[::-1])  # Rearrange rows to start with A

                if use_log_scale:
                    sns.heatmap(np.log10(pivot_table + 1), cmap=cmap, annot=pivot_table, fmt=".0f", linewidths=.5, cbar_kws={'label': title_suffix}, ax=ax)
                else:
                    sns.heatmap(pivot_table, cmap=cmap, annot=pivot_table, fmt=".2f", linewidths=.5, cbar_kws={'label': title_suffix}, ax=ax)

                ax.set_title(f"Set {s}", fontsize=24)
                ax.set_xlabel("Well Column", fontsize=20)
                ax.set_ylabel("Well Row", fontsize=20)
                ax.tick_params(labelsize=18)
                ax.set_yticklabels(ax.get_yticklabels(), rotation=0)
                ax.set_xticklabels(ax.get_xticklabels(), rotation=0)

            plt.tight_layout()
            pdf_pages.savefig(fig)
            plt.close(fig)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input_file_path> <output_csv_path>")
        sys.exit(1)

    input_file_path = sys.argv[1]
    output_csv_path = sys.argv[2]
    output_pdf_path = output_csv_path.replace('.csv', '.pdf')

    df = parse_file(input_file_path)
    df.to_csv(output_csv_path, index=False)
    create_plots(df, output_pdf_path)
