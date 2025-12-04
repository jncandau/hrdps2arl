#!/bin/bash

# Default flags
RUN_A=false
RUN_B=false
RUN_C=false
RUN_D=false
RUN_E=false
DATE=""

# Function to validate date format YYYYMMDD
validate_date() {
    local date_input="$1"
    
    # Check if date matches YYYYMMDD format (8 digits)
    if [[ ! "$date_input" =~ ^[0-9]{8}$ ]]; then
        echo "Error: Date must be in YYYYMMDD format (8 digits)"
        return 1
    fi
    
    # Extract year, month, day
    local year="${date_input:0:4}"
    local month="${date_input:4:2}"
    local day="${date_input:6:2}"
    
    # Validate month (01-12)
    if [[ "$month" -lt 1 || "$month" -gt 12 ]]; then
        echo "Error: Month must be between 01 and 12"
        return 1
    fi
    
    # Validate day (01-31)
    if [[ "$day" -lt 1 || "$day" -gt 31 ]]; then
        echo "Error: Day must be between 01 and 31"
        return 1
    fi
    
    # Additional validation: check if date actually exists
    if ! date -d "$year-$month-$day" &>/dev/null; then
        echo "Error: Invalid date - $year-$month-$day does not exist"
        return 1
    fi
    
    return 0
}


# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -x)
            DATE="$2"
            shift 2
            ;;
        -a)
            RUN_A=true
            shift
            ;;
        -b)
            RUN_B=true
            shift
            ;;
        -c)
            RUN_C=true
            shift
            ;;
        -d)
            RUN_D=true
            shift
            ;;
        -e)
            RUN_E=true
            shift
            ;;
        --all)
            RUN_A=true
            RUN_B=true
            RUN_C=true
            RUN_D=true
            RUN_E=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 -x DATE [options]"
            echo ""
            echo "Required:"
            echo "  -x      DATE  Date in YYYYMMDD format"
            echo ""
            echo "Options:"
            echo "  -a      Download and preprocess HRDPS data"
            echo "  -b      Create daily GRIB files"
            echo "  -c      Trim daily grids to region of interest"
            echo "  -d      Run HYSPLIT model"
            echo "  -e      Convert trajectory to shapefile"
            echo "  --all   Run all"
            echo "  -h      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if date was provided
if [[ -z "$DATE" ]]; then
    echo "Error: Date is required. Use -d or --date to specify a date in YYYYMMDD format."
    echo "Use -h for help."
    exit 1
fi

# Validate the date format
if ! validate_date "$DATE"; then
    exit 1
fi


RUN_DATE=$DATE
echo "Date validated: $RUN_DATE"

# We use the hourly predictions at noon every day
RUN_TIME=00 # cycle (UTC)
FH_BEG=0           # first forecast hour
FH_END=8          # last forecast hour to convert
# Lat Long and altitude of starting point
LAT=50
LON=-90
ALT=500

#Environment Canada native rotated ll projection
EC_SRS='+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs'

DROOT=/home/jcandau/scratch/Test4/
OUTROOT=HRDPS_$(date -u -d $RUN_DATE +%Y%m%d%H)
WORKDIR=$DROOT/$OUTROOT

# Pressure levels to download
# These levels must match the levels available from EC HRDPS data
PLVLS=(1015 1000 985 970 950 925 900 850 800 750 700 650 600 550 500 450 400 350 300 275 250 225 200 150 100 50)

# Variables to download - These variables must match the names of the grib files from EC
PL_VARS=(TMP UGRD VGRD RH VVEL HGT SPFH)    # temperature, wind, humidity, omega, height
#SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFP_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m" "CAPE_Sfc" "TCDC_Sfc")
# Here I am removing CAPE and TCDC because I can't find a way to set the shortName for these two using grib_set. When I try to change the shortName
# it also changes the levelOf(something) and I can't seem to be able to correct that
SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFL_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m")

# We also download OROGRAPHY which is important for Hysplit
# This variable is available from the Weather Events on a Grid (WEonG) only for predictions at 1h and more (not 000)
# The url is: https://dd.meteo.gc.ca/today/model_hrdps/continental/2.5km/00/006/20251125T00Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT006H.grib2

# Decide if we reproject the gribs from rotated latlong to regular latlong
REPROJECT=0

# ============================================
# SUB-SCRIPT A: Download and preprocess HRDPS data
# ============================================
run_subscript_a() {

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
                    curl -f -s -S -o "$GRIB_FILE" "$url" || true
                    if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                        echo "Error downloading: ${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${V}_ISBL_${L4d}_RLatLon0.0225_PT${FHR3d}H.grib2"
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
                    echo "Error downloading: ${CYCLE}T${RUN_TIME}Z_MSC_HRDPS_${SV}_RLatLon0.0225_PT${FHR3d}H.grib2"
                fi
            fi
        done

        # Download orography from the Weather Events on a Grid data type
        # Note that orography is not available for the prediction at 000H so we have to download it from 001H
        # and copy it as 000H while changing the forecastTime to 0
        GRIB_FILE="$WORKDIR/surface/${CYCLE}T${RUN_TIME}Z_OROGRAPHY_SFC_${FHR3d}H.grib2"
        GRIB_TMP="$WORKDIR/surface/${CYCLE}T${RUN_TIME}Z_OROGRAPHY_SFC_${FHR3d}H.tmp"
        if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
            if [[ $FHR -eq "0" || $FHR -eq 0 ]]; then
                echo "FHR= $FHR"
                echo "Processing ORO at 000"
                url="${BASE_URL}/001/${CYCLE}T${RUN_TIME}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT001H.grib2"
                echo $url
                echo $GRIB_TMP
                curl -fsS -o "$GRIB_TMP" "$url" || true
                grib_set -s forecastTime=0,stepRange=0 "$GRIB_TMP" "$GRIB_FILE"
                rm $GRIB_TMP
            else
                echo "Processing ORO at > 000"
                url="${BASE_URL}/${FHR3d}/${CYCLE}T${RUN_TIME}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT${FHR3d}H.grib2"
                curl -fsS -o "$GRIB_FILE" "$url" || true
                if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                    echo "Error downloading: ${BASE_URL}/${FHR3d}/${CYCLE}T${RUN_TIME}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT${FHR3d}H.grib2"
                fi
            fi
        fi
    done
    echo "Downloading completed."

if [ $REPROJECT -ne 0 ]; then
    for FHR in $(seq -w $FH_BEG $FH_END); do
        FHR3d=$(printf "%03d" "$FHR")
        echo "Reprojecting for time: $FHR3d"

        cd "${WORKDIR}/levels"
        # Pressure levels
        for L in "${PLVLS[@]}"; do
            for V in "${PL_VARS[@]}"; do
                GRIB_FILE="${CYCLE}T${RUN_TIME}Z_${V}_ISBL_${L}_${FHR3d}H.grib2"
                GRIB_FILE_LL="${CYCLE}T${RUN_TIME}Z_${V}_ISBL_${L}_${FHR3d}H_ll.grib2"
                if [ -f "$GRIB_FILE" ]; then
                    gdalwarp -r bilinear -t_srs "EPSG:4326" "$GRIB_FILE" "$GRIB_FILE_LL"
                fi
            done
        done

        cd "${WORKDIR}/surface"
        # Surface fields
        for SV in "${SFC_VARS[@]}"; do
            GRIB_FILE="${CYCLE}T${RUN_TIME}Z_${SV}_SFC_${FHR3d}H.grib2"
            GRIB_FILE_LL="${CYCLE}T${RUN_TIME}Z_${SV}_SFC_${FHR3d}H_ll.grib2"
            if [ -f "$GRIB_FILE" ]; then
                gdalwarp -r bilinear -t_srs "EPSG:4326" "$GRIB_FILE" "$GRIB_FILE_LL"
            fi
        done
    done
fi
}

# ============================================
# SUB-SCRIPT B: Create daily GRIB files
# ============================================
run_subscript_b() {
    echo "Creating daily GRIB files..."
    CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)

if [ $REPROJECT -eq 0 ]; then
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2
   cd $WORKDIR/levels
   find . -type f ! -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_levels.grib2
   # Sort the resulting grids by date and time
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_levels.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2
   rm $WORKDIR/arl/temp_levels.grib2
   cd $WORKDIR/surface
   find . -type f ! -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_surface.grib2
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_surface.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2
   rm $WORKDIR/arl/temp_surface.grib2
else
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2
   cd $WORKDIR/levels
   find . -type f -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_levels_ll.grib2
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_levels_ll.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2
   rm $WORKDIR/arl/temp_levels_ll.grib2
   cd $WORKDIR/surface
   find . -type f -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_surface_ll.grib2
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_surface_ll.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2
   rm $WORKDIR/arl/temp_surface_ll.grib2
fi
    echo "Daily GRIB files created."
}

# ====================================================  
# SUB-SCRIPT C: Trim daily grids to region of interest
# ====================================================
run_subscript_c() {
    CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)
    echo "Trimming daily grids to region of interest..."
    cd $WORKDIR/arl

    if [[ -f DATA.ARL ]]; then
        rm DATA.ARL
    fi
    
    # Calculate the bounding box for trimming
    UL_LON=$(($LON - 5))
    UL_LAT=$(($LAT + 5))
    LR_LON=$(($LON + 5))
    LR_LAT=$(($LAT - 5))

    if [ $REPROJECT -eq 0 ]; then
        #Calculate the bounding box for the trim
        UL=$(echo -e "$UL_LON $UL_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
        LR=$(echo -e "$LR_LON $LR_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
        echo "Trimming daily gribs"
        gdal_translate -projwin $UL $LR ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2 surface_small.grib2
        gdal_translate -projwin $UL $LR ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2 levels_small.grib2
        echo "Converting to ARL format"
        hrdps2arl -llevels_small.grib2 -ssurface_small.grib2
    else
        echo "Trimming daily gribs"
        gdal_translate -projwin $UL_LON $UL_LAT $LR_LON $LR_LAT ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2 surface_small_ll.grib2
        gdal_translate -projwin $UL_LON $UL_LAT $LR_LON $LR_LAT ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2 levels_small_ll.grib2
        echo "Converting to ARL format"
        hrdps2arl -llevels_small_ll.grib2 -ssurface_small_ll.grib2
    fi

    echo "Trimming completed."
}

# ============================================
# SUB-SCRIPT D: Run HYSPLIT model
# ============================================
run_subscript_d() {

    CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)
    
    echo "converting HRDPS GRIB to HYSPLIT format..."
    
    cd $WORKDIR/arl

    if [ $REPROJECT -eq 0 ]; then
        hrdps2arl -llevels_small.grib2 -ssurface_small.grib2
    else
        hrdps2arl -llevels_small_ll.grib2 -ssurface_small_ll.grib2
    fi

    echo "Preparing to run HYSPLIT model..."

    # Write CONTROL FILE
    # Careful because the coordinates in the CONTROL FILE
    # are in the order LAT LON, not LON LAT
    CONTROL_FILE="CONTROL"
    echo $(date -u -d $RUN_DATE +'%Y %m %d %H') > $CONTROL_FILE
    echo "1" >> $CONTROL_FILE
    if [ $REPROJECT -eq 0 ]; then
        SP1=$(echo -e "$LON $LAT $ALT" | gdaltransform -s_srs EPSG:4326 -t_srs "$EC_SRS")
        SP2="$(echo $SP1 | cut -d " " -f 2) $(echo $SP1 | cut -d " " -f 1)  $(echo $SP1 | cut -d " " -f 3)"
        echo "${SP2}" >> $CONTROL_FILE
    else
        echo "$LAT $LON $ALT" >> $CONTROL_FILE
    fi
    echo "6" >> $CONTROL_FILE
    echo "0" >> $CONTROL_FILE
    echo "15500" >> $CONTROL_FILE
    echo "1" >> $CONTROL_FILE
    echo "./" >> $CONTROL_FILE
    echo "DATA.ARL" >> $CONTROL_FILE
    echo "./" >> $CONTROL_FILE
    echo "tdump.$CYCLE" >> $CONTROL_FILE

    # Write SETUP FILE
    SETUP_FILE="SETUP"
    echo "&SETUP" >> $SETUP_FILE
    # Altitude of starting point is in meters AGL
    echo "KMSL=0," >> $SETUP_FILE
    echo "/" >> $SETUP_FILE

    # Copy ASCDATA.CFG
    if [ -f $DROOT/bdyfiles/ASCDATA.CFG ]; then
        cp $DROOT/bdyfiles/* .
    else
        echo "ERROR: ASCDATA.CFG not found in $DROOT/bdyfiles/"
        return 1
    fi

    # Run Hysplit
    hyts_std


    # Export to kml
    trajplot -a3 -A1 -f0 -itdump.${CYCLE} -otmp

    if [[ $REPROJECT -eq 0 ]]; then
        ogr2ogr -t_srs EPSG:4326 -s_srs "$EC_SRS" trajectory_${CYCLE}.kml tmp_01.kml
        rm tmp_01.kml tmp.ps 
     else
        mv tmp_01.kml trajectory_${CYCLE}.kml
        rm tmp.ps
    fi

    echo "HYSPLIT model run completed."
}

# ============================================  
# SUB-SCRIPT E: convert Hysplit trajectory to shapefile
# ============================================
run_subscript_e() {
    
    CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)
    
    echo "converting Hysplit trajectory to shapefile..."
    ogr2ogr trajectory_20251110.shp trajectory_20251110.kml
    echo "Conversion completed."
}

# ============================================
# MAIN EXECUTION
# ============================================
echo "Starting main script..."

[[ "$RUN_A" == true ]] && run_subscript_a
[[ "$RUN_B" == true ]] && run_subscript_b
[[ "$RUN_C" == true ]] && run_subscript_c
[[ "$RUN_D" == true ]] && run_subscript_d
[[ "$RUN_E" == true ]] && run_subscript_e

echo "Main script finished."