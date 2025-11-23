#!/usr/bin/env bash

source ./0_set_parameters_hrdps.sh

CYCLE=$(date -u -d $RUN_DATE +%Y%m%d)

SEARCH_STRING="_ll.grib2"

if [ $REPROJECT -eq 0 ]; then
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2
   cd $WORKDIR/levels
   find . -type f ! -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_levels.grib2
   # Sort the resulting grids by date and time
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_levels.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels.grib2
   rm $WORKDIR/arl/temp_levels.grib2
   cd $WORKDIR/surface
   find . -type f ! -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface.grib2
else
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2
   rm -f $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2
   cd $WORKDIR/levels
   find . -type f -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/temp_levels_ll.grib2
   grib_copy -B "date:i asc, stepRange:i asc, level:i asc" $WORKDIR/arl/temp_levels_ll.grib2 $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_levels_ll.grib2
   rm $WORKDIR/arl/temp_levels_ll.grib2
   cd $WORKDIR/surface
   find . -type f -name "*_ll.grib2" -exec cat {} + > $WORKDIR/arl/${CYCLE}T${RUN_TIME}_${FH_BEG}_${FH_END}_HRDPS_surface_ll.grib2
fi



