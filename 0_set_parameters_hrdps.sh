#!/usr/bin/env bash

RUN_DATE=2025-11-11
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

PLVLS=(1015 1000 985 970 950 925 900 850 800 750 700 650 600 550 500 450 400 350 300 275 250 225 200 150 100 50)

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

