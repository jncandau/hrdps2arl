#!/usr/bin/env bash
set -euo pipefail

############################
# User input
############################
GRIB=$1   # GRIB2 file containing rotated LL grid
LON=$2    # regular lon (WGS84)
LAT=$3    # regular lat (WGS84)

############################
# 1. Extract rotated pole metadata using ecCodes
############################

echo "Extracting rotated pole from GRIB2..."

# Some GRIBs use 'latitudeOfSouthernPole', others 'latitudeOfThePole'
LAT_POLE=$(grib_get -w gridType=rotated_ll -p latitudeOfSouthernPole $GRIB 2>/dev/null || \
           grib_get -w gridType=rotated_ll -p latitudeOfThePole $GRIB)

LON_POLE=$(grib_get -w gridType=rotated_ll -p longitudeOfSouthernPole $GRIB 2>/dev/null || \
           grib_get -w gridType=rotated_ll -p longitudeOfThePole $GRIB)

ROT_ANGLE=$(grib_get -w gridType=rotated_ll -p angleOfRotation $GRIB 2>/dev/null || echo "0")

echo "Rotated pole lat:  $LAT_POLE"
echo "Rotated pole lon:  $LON_POLE"
echo "Rotation angle:    $ROT_ANGLE"

############################
# 2. Build PROJ rotated-pole CRS string for GDAL
############################

# PROJ rotated-pole syntax:
#   +proj=ob_tran +o_proj=longlat +lon_0=<pole_lon+180> +o_lat_p=<pole_lat>
#   +o_lon_p=0 +datum=WGS84 +to_meter=1

# Convert pole lon for GDAL:
LON0=$(awk -v lp=$LON_POLE 'BEGIN { print lp + 180 }')

PROJ_ROT="+proj=ob_tran +o_proj=longlat +o_lat_p=${LAT_POLE} +o_lon_p=0 +lon_0=${LON0} +datum=WGS84 +to_meter=1"

echo "Using PROJ CRS:"
echo "$PROJ_ROT"

############################
# 3. Apply coordinate transformation WGS84 → rotated grid
############################

echo "Transforming ($LON, $LAT) → rotated lat/lon..."

gdaltransform \
    -s_srs EPSG:4326 \
    -t_srs "${PROJ_ROT}" <<EOF
$LON $LAT
EOF
