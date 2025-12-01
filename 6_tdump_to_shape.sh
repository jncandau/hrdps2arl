#!/bin/bash

# Define input file name (HYSPLIT tdump output)
INPUT_TDUMP=$1

# Define output shapefile base name
OUTPUT_SHP_BASE=$2

# --- HYSPLIT Conversion Steps ---

# 1. Run trajplot.exe to generate ESRI Generate format ASCII files
#    -a3 option: 3 for Google Earth (KMZ), but a better option for shapefile prep is often -a1 (ESRI Generate) for the next step.
#    Note: The documentation suggests that trajplot -a1 creates GIS_*.txt files for conversion. 
#    The modern GUI option "GIS to Shapefile" uses intermediate files.
#    A more direct command line approach uses the ascii2shp utility.
#    Let's use the method from the HYSPLIT forum which uses the ascii2shp utility directly.

# First, ensure the tdump file is standard (optional, but good practice)
# hyts_std.exe is used in some examples to ensure standardized output
# ./hyts_std.exe

# 2. Run trajplot.exe with the option to create the GIS output files in 'generate' format
# The option -a1 generates GIS_traj_ps_*.txt and GIS_traj_ps_*.att files
trajplot -i${INPUT_TDUMP} -a1 -o${OUTPUT_SHP_BASE}

# The above command generates files like GIS_traj_ps_01.txt and GIS_traj_ps_01.att in the working directory

# 3. Convert the generated ASCII files to the binary shapefile format using ascii2shp.exe
# The input file is redirected using '<'
ascii2shp -i ${OUTPUT_SHP_BASE} lines < GIS_traj_ps_01.txt

# 4. Create the required .dbf attribute file from the .att file
# This utility creates a DBF file from a comma-delimited text file
# Options -C specify column types, -d specify delimiters
txt2dbf -C7 -C9 -C5 -C9 -d, -d, -d, GIS_traj_ps_01.att trajplot.dbf

echo "Shapefiles created: $2.shp, $2.shx, $2.dbf"

