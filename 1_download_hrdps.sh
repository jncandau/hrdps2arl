#!/usr/bin/env bash

source ./0_set_parameters_hrdps.sh

mkdir -p "$WORKDIR"/{surface,levels,arl}

cd "$WORKDIR"

CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)
BASE_URL="https://dd.weather.gc.ca/${CYCLE}/WXO-DD/model_hrdps/continental/2.5km/$RUN_TIME/"  # example pattern

# Function to check that a grib file exists and is valid
check_grib() {
      GRIB_PRESENT=0
      if [ -f $1 ]; then
         grib_ls $1 > /dev/null 2>&1
         if [[ $? -eq 0 ]]; then
            GRIB_PRESENT=1
         fi
      fi
      echo $GRIB_PRESENT
}

rm $WORKDIR/Missing_downloads.txt
touch $WORKDIR/Missing_downloads.txt
echo "Missing downloads $(date)" >> $WORKDIR/Missing_downloads.txt

for FHR in $(seq -w $FH_BEG $FH_END); do
  FHR3d=$(printf "%03d" "$FHR")
  echo "Dowloading gribs for date $CYCLE run time $FHR3d"

  # Pressure levels
  for L in "${PLVLS[@]}"; do
    L4d=$(printf "%04d" "$L")
    for V in "${PL_VARS[@]}"; do
      GRIB_FILE="$WORKDIR/levels/${CYCLE}T${RUN_TIME}Z_${V}_ISBL_${L}_${FHR3d}H.grib2"
      if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
        url="${BASE_URL}/${FHR3d}/${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${V}_ISBL_${L4d}_RLatLon0.0225_PT${FHR3d}H.grib2"
      	curl -fsS -o "$GRIB_FILE" "$url" || true
        if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
	   echo "${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${V}_ISBL_${L4d}_RLatLon0.0225_PT${FHR3d}H.grib2" >> $WORKDIR/Missing_downloads.txt
	fi
      fi
    done
  done

  # Surface fields
  for SV in "${SFC_VARS[@]}"; do
    # e.g., AGL-10m, AGL-2m, MSL
    GRIB_FILE="$WORKDIR/surface/${CYCLE}T${RUN_TIME}Z_${SV}_SFC_${FHR3d}H.grib2"
    if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
        url="${BASE_URL}/${FHR3d}/${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${SV}_RLatLon0.0225_PT${FHR3d}H.grib2"
	curl -fsS -o "$GRIB_FILE" "$url" || true
	if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
	   echo "${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${SV}_RLatLon0.0225_PT${FHR3d}H.grib2" >> $WORKDIR/Missing_downloads.txt
	fi
    fi
  done
done
