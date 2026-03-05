#!/bin/bash

# Script to convert 3D trajectory CSV to shapefile
# Usage: ./csv_to_shapefile.sh input.csv output_shapefile

# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_csv> <output_shapefile_name>"
    echo "Example: $0 trajectories.csv output_trajectories"
    exit 1
fi

INPUT_CSV="$1"
OUTPUT_SHP="$2"

# Define the custom projection
CUSTOM_PROJ="+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs"

# Check if input file exists
if [ ! -f "$INPUT_CSV" ]; then
    echo "Error: Input file '$INPUT_CSV' not found!"
    exit 1
fi

# Check if GDAL/OGR is installed
if ! command -v ogr2ogr &> /dev/null; then
    echo "Error: ogr2ogr (GDAL) is not installed."
    echo "Please install it with: sudo apt-get install gdal-bin"
    exit 1
fi

echo "Converting CSV to shapefile..."
echo "Using custom oblique transformation projection"

echo "ID,longitude,latitude,altitude" > tmp.csv
HEADER_LINES=$(grep -n "PRESSURE" $INPUT_CSV | cut -d ":" -f 1)
tail -n +$((HEADER_LINES + 1)) $INPUT_CSV | awk '{print $1, $9, $11, $10, $12}' | sort -k1,1n -k2,2n | awk '{print $1, $3, $4, $5}' | sed -e 's/ /,/g' >> tmp.csv
INPUT_CSV="tmp.csv"

# Create VRT (Virtual Format) file to define the CSV structure
VRT_FILE="${INPUT_CSV%.csv}.vrt"

cat > "$VRT_FILE" << EOF
<OGRVRTDataSource>
    <OGRVRTLayer name="trajectories">
        <SrcDataSource>$INPUT_CSV</SrcDataSource>
	<SrcLayer>${INPUT_CSV%.csv}</SrcLayer>
        <GeometryType>wkbLineString25D</GeometryType>
        <LayerSRS>EPSG:4326</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="longitude" y="latitude" z="altitude"/>
        <Field name="ID" type="String"/>
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF

echo "Created VRT file: $VRT_FILE"

cat $VRT_FILE

# First, create points from the CSV
POINTS_SHP="${OUTPUT_SHP}_points"
ogr2ogr -f "ESRI Shapefile" "$POINTS_SHP.shp" "$VRT_FILE"

if [ $? -ne 0 ]; then
    echo "Error: Failed to create point shapefile"
    rm -f "$VRT_FILE"
    exit 1
fi

echo "Created point shapefile: ${POINTS_SHP}.shp"

# Now convert points to lines grouped by ID using SQL
ogr2ogr -f "ESRI Shapefile" "${OUTPUT_SHP}.shp" "${POINTS_SHP}.shp" \
    -dialect sqlite \
    -sql "SELECT ID, ST_MakeLine(geometry) as geometry FROM ${OUTPUT_SHP}_points GROUP BY ID"

if [ $? -eq 0 ]; then
    echo "Success! Created trajectory shapefile: ${OUTPUT_SHP}.shp"
    
    # Clean up temporary files
    rm -f "$VRT_FILE"
    rm -f "${POINTS_SHP}."*
    
    echo "Cleaned up temporary files"
else
    echo "Error: Failed to create trajectory lines"
    rm -f "$VRT_FILE"
    exit 1
fi

echo "Done!"
