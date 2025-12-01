#!/usr/bin/env bash
set -euo pipefail

############################
# User input
############################
SHAPE=$1  # shapefile to reproject
OUT=$2

PROJ_ROT="+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs"
echo "Using PROJ CRS:"
echo "$PROJ_ROT"

echo "Transforming rotated lat/lon to regular"

ogr2ogr \
    -t_srs EPSG:4326 \
    -s_srs "${PROJ_ROT}" $2 $1
