from pathlib import Path
from collections import defaultdict
import pandas as pd
from tqdm import tqdm
dataframes = []

print("Gathering brainstats...")
for tsv in Path('./freesurfer').rglob("*brainmeasures.tsv"):
    dataframes.append(pd.read_csv(tsv, sep="\t"))
group_brainmeasures = pd.concat(dataframes, ignore_index=True, axis=0)
group_brainmeasures.to_parquet("group_brainmeasures.parquet")

annot_dir = Path("./freesurfer_tabulate/annots")
atlas_names = [
    annot.name.replace("rh.", "").replace(".annot", "")  for
    annot in annot_dir.rglob("rh*annot")]
print("Gathering parcellation stats for %d atlases" % len(atlas_names))


region_stats_files = list(Path('./freesurfer').rglob("*regionsurfacestats.tsv"))
parcel_dfs = defaultdict(list)
for tsv in tqdm(region_stats_files):
    _parcel_df = pd.read_csv(tsv, sep="\t")
    for atlasname in atlas_names:
        parcel_dfs[atlasname].append(_parcel_df[_parcel_df["atlas"] == atlasname])

for atlasname in atlas_names:
    atlas_df = pd.concat(parcel_dfs[atlasname], ignore_index=True, axis=0)
    print(atlasname + "saved with shape " + str(atlas_df.shape))
    atlas_df.to_parquet(atlasname + "_surfacestats.parquet")
