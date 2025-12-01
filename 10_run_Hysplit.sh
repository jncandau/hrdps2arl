#!/usr/bin/env bash
#
#
source /home/jcandau/scratch/Test4/0_set_parameters_hrdps.sh

CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)

# Download met data
echo "Downloading met files..."
source ./1_download_hrdps.sh

# Create the grib file for the day
if [[ ! -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2 || ! -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2 ]]; then
   echo "Creating daily gribs"
   source /home/jcandau/scratch/Test4/3_create_daily_gribs.sh
else
   echo "Daily gribs alread present"
fi

# Trim the daily grib files and convert to ARL
cd $WORKDIR/arl
if [[ ! -f DATA.ARL ]]; then

   # Calculate the bounding box for trimming
   UL_LON=$(($LON - 5))
   UL_LAT=$(($LAT + 5))
   LR_LON=$(($LON + 5))
   LR_LAT=$(($LAT - 5))

   cd $WORKDIR/arl
   if [ $REPROJECT -eq 0 ]; then
      #Calculate the bounding box for the trim
      UL=$(echo -e "$UL_LON $UL_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
      LR=$(echo -e "$LR_LON $LR_LAT" | gdaltransform -output_xy -s_srs EPSG:4326 -t_srs "$EC_SRS")
      echo "Trimming daily gribs"
      gdal_translate -projwin $UL $LR ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2 surface_small.grib2
      gdal_translate -projwin $UL $LR ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2 levels_small.grib2
      echo "Converting to ARL format"
      hrdps2arl -ilevels_small.grib2 -asurface_small.grib2
   else
      echo "Trimming daily gribs"
      gdal_translate -projwin $UL_LON $UL_LAT $LR_LON $LR_LAT ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2 surface_small_ll.grib2
      gdal_translate -projwin $UL_LON $UL_LAT $LR_LON $LR_LAT ${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2 levels_small_ll.grib2
      echo "Converting to ARL format"
      hrdps2arl -ilevels_small_ll.grib2 -asurface_small_ll.grib2
   fi
else
   echo "DATA.ARL is already present"
fi

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
echo "KMSL=0," >> $SETUP_FILE
echo "/" >> $SETUP_FILE

# Copy ASCDATA.CFG
cp /home/jcandau/software/hysplit.v5.4.2.source/testing/ASCDATA.CFG .

# Run Hysplit
hyts_std

# Convert tdump to csv
#awk 'NR>5 {print $10","$11","$12}' tdump.$CYCLE > trajectory.csv
# Add header
#echo "lat,lon,height" | cat - trajectory.csv > temp && mv temp trajectory.csv
# Reproject to EPSG:4326 if required
if [[ $REPROJECT -eq 0 ]]; then
        trajplot -a3 -itdump.${CYCLE} -otmp
	#ogr2ogr -f KML tmp.kml trajectory.csv -oo X_POSSIBLE_NAMES=lon -oo Y_POSSIBLE_NAMES=lat -oo Z_POSSIBLE_NAMES=height
	ogr2ogr -t_srs EPSG:4326 -s_srs "$EC_SRS" trajectory_${CYCLE}.kml tmp_01.kml
	rm tmp*
else
        trajplot -a3 -A1 -itdump.20251115 -otmp
	mv tmp_01.kml trajectory_${CYCLE}.kml
	rm tmp*
        #ogr2ogr -f 'ESRI Shapefile' trajectory_${CYCLE}.shp trajectory.csv -oo X_POSSIBLE_NAMES=lon -oo Y_POSSIBLE_NAMES=lat -oo Z_POSSIBLE_NAMES=height
fi
