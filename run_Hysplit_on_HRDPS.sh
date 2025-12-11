#!/bin/bash

# Default flags
RUN_A=false
RUN_B=false
RUN_C=false
RUN_D=false
RUN_E=false
DATE=""

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
        -d)
            DATE="$2"
            shift 2
            ;;
        -x)
            LON="$2"
            shift 2
            ;;
        -y)
            LAT="$2"
            shift 2
            ;;
        -z)
            ALT="$2"
            shift 2
            ;;
        -p)
            RUN_P=true
            shift
            ;;
        -c)
            RUN_C=true
            shift
            ;;
        -t)
            RUN_T=true
            shift
            ;;
        -r)
            RUN_R=true
            shift
            ;;
        -s)
            RUN_S=true
            shift
            ;;
        --all)
            RUN_P=true
            RUN_C=true
            RUN_T=true
            RUN_R=true
            RUN_S=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options] -d DATE -x LONGITUTE -y LATITUDE -z ALTITUDE"
            echo ""
            echo "Required:"
            echo "  -d      DATE  Date in YYYYMMDD format"
            echo "  -x      LONGITUDE  Longitude in decimal degrees"
            echo "  -y      LATITUDE   Latitude in decimal degrees"
            echo "  -z      ALTITUDE    Altitude in meters above ground level"
            echo ""
            echo "Options:"
            echo "  -p      Download and preprocess HRDPS data"
            echo "  -c      Create daily GRIB files"
            echo "  -t      Trim daily grids to region of interest"
            echo "  -r      Run HYSPLIT model"
            echo "  -s      Convert trajectory to shapefile"
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

# Initialize arrays
# According to Philippe Barneoud and Alain Malo, it is better to not use the 000 forecast hour because
# this data may be biased.
RUN_DATE=()
# Loop from i=0 to 23
for i in {0..23}; do
    if [ $i -le 12 ]; then
        RUN_DATE[$i]=$(date -u --date=$DATE +%Y%m%d)
     else
        RUN_DATE[$i]=$(date -u --date="$DATE + 1 day" +%Y%m%d)
    fi
done
#RUN_TIME=(12 12 12 12 12 12 18 18 18 18 18 18 00 00 00 00 00 00 06 06 06 06 06 06)
#F_HOUR=(000 001 002 003 004 005 000 001 002 003 004 005 000 001 002 003 004 005 000 001 002 003 004 005)
RUN_TIME=( 06 12 12 12 12 12 12 18 18 18 18 18 18 00 00 00 00 00 00 06 06 06 06 06)
F_HOUR=(006 001 002 003 004 005 006 001 002 003 004 005 006 001 002 003 004 005 006 001 002 003 004 005)

for i in {0..23}; do
echo $i ${RUN_DATE[$i]} ${RUN_TIME[$i]} ${F_HOUR[$i]}
done

#Environment Canada native rotated ll projection
EC_SRS='+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs'

DROOT=/home/jcandau/scratch/Test4/
OUTROOT=HRDPS_$(date -u -d $DATE +%Y%m%d%H)
WORKDIR=$DROOT/$OUTROOT

# Pressure levels to download
# These levels must match the levels available from EC HRDPS data
PLVLS=(1015 1000 985 970 950 925 900 850 800 750 700 650 600 550 500 450 400 350 300 275 250 225 200 150 100 50)

# Variables to download - These variables must match the names of the grib files from EC
PL_VARS=(TMP UGRD VGRD RH VVEL HGT SPFH)    # temperature, wind, humidity, omega, height
#SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFP_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m" "CAPE_Sfc" "TCDC_Sfc")
# Here I am removing CAPE and TCDC because I can't find a way to set the shortName for these two using grib_set. When I try to change the shortName
# it also changes the levelOf(something) and I can't seem to be able to correct that
SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFL_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m" "CAPE_Sfc" "TCDC_Sfc" "PRATE_Sfc")
# We also download OROGRAPHY which is important for Hysplit
# This variable is available from the Weather Events on a Grid (WEonG) only for predictions at 1h and more (not 000)
# The url is: https://dd.meteo.gc.ca/today/model_hrdps/continental/2.5km/00/006/20251125T00Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT006H.grib2

# ============================================
# SUB-SCRIPT P: Download and preprocess HRDPS data
# ============================================
run_subscript_P() {

    mkdir -p "$WORKDIR"/{surface,levels,arl}

    cd "$WORKDIR"

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

    for i in {0..23}; do
        echo "---------------------------------------------------------------------------------------"
        echo "Dowloading gribs for date ${RUN_DATE[$i]} run time ${RUN_TIME[$i]} forecast hour ${F_HOUR[$i]}"

        BASE_URL="https://dd.weather.gc.ca/${RUN_DATE[$i]}/WXO-DD/model_hrdps/continental/2.5km/${RUN_TIME[$i]}/"

        # Pressure levels
        for L in "${PLVLS[@]}"; do
            L4d=$(printf "%04d" "$L")
            for V in "${PL_VARS[@]}"; do
                GRIB_FILE="$WORKDIR/levels/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_${V}_ISBL_${L}_${F_HOUR[$i]}H.grib2"
                if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                    url="${BASE_URL}/${F_HOUR[$i]}/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_MSC_HRDPS_${V}_ISBL_${L4d}_RLatLon0.0225_PT${F_HOUR[$i]}H.grib2"
                    curl -f -s -S -o "$GRIB_FILE" "$url" || true
                    if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                        echo "Error downloading: ${url} as ${GRIB_FILE}"
                    fi
                fi
            done
        done

        # Surface fields
        for SV in "${SFC_VARS[@]}"; do
            # e.g., AGL-10m, AGL-2m, MSL
            echo "Downloading surface variable: ${SV}"
            GRIB_FILE="$WORKDIR/surface/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_${SV}_SFC_${F_HOUR[$i]}H.grib2"
            if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                url="${BASE_URL}/${F_HOUR[$i]}/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_MSC_HRDPS_${SV}_RLatLon0.0225_PT${F_HOUR[$i]}H.grib2"
                curl -fsS -o "$GRIB_FILE" "$url" || true
                if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                    echo "Error downloading: ${url} as ${GRIB_FILE}"
                fi
		    fi
            if [ $(check_grib $GRIB_FILE) -eq 1 ]; then
		        if [ ${SV} == "CAPE_Sfc" ]; then
                    echo "Changing shortName for CAPE"
		            grib_set -s shortName=cape ${GRIB_FILE} ${GRIB_FILE}.tmp
		            mv ${GRIB_FILE}.tmp ${GRIB_FILE}
		        fi
		        if [ ${SV} == "TCDC_Sfc" ]; then
                    echo "Changing shortName for TCDC"
                    grib_set -s shortName=tcc ${GRIB_FILE} ${GRIB_FILE}.tmp
                    mv ${GRIB_FILE}.tmp ${GRIB_FILE}
                fi
            fi
        done

        # Download orography from the Weather Events on a Grid data type
        # Note that orography is not available for the prediction at 000H so we have to download it from 001H
        # and copy it as 000H while changing the forecastTime to 0
        GRIB_FILE="$WORKDIR/surface/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_OROGRAPHY_SFC_${F_HOUR[$i]}H.grib2"
        GRIB_TMP="$WORKDIR/surface/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_OROGRAPHY_SFC_${F_HOUR[$i]}H.tmp"
        if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
            if [[ ${F_HOUR[$i]} == "000" ]]; then
                echo "F_HOUR= ${F_HOUR[$i]}"
                echo "Processing ORO at 000"
                url="${BASE_URL}/001/${F_DATE[$i]}T${RUN_TIME[$i]}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT001H.grib2"
                echo $url
                echo $GRIB_TMP
                curl -fsS -o "$GRIB_TMP" "$url" || true
                grib_set -s forecastTime=0,stepRange=0 "$GRIB_TMP" "$GRIB_FILE"
                rm $GRIB_TMP
            else
                echo "Processing ORO at > 000"
                url="${BASE_URL}/${F_HOUR[$i]}/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT${F_HOUR[$i]}H.grib2"
                curl -fsS -o "$GRIB_FILE" "$url" || true
                if [ $(check_grib $GRIB_FILE) -eq 0 ]; then
                    echo "Error downloading: ${BASE_URL}/${F_HOUR[$i]}/${RUN_DATE[$i]}T${RUN_TIME[$i]}Z_MSC_HRDPS-WEonG_ORGPHY_Sfc_RLatLon0.0225_PT${F_HOUR[$i]}H.grib2"
                fi
            fi
        else
            echo "Orography file already exists: $GRIB_FILE"
        fi
    done
    echo "Downloading completed."
}

# ============================================
# SUB-SCRIPT C: Create daily GRIB files
# ============================================
run_subscript_C() {
    echo "Creating daily GRIB files..."
    rm -f $WORKDIR/arl/*_HRDPS_levels.grib2
    rm -f $WORKDIR/arl/*_HRDPS_surface.grib2
    cd $WORKDIR/levels
    find . -type f -name "*.grib2" -exec cat {} + > $WORKDIR/arl/temp_levels.grib2
    # Sort the resulting grids by date and time
    grib_copy -B "validityDate:i asc, validityTime:i asc, level:i asc" $WORKDIR/arl/temp_levels.grib2 $WORKDIR/arl/${DATE}_HRDPS_levels.grib2
    # rm $WORKDIR/arl/temp_levels.grib2
    cd $WORKDIR/surface
    find . -type f -name "*.grib2" -exec cat {} + > $WORKDIR/arl/temp_surface.grib2
    grib_copy -B "validityDate:i asc, validityTime:i asc, level:i asc" $WORKDIR/arl/temp_surface.grib2 $WORKDIR/arl/${DATE}_HRDPS_surface.grib2
    # rm $WORKDIR/arl/temp_surface.grib2
    echo "Daily GRIB files created."
}

# ====================================================  
# SUB-SCRIPT T: Trim daily grids to region of interest
# ====================================================
run_subscript_T() {
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

    #Calculate the bounding box for the trim
    UL=$(echo -e "$UL_LON $UL_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
    LR=$(echo -e "$LR_LON $LR_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
    echo "Trimming daily gribs"
    gdal_translate -projwin $UL $LR ${DATE}_HRDPS_surface.grib2 surface_small.grib2
    gdal_translate -projwin $UL $LR ${DATE}_HRDPS_levels.grib2 levels_small.grib2
    echo "Converting to ARL format"
    hrdps2arl -llevels_small.grib2 -ssurface_small.grib2

    echo "Trimming completed."
}

# ============================================
# SUB-SCRIPT R: Run HYSPLIT model
# ============================================
run_subscript_R() {
    
    echo "converting HRDPS GRIB to HYSPLIT format..."
    
    cd $WORKDIR/arl

    hrdps2arl -llevels_small.grib2 -ssurface_small.grib2

    echo "Preparing to run HYSPLIT model..."

    # Write CONTROL FILE
    # Careful because the coordinates in the CONTROL FILE
    # are in the order LAT LON, not LON LAT
    CONTROL_FILE="CONTROL"
    # Starting time (Year, month, day, hour)
    echo $(date -u -d $DATE +'%Y %m %d %H') > $CONTROL_FILE
    # Number of starting locations
    echo "1" >> $CONTROL_FILE
    # Starting location (lat lon alt)
    SP1=$(echo -e "$LON $LAT $ALT" | gdaltransform -s_srs EPSG:4326 -t_srs "$EC_SRS")
    SP2="$(echo $SP1 | cut -d " " -f 2) $(echo $SP1 | cut -d " " -f 1)  $(echo $SP1 | cut -d " " -f 3)"
    echo "${SP2}" >> $CONTROL_FILE
    # Number of hours to run
    echo "6" >> $CONTROL_FILE
    # Vertical motion method (0=isentropic, 1=pressure, 2=vertical velocity)
    echo "0" >> $CONTROL_FILE
    # Top of model (in meters AGL)
    echo "15500" >> $CONTROL_FILE
    # Number of meteorological files
    echo "1" >> $CONTROL_FILE
    # Meteorological file paths
    echo "./" >> $CONTROL_FILE
    # Meteorological file names
    echo "DATA.ARL" >> $CONTROL_FILE
    # Output file path
    echo "./" >> $CONTROL_FILE
    # Output file name
    echo "tdump.$DATE" >> $CONTROL_FILE

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
    trajplot -a3 -A1 -f0 -itdump.${DATE} -otmp

    ogr2ogr -t_srs EPSG:4326 -s_srs "$EC_SRS" trajectory_${DATE}.kml tmp_01.kml
    rm tmp_01.kml tmp.ps 

    echo "HYSPLIT model run completed."
}

# ============================================  
# SUB-SCRIPT S: convert Hysplit trajectory to shapefile
# ============================================
run_subscript_S() {
    
    echo "converting Hysplit trajectory to shapefile..."
    ogr2ogr trajectory_20251110.shp trajectory_20251110.kml
    echo "Conversion completed."
}

# ============================================
# MAIN EXECUTION
# ============================================
echo "Starting main script..."

[[ "$RUN_P" == true ]] && run_subscript_P
[[ "$RUN_C" == true ]] && run_subscript_C
[[ "$RUN_T" == true ]] && run_subscript_T
[[ "$RUN_R" == true ]] && run_subscript_R
[[ "$RUN_S" == true ]] && run_subscript_S

echo "Main script finished."
