# hrdps2arl
Conversion of Environment Canada's HRDPS meteorological data to a HYSPLIT (ARL) format

## Requirements

- Hysplit
- Bash to run the scripts

## Installation

```bash
# clone
git clone https://github.com/jncandau/hrdps2arl.git
```

## Characteristics of HRDPS Meteorological data

The operational High Resolution Deterministic Prediction System (HRDPS) is produced by Environment Canada, 4-times a day at a 2.5km horizontal resolution and 31 vertical levels over Canada and the northern USA. The data for the past month is available here: https://dd.weather.gc.ca/. Historical data since 2015-04-23 have to be ordered directly from Environment Canada.

HRDPS has some characteristics that affect the conversion to HYSPLIT format, how the CONTROL file should be written and Hysplit results themselves.

Reference for HRDPS:
Milbrandt, J. A., Bélair, S., Faucher, M., Vallée, M., Carrera, M. L., & Glazer, A. (2016). The pan-Canadian high resolution (2.5 km) deterministic
prediction system. Weather and Forecasting, 31(6), 1791-1816 (https://doi.org/10.1175/WAF-D-16-0035.1)

### Projection and extent

Natively, HRDPS is in a rotated latlong projection. More precisely: '+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs'. We chose to keep the data in their original projection do avoid having to interpolate in a re-projection and potentially reduce accuracy. As a result, **Hysplit results obtained using HRDPS are in the same rotated lat-lon projection as the meteorological data**. According to Chris Loughner, running Hysplit on HRDPS's rotated lat-lon is not a problem as long as we have downwelling shortwave radiation (DSWF) in the ARL file to prevent HYSPLIT from calculating it based on the sun angle at a lat lon position. Luckily, HRDPS provides a downward shortwave flux. Because all the Hysplit calculations are in native HRDPS projection, the results (e.g., trajectories) have to be re-projected if they need to be in regular lat-lon.

The extent of HRDPS data in regulat lat-lon is: 
- Latitude: -152.7685 to -40.6938
- Longitude: 27.2840 to 70.6164

HRDPS rasters can be clipped to a specific bounding box given in regular lat-lon using gdal: 
gdalwarp -te xmin ymin xmax ymax -te_srs EPSG:4326 input.grib2 output.grib2
For example, for Eastern Canada:
gdalwarp -te -95 43 -50 55 -te_srs EPSG:4326 input.grib2 output.grib2 

Clipping can be combined with re-projection to regulat lat-long using:
gdalwarp -te xmin ymin xmax ymax -te_srs EPSG:4326 -r bilinear -t_srs "EPSG:4326" input.grib2 output.grib2

### Variables

The list of HRDPS variables available for download is given here:  https://eccc-msc.github.io/open-data/msc-data/nwp_hrdps/readme_hrdps-datamart_en/

We have identified all the variables suitable as input to Hysplit and mapped them to the corresponding Hysplit variables:
    3D Variables:
      gh    -> HGTS  : Geopotential height (gpm)
      t     -> TEMP  : Temperature (K)
      u     -> UWND  : U-wind component (m/s)
      v     -> VWND  : V-wind component (m/s)
      w     -> WWND  : Omega (Pa/s -> hPa/s, factor 0.01)
      r     -> RELH  : Relative humidity (%)
      q     -> SPHU  : Specific humidity (kg/kg)
 
    2D Variables:
      prmsl -> MSLP  : Mean sea level pressure (Pa -> hPa, factor 0.01)
      10u   -> U10M  : 10m U-wind (m/s)
      10v   -> V10M  : 10m V-wind (m/s)
      2t    -> T02M  : 2m temperature (K)
      blh   -> PBLH  : Boundary layer height (m)
      sp    -> PRSS  : Surface pressure (Pa -> hPa, factor 0.01)
      ishf  -> SHTF  : Sensible heat flux (W/m2)
      ssrd  -> DSWF  : Downward shortwave flux (W/m2)
      2r    -> RH2M  : 2m relative humidity (%)
      2sh   -> SPH2  : 2m specific humidity (kg/kg)
      h     -> SHGT  : Surface orography (m)
      cape  -> CAPE  : Convective available potential energy (W/m2)
      prate -> TPP1  : Total precip (1h) (kg/(m2*s) -> m factor 3.6)
      tcc   -> TCLD  : Total cloud cover (%)
      lhtfl -> LTHF  : Latent heat flux (W/m2)

There are a couple of differences in units between HRDPS and Hysplit variables that required a conversion factor:
    - Pressure variables are in Pa in HRDPS are multiplied by 0.01 to convert to hPa in Hysplit
    - Precipitation is in kg/(m2*s) in HRDPS are multiplied by 3.6 to convert to m in Hsyplit

Note that two variables, SHGT and CAPE, are never available at the 000 forecast hour. It is not a problem if the 000 forecast hour is not used as suggested in the next section.

### Dealing with the 000 forecast hour

Several exchanges with Environment Canada colleagues suggest that it is better to use the 006 forecast hour of the previous run time than the 000 forecast hour of the current one. In addition, as mentioned above, the 000 forecast hour does not have all the variables. 

Considering this, **we suggest not using the 000 forecast hour** replacing it with the 006 forecast hour of the previous run time.

### Workflow to use Hysplit with HRDPS

1- Download the grib2 files of selected variables from https://dd.weather.gc.ca/ or request data from Environment Canada. For a single day, from 00:00 to 00:00 the next day, the highest accuracy is achieved by downloading the 006 forecast hour of the 18:00 run time of the previous day to cover the 00:00 hour and then the 001 to 006 forecast hours for each run time (00, 06, 12 and 18) that day. A simpler but less accurate option is to downloading the 006 forecast hour of the 18:00 run time of the previous day to cover the 00:00 hour and then the 001 to 023 forecast hour of the 00:00 run time that day.  

2- If possible, clip the grib files to area of interest to reduce the size of the final dataset

3- Generate a surface and a levels grib file by concatenating the respective grib files

4- Sort surface and level grib files by validityDate and validityTime using the ECCODES command: 
    grib_copy -B "validityDate:i asc, validityTime:i asc, level:i asc" output.grib2 input.grib2
    
    It is critical that the time slices in the grib files are equally spaced (e.g, every hour). If not, Hysplit will crash. This can be checked with the following command:
    grib_ls -p validityDate,validityTime -B validityDate,validityTime:i 20251203_HRDPS_surface.grib2 | uniq

5- Convert the surface and levels grib files to Hysplit format using hrdps2arl:
    hrdps2arl -llevel.grib2 -ssurface.grib2

6- Run Hysplit using the resulting ARL file

7- Re-project the trajectory coordinates to regular lat-lon if required.

