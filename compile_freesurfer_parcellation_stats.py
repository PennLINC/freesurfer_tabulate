"""Compile FreeSurfer stats files."""
import os
import sys
import pandas as pd

hemispheres = ["lh", "rh"]
atlases = [
    "aparc.a2009s",
    "aparc.DKTatlas",
    "aparc.pial",
    "aparc",
    "BA_exvivo",
    "BA_exvivo.thresh",
    "AAL",
    "CC200",
    "CC400",
    "glasser",
    "gordon333dil"
    "HOCPATh25",
    "Juelich",
    "PALS_B12_Brodmann",
    "Schaefer2018_1000Parcels_17Networks_order",
    "Schaefer2018_1000Parcels_7Networks_order",
    "Schaefer2018_100Parcels_17Networks_order",
    "Schaefer2018_100Parcels_7Networks_order",
    "Schaefer2018_200Parcels_17Networks_order",
    "Schaefer2018_200Parcels_7Networks_order",
    "Schaefer2018_300Parcels_17Networks_order",
    "Schaefer2018_300Parcels_7Networks_order",
    "Schaefer2018_400Parcels_17Networks_order",
    "Schaefer2018_400Parcels_7Networks_order",
    "Schaefer2018_500Parcels_17Networks_order",
    "Schaefer2018_500Parcels_7Networks_order",
    "Schaefer2018_600Parcels_17Networks_order",
    "Schaefer2018_600Parcels_7Networks_order",
    "Schaefer2018_700Parcels_17Networks_order",
    "Schaefer2018_700Parcels_7Networks_order",
    "Schaefer2018_800Parcels_17Networks_order",
    "Schaefer2018_800Parcels_7Networks_order",
    "Schaefer2018_900Parcels_17Networks_order",
    "Schaefer2018_900Parcels_7Networks_order",
    "Slab",
    "Yeo2011_17Networks_N1000",
    "Yeo2011_7Networks_N1000"]

subjects_dir = os.getenv("SUBJECTS_DIR")
if __name__ == "__main__":
    subject_id = sys.argv[1]
    in_dir = os.path.join(subjects_dir, subject_id)
    stats_dir = os.path.join(in_dir, "stats")
    dfs = []
    for hemi in hemispheres:
        for atlas in atlases:
            stats_file = os.path.join(stats_dir, f"{hemi}.{atlas}.stats")
            with open(stats_file, "r") as fo:
                data = fo.readlines()

            idx = [i for i, l in enumerate(data) if l.startswith("# ColHeaders ")]
            assert len(idx) == 1
            idx = idx[0]

            columns_row = data[idx]
            actual_data = data[idx + 1:]
            actual_data = [line.split() for line in actual_data]
            columns = columns_row.replace("# ColHeaders ", "").split()

            df = pd.DataFrame(columns=columns, data=actual_data)
            df.insert(0, "hemisphere", hemi)
            df.insert(0, "atlas", atlas)
            dfs.append(df)

    out_df = pd.concat(dfs, axis=0)
    out_df.to_csv(f"{subjects_dir}/${subject_id}/{subject_id}_surfacestats.tsv", sep="\t", index=False)
