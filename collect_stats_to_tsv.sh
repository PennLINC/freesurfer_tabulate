#!/bin/bash

script_name=$0

## Updates to make
# command line argument flags and usage [X]
# take in a comma separated list of metrics
# take in a comma separated list of aparcs
# longitudinal freesurfer processing -- will need to update qcache call to reconall -long cross-subject basesubject -qcache 

# A script that will calculate desired surface metrics for a list of surface atlases
# and will grab subject metadata. Creates stat tsv and json files of the results

usage() {
	cat << EOF >&2
Usage: $script_name [-s] [-f] [-c] [-n] [-l] [-o] [-m] [-p]

-s <subject_id>: The subject identifier. This is the subject's directory name in the freesurfer 
SUBJECTS_DIR (i.e., the identifier used with --s in freesurfer commands).

-f <freesurfer_dir>: The freesurfer SUBJECTS_DIR. The directory <freesurfer_dir>/<subject_id> 
must exist with typical freesurfer outputs mri/ surf/ label/ etc.

-c <freesurfer_sif>: Full path to the singularity SIF container with freesurfer. This should 
be the exact version of freesurfer that was used to create the data in freesurfer_dir. Can be 
a freesurfer.sif or fmriprep.sif

-n <neuromaps_sif>: Full path to a singularity container for neuromaps, used for the creation 
of cifti metric files

-l <freesurfer_license>: Full path to a freesurfer license.txt

-o <output_dir>: Path to where the output files will go

-m <metrics>: A comma separated list of metrics to generate stats and ciftis for, in addition to 
the metrics automatically calculated by mris_anatomical_stats (number of vertices, surface area, 
gray matter volume, average thickness, thickness std, mean curvature, gaussian curvative, folding 
index). Metrics can include freesurfer-generated metrics w-g.pct, sulc, pial_lgi, and/or 
user-specified measure(s). The user-specified measure(s) must have been projected onto both the 
subject's native surface and the fsaverage surface (with e.g. mri_vol2surf and mri_surf2surf) and 
must exist as .mgh files in <freesurfer_dir>/<subject_id>/surf in the format $hemi.<metric>.mgh 
and $hemi.<metric>.fsaverage.mgh, respectively. If no additional metrics are of interest, can 
be left blank (defaults to none) 

-p <parcellations>: A comma separated list of parcellations to compute stats and ciftis with, 
in addition to the 4 atlases that come with freesurfer and exist in fsnative (aparc.DKTatlas, 
aparc.a2009s, aparc, BA_exvivo). Parcellations can include any of the annot files found in 
freesurfer_tabulate/annots (e.g., glasser, Juelich, Schaefer2018_400Parcels_7Networks_order).
Can be left blank (defaults to all)
EOF

	exit 1
}

subject_id=false # positional argument
freesurfer_dir=false # positional argument
freesurfer_sif=false # positional argument
neuromaps_sif=false # positional argument
freesurfer_license=false # positional argument
output_dir=false # positional argument
metrics=none # user can specify a list of additional metrics, but defaults to none
parcellations=AAL,CC200,CC400,glasser,gordon333dil,HOCPATh25,Juelich,PALS_B12_Brodmann,Schaefer2018_1000Parcels_17Networks_order,Schaefer2018_1000Parcels_7Networks_order,Schaefer2018_100Parcels_17Networks_order,Schaefer2018_100Parcels_7Networks_order,Schaefer2018_200Parcels_17Networks_order,Schaefer2018_200Parcels_7Networks_order,Schaefer2018_300Parcels_17Networks_order,Schaefer2018_300Parcels_7Networks_order,Schaefer2018_400Parcels_17Networks_order,Schaefer2018_400Parcels_7Networks_order,Schaefer2018_500Parcels_17Networks_order,Schaefer2018_500Parcels_7Networks_order,Schaefer2018_600Parcels_17Networks_order,Schaefer2018_600Parcels_7Networks_order,Schaefer2018_700Parcels_17Networks_order,Schaefer2018_700Parcels_7Networks_order,Schaefer2018_800Parcels_17Networks_order,Schaefer2018_800Parcels_7Networks_order,Schaefer2018_900Parcels_17Networks_order,Schaefer2018_900Parcels_7Networks_order,Slab,Yeo2011_17Networks_N1000,Yeo2011_7Networks_N1000 # user can specify a list of parcellations, but defaults to all

while getopts "s:f:c:n:l:o:m:p:" opt; do
	case $opt in 
		(s) subject_id=$OPTARG;;
		(f) freesurfer_dir=$OPTARG;;
		(c) freesurfer_sif=$OPTARG;;
		(n) neurosynth_sif=$OPTARG;;
		(l) freesurfer_license=$OPTARG;;
		(o) output_dir=$OPTARG;;
		(m) metrics=$OPTARG;;
		(p) parcellations=$OPTARG;;
		 *) usage;;
	esac

	case $OPTARG in
		-) echo "Command line argument $opt needs a valid argument"
		exit 1 ;;
	esac
done

if [[ "$subject_id $freesurfer_dir $freesurfer_sif $neurosynth_sif $freesurfer_license $output_dir" =~ false ]] ; then
	echo " "
	echo "$0 call is missing a required command line argument, one of: -s -f -c -n -l -o"
	echo " "
	usage
	exit 1
fi

set -e -u -x

# Get input for this run
fs_root=$freesurfer_dir

if [[ ${subject_id} == *"long"* ]]; then
	longitudinal_fs=TRUE # running on longitudinal freesurfer output
fi

if [[ ${metrics} == *"lgi"* ]]; then
	compute_lgi=TRUE # computing lgi
fi

# Set up FreeSurfer environment 
source ${FREESURFER_HOME}/SetUpFreeSurfer.sh
export SUBJECTS_DIR=${fs_root}
subject_fs=${SUBJECTS_DIR}/${subject_id}

# Scripts and data dirs from freesurfer_tabulate repo
SCRIPT_DIR=$(dirname "$script_name")
annots_dir=${SCRIPT_DIR}/annots
parcstats_to_tsv_script=${SCRIPT_DIR}/compile_freesurfer_parcellation_stats.py
to_cifti_script=${SCRIPT_DIR}/vertex_measures_to_cifti.py
metadata_to_bids_script=${SCRIPT_DIR}/seg_and_metadata_to_bids.py

# CUBIC-specific stuff needed for LGI to be run outside of a container
if [[ ${compute_lgi} == TRUE ]]; then
	module load freesurfer/7.2.0
	export SUBJECTS_DIR=${fs_root}
	subject_fs=${SUBJECTS_DIR}/${subject_id}
fi

# Set singularity params
workdir=${subject_fs}
export APPTAINERENV_OMP_NUM_THREADS=1
export APPTAINERENV_NSLOTS=1
export APPTAINERENV_ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
export APPTAINERENV_SUBJECTS_DIR=${SUBJECTS_DIR}
export APPTAINER_TMPDIR=${SINGULARITY_TMPDIR}
export APPTAINERENV_NEUROMAPS_DATA=${SUBJECTS_DIR}/${subject_id}/trash # we're using the subject's trash directory as a temp dir for neuromaps data
singularity_cmd="singularity exec --containall --writable-tmpfs -B ${SUBJECTS_DIR} -B ${annots_dir} -B ${freesurfer_license}:/opt/freesurfer/license.txt ${freesurfer_sif}"
neuromaps_singularity_cmd="singularity exec --containall --writable-tmpfs -B ${SUBJECTS_DIR} -B ${SCRIPT_DIR} ${neuromaps_sif}"

# Special atlases that we need to warp from fsaverage to native
parcs=${parcellations//,/ }
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

# Run qcache on this person to get the mgh files
if [[ $longitudinal_fs == TRUE ]]; then
	cross_sectional_id=$(echo $subject_id | cut -f 1 -d'.') #extract the cross-sectional freesurfer id $cross.long.$base
	base_id=$(echo $subject_id | cut -f 3 -d'.') #extract the base template freesurfer id $cross.long.$base
	${singularity_cmd} recon-all -long ${cross_sectional_id} ${base_id} -qcache
else
	${singularity_cmd} recon-all -s ${subject_id} -qcache
fi

# CUBIC-specific stuff needed for LGI to be run outside of a container
# NOTE: this is not done with a container because it requires matlab :(
if [[ ${compute_lgi} == TRUE ]]; then
	module load freesurfer/7.2.0
	export SUBJECTS_DIR=${fs_root}
	subject_fs=${SUBJECTS_DIR}/${subject_id}
	HAS_LGI=1
	set +e
	recon-all -s ${subject_id} -localGI
	# It may fail the first time, so try running it again:
	if [ $? -gt 0 ]; then
    	HAS_LGI=0
    	find ${subject_fs} -name '*pial_lgi' -delete
	fi
	set -e
fi


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

            if [ $HAS_LGI -gt 0 ]; then
                # LGI stats
                ${singularity_cmd} \
                    mri_segstats \
                    --annot ${subject_id} ${hemi} ${parc} \
                    --in ${subject_fs}/surf/${hemi}.pial_lgi \
                    --sum ${subject_fs}/stats/${hemi}.${parc}.pial_lgi.stats
            fi
    done
done

# Create the tsvs for the regional stats from the parcellations
${neuromaps_singularity_cmd} \
python ${parcstats_to_tsv_script} ${subject_id} ${native_parcs} ${parcs}
${neuromaps_singularity_cmd} \
python ${metadata_to_bids_script} ${subject_id}

# Get these into MGH
if [ $HAS_LGI -gt 0 ]; then
    ${singularity_cmd} recon-all -s ${subject_id} -qcache -measure pial_lgi
fi

# Big picture here: get these mgh metrics into cifti format
# first we have to export them from mgh to gifti. We'll use freesurfer for this
# but it will create malformed gifti files.
cd ${subject_fs}/surf
for hemi in lh rh
do
    for mgh_surf in ${hemi}*fsaverage.mgh
    do
        ${singularity_cmd} mris_convert \
            -c ${PWD}/${mgh_surf} \
            ${SUBJECTS_DIR}/fsaverage/surf/${hemi}.white \
            ${PWD}/${mgh_surf/.mgh/.malformed.shape.gii}
    done
done

# Finally, use neuromaps to go from fsaverage to fsLR164k.
${neuromaps_singularity_cmd} \
  python ${to_cifti_script} \
  ${subject_fs}

# Remove the malformed data from surf/
rm -fv ${subject_fs}/surf/*malformed*

# gather fsaverage mgh files
mkdir -p "${output_dir}/${subject_id}_fsaverage"
mv ${subject_fs}/surf/*fsaverage*mgh "${output_dir}/${subject_id}_fsaverage/"

# gather the fslr cifti files
mkdir -p "${output_dir}/${subject_id}_fsLR_den-164k"
mv ${subject_fs}/surf/*.nii "${output_dir}/${subject_id}_fsLR_den-164k/"

# Move the surface stats tsv
mv ${subject_fs}/*regionsurfacestats.tsv ${output_dir}/
# Move the metadata
mv ${SUBJECTS_DIR}/*brainmeasures.* ${output_dir}/

# Remove temp files from neuromaps
rm -rf ${subject_fs}/trash/*

# Compress the subject freesurfer directory and move it to outputs
cd "${SUBJECTS_DIR}"
tar cvfJ ${subject_id}_freesurfer.tar.xz ${subject_id}
mv ${subject_id}_freesurfer.tar.xz ${output_dir}

cd ${output_dir}
tar cvfJ ${subject_id}_fsaverage.tar.xz ${subject_id}_fsaverage
tar cvfJ ${subject_id}_fsLR_den-164k.tar.xz ${subject_id}_fsLR_den-164k
rm -rf ${subject_id}_fsaverage ${subject_id}_fsLR_den-164k


