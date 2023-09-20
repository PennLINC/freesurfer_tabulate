"""Compile FreeSurfer stats files."""
import os
import sys
import pandas as pd

hemispheres = ["lh", "rh"]
NOSUFFIX_COLS = ["Index", "SegId", "StructName"]

def statsfile_to_df(stats_fname, hemi, atlas, column_suffix=""):
    with open(stats_fname, "r") as fo:
        data = fo.readlines()

    idx = [i for i, l in enumerate(data) if l.startswith("# ColHeaders ")]
    assert len(idx) == 1
    idx = idx[0]

    columns_row = data[idx]
    actual_data = data[idx + 1:]
    actual_data = [line.split() for line in actual_data]
    columns = columns_row.replace("# ColHeaders ", "").split()

    df = pd.DataFrame(columns=[col + column_suffix
                               if not col in NOSUFFIX_COLS
                               else col for col in columns],
                      data=actual_data)
    df.insert(0, "hemisphere", hemi)
    df.insert(0, "atlas", atlas)
    return df

subjects_dir = os.getenv("SUBJECTS_DIR")
if __name__ == "__main__":
    subject_id = sys.argv[1]
    atlases = sys.argv[2:]
    print(f"Summarizing regional stats for {len(atlases)} atlases")
    in_dir = os.path.join(subjects_dir, subject_id)
    stats_dir = os.path.join(in_dir, "stats")
    surfstat_dfs = []
    for atlas in atlases:
        print(atlas)
        for hemi in hemispheres:
            print(f"   {hemi}")

            # Get the surface statistics
            surfstats_file = os.path.join(stats_dir, f"{hemi}.{atlas}.stats")
            surfstat_df_ = statsfile_to_df(surfstats_file, hemi, atlas)

            # get the g-w.pct files
            gwpct_file = os.path.join(stats_dir, f"{hemi}.{atlas}.w-g.pct.stats")
            gwpct_df_ = statsfile_to_df(gwpct_file, hemi, atlas, column_suffix="_gwpct")
            surf_and_gwpct = pd.merge(surfstat_df_, gwpct_df_)

            # get the g-w.pct files
            lgi_file = os.path.join(stats_dir, f"{hemi}.{atlas}.pial_lgi.stats")
            lgi_df_ = statsfile_to_df(lgi_file, hemi, atlas, column_suffix="_piallgi")
            surfstat_dfs.append(pd.merge(surf_and_gwpct, lgi_df_))

    # The freesurfer directory may contain subject and session. check here
    session_id = None
    if "_" in subject_id:
        subject_id, session_id = subject_id.split("_")
    out_df = pd.concat(surfstat_dfs, axis=0, ignore_index=True)
    out_df.insert(0, "session_id", session_id)
    out_df.insert(0, "subject_id", subject_id)
    out_df.to_csv(f"{subjects_dir}/{subject_id}/{subject_id}_surfacestats.tsv", sep="\t", index=False)
