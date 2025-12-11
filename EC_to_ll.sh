#!/bin/bash

# Converts rotated lat/lon coordinates to regular WGS84 lat/lon
# Usage: EC_to_ll.sh <GRIB2_file> <lon> <lat>

set -euo pipefail

############################
# User input
############################
LON=$1    # rotated lon
LAT=$2    # rotated lat

#Environment Canada native rotated ll projection
EC_SRS='+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs'

UL=$(echo -e "$UL_LON $UL_LAT" | gdaltransform -output_xy -t_srs EPSG:4326 -s_srs "$EC_SRS")

echo "Transforming rotated ($LON, $LAT) → WGS84 lat/lon..."
echo "Transformed coordinates:",$UL

