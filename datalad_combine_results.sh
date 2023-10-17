#!/bin/bash

datalad run \
    -i './freesurfer/*/*brainmeasures.tsv' \
    -i './freesurfer/*/*regionsurfacestats.tsv' \
    -o './*_surfacestats.parquet' \
    -o './group_brainmeasures.parquet' \
    --expand both \
    --explicit \
    -m "concatenate group measures" \
    "python freesurfer_tabulate/group_combine.py"