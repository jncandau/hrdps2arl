#!/bin/bash

# Converts rotated regular WGS84 lat/lon to Environment Canada native rotated lat/lon
# Usage: ll_to_EC.sh <lon> <lat>

set -euo pipefail

############################
# User input
############################
LON=$1    # rotated lon
LAT=$2    # rotated lat

#Environment Canada native rotated ll projection
EC_SRS='+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs'

UL=$(echo -e "$LON $LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")

echo "Transforming ($LON, $LAT) → EC rotated lat/lon..."
echo "Transformed coordinates: $UL"

