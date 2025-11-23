#!/usr/bin/env bash

RUN_DATE=2025-11-15
# We use the hourly predictions at noon every day
RUN_TIME=12 # cycle (UTC)
FH_BEG=0           # first forecast hour
FH_END=0          # last forecast hour to convert
OUTROOT=HRDPS_$(date -u -d $RUN_DATE +%Y%m%d%H)
WORKDIR=$PWD/$OUTROOT

PLVLS=(1015 1000 985 970 950 925 900 850 800 750 700 650 600 550 500 450 400 350 300 275 250 225 200 150 100 50)

PL_VARS=(TMP UGRD VGRD RH VVEL HGT SPFH)    # temperature, wind, humidity, omega, height
#SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFP_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m" "CAPE_Sfc" "TCDC_Sfc")
# Here I am removing CAPE and TCDC because I can't find a way to set the shortName for these two using grib_set. When I try to change the shortName
# it also changes the levelOf(something) and I can't seem to be able to correct that
SFC_VARS=("PRMSL_MSL" "UGRD_AGL-10m" "VGRD_AGL-10m" "TMP_AGL-2m" "HPBL_Sfc" "PRES_Sfc" "SHTFL_Sfc" "LHTFP_Sfc" "DSWRF_Sfc" "RH_AGL-2m" "SPFH_AGL-2m")

# Decide if we reproject the gribs from rotated latlong to regular latlong
REPROJECT=0

