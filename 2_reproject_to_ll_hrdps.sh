#!/usr/bin/env bash

source ./0_set_parameters_hrdps.sh

CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)

for FHR in $(seq -w $FH_BEG $FH_END); do
  FHR3d=$(printf "%03d" "$FHR")
  echo 'Reprojecting for time: '$FHR3d
  
  cd ${WORKDIR}/levels
  # Pressure levels
  for L in "${PLVLS[@]}"; do
    for V in "${PL_VARS[@]}"; do
     GRIB_FILE="${CYCLE}T${RUN_TIME}Z_${V}_ISBL_${L}_${FHR3d}H.grib2"
     GRIB_FILE_LL="${CYCLE}T${RUN_TIME}Z_${V}_ISBL_${L}_${FHR3d}H_ll.grib2"
     if [ -f $GRIB_FILE ]; then
     	gdalwarp -r bilinear -t_srs "EPSG:4326" $GRIB_FILE $GRIB_FILE_LL
    fi
    done
  done

  cd ${WORKDIR}/surface
  # Surface fields
  for SV in "${SFC_VARS[@]}"; do
    GRIB_FILE="${CYCLE}T${RUN_TIME}Z_${SV}_SFC_${FHR3d}H.grib2"
    GRIB_FILE_LL="${CYCLE}T${RUN_TIME}Z_${SV}_SFC_${FHR3d}H_ll.grib2"
    if [ -f $GRIB_FILE ]; then
       gdalwarp -r bilinear -t_srs "EPSG:4326" $GRIB_FILE $GRIB_FILE_LL
    fi
  done
done
