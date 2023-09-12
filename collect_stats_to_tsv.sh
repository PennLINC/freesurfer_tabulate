#!/bin/bash

# A script that will calculate surface metrics for many atlases
# and will grab subject metadata. Creates tsv and json files
# of the results

# USAGE:
# collect_stats_to_tsv.sh subject_id freesurfer_dir fmriprep.sif
#
#
# subject_id:     The subject identifier. Must start with sub-. Could
#                 also be sub-X_ses-Y. This is the subject ID as it
#                 would be used for --s in most FreeSurfer programs
#
# freesurfer_dir: The directory that would be SUBJECTS_DIR if you
#                 were to run this outside of a container. There
#                 must exist a ${freesurfer_dir}/${subject_id}
#                 directory containing surf/ label/, etc.
#
# fmriprep.sif:   Full path to the singularity/apptainer SIF file
#                 containing the fmriprep used to create the
#                 freesurfer data. Maybe a regular freesurfer sif
#                 would work, but I haven't tested it

#get input for this run
subject_id=$1
fs_root=$2
fmriprep_sif=$3
export SUBJECTS_DIR=${fs_root}
subject_fs=${SUBJECTS_DIR}/${subject_id}

# Local data
SCRIPT_DIR=$(basedir $0)
annots_dir=${SCRIPT_DIR}/annots
combine_script=${SCRIPT_DIR}/compile_freesurfer_stats.py

workdir=${subject_fs}
export APPTAINERENV_OMP_NUM_THREADS=1
export APPTAINERENV_NSLOTS=1
export APPTAINERENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
export APPTAINERENV_SUBJECTS_DIR=${SUBJECTS_DIR}
export APPTAINER_TMPDIR=${SINGULARITY_TMPDIR}
singularity_cmd="singularity exec --containall --writable-tmpfs -B ${SUBJECTS_DIR} -B ${annots_dir} -B ${FREESURFER_HOME}/license.txt:/opt/freesurfer/license.txt ${fmriprep_sif}"

# Special atlases that we need to warp from fsaverage to native
parcs="AAL CC200 CC400 glasser gordon333dil HOCPATh25 Juelich PALS_B12_Brodmann Schaefer2018_1000Parcels_17Networks_order Schaefer2018_1000Parcels_7Networks_order Schaefer2018_100Parcels_17Networks_order Schaefer2018_100Parcels_7Networks_order Schaefer2018_200Parcels_17Networks_order Schaefer2018_200Parcels_7Networks_order Schaefer2018_300Parcels_17Networks_order Schaefer2018_300Parcels_7Networks_order Schaefer2018_400Parcels_17Networks_order Schaefer2018_400Parcels_7Networks_order Schaefer2018_500Parcels_17Networks_order Schaefer2018_500Parcels_7Networks_order Schaefer2018_600Parcels_17Networks_order Schaefer2018_600Parcels_7Networks_order Schaefer2018_700Parcels_17Networks_order Schaefer2018_700Parcels_7Networks_order Schaefer2018_800Parcels_17Networks_order Schaefer2018_800Parcels_7Networks_order Schaefer2018_900Parcels_17Networks_order Schaefer2018_900Parcels_7Networks_order Slab Yeo2011_17Networks_N1000 Yeo2011_7Networks_N1000"

# Atlases that come from freesurfer and are already in fsnative
native_parcs="aparc.DKTatlas aparc.a2009s aparc BA_exvivo"


# Perform the mapping from fsaverage to native
for hemi in lh rh; do
    for parc in ${parcs}; do
            annot_name=${hemi}.${parc}.annot
            fsaverage_annot=${annots_dir}/${annot_name}
            native_annot=${subject_fs}/label/${annot_name}
            stats_file=${subject_fs}/stats/${annot_name/.annot/.stats}

            ${singularity_cmd} \
                mri_surf2surf \
                --srcsubject fsaverage \
                --trgsubject ${subject_id} \
                --hemi ${hemi} \
                --sval-annot ${fsaverage_annot} \
                --tval ${native_annot}
    done
done

# create the .stats files for each annot file
for hemi in lh rh; do
    for parc in ${native_parcs} ${parcs}; do

            annot_name=${hemi}.${parc}.annot
            native_annot=${subject_fs}/label/${annot_name}
            stats_file=${subject_fs}/stats/${annot_name/.annot/.stats}

            # Surface stats
            ${singularity_cmd} \
                mris_anatomical_stats \
                -a ${native_annot} \
                -f ${stats_file} \
                -th3 \
                -noglobal \
                ${subject_id} \
                ${hemi}

            # GWR stats
            ${singularity_cmd} \
                mri_segstats \
                --in ${subject_fs}/surf/${hemi}.w-g.pct.mgh \
                --annot ${subject_id} ${hemi} ${parc} \
                --sum ${subject_fs}/stats/${hemi}.${parc}.w-g.pct.stats \
                --snr
    done
done

# Run qcache on this person to get the mgh files
${singularity_cmd} recon-all -s ${subject_id} -qcache

# Create the tsv files and jsons
python ${combine_script} ${subject_id}