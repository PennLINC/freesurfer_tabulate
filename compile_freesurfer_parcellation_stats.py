"""Compile FreeSurfer stats files."""
import os
import sys
import pandas as pd
import numpy as np

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
            gwpct_df_ = statsfile_to_df(gwpct_file, hemi, atlas, column_suffix="_wgpct")
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

    def sanity_check_columns(reference_column, redundant_column, atol=0):
        if not np.allclose(
            out_df[reference_column].astype(np.float32),
            out_df[redundant_column].astype(np.float32), atol=atol):
            raise Exception(f"The {reference_column} values were not identical to {redundant_column}")
        out_df.drop(redundant_column, axis=1, inplace=True)

    # Do some sanity checks and remove redundant columns
    sanity_check_columns("NumVert", "NVertices_wgpct", 0)
    sanity_check_columns("NumVert", "NVertices_piallgi", 0)
    sanity_check_columns("SurfArea", "Area_mm2_piallgi", 1)
    sanity_check_columns("SurfArea", "Area_mm2_wgpct", 1)

    out_df.to_csv(f"{subjects_dir}/{subject_id}/{subject_id}_regionsurfacestats.tsv", sep="\t", index=False)
