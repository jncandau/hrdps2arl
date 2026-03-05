#!/bin/bash

HEADER_LINES=$(grep -n "PRESSURE" $1 | cut -d ":" -f 1)

NTRAJ=$(tail -n +$((HEADER_LINES + 1)) $1 | awk '{print $1}' | sort | uniq | wc -l)

for (( i = 1; i <= $NTRAJ; i++ )); do
 rm tmp.csv tmp.vrt
 tail -n +$((HEADER_LINES + 1)) $1 | awk '{print $1, $9, $11, $10, $12}' | awk -v NT="$i" '$1 == NT' | sort -n -k 2,2 | awk '{print $3, $4, $5}' | sed -e 's/ /,/g' > tmp.csv
 cat <<EOF > tmp.vrt
    <OGRVRTDataSource>
    <OGRVRTLayer name="$(basename "$INPUT_FILE" .csv)">
        <SrcDataSource>$INPUT_FILE</SrcDataSource>
        <GeometryType>wkbPoint25D</GeometryType>
        <LayerSRS>$SOURCE_CRS</LayerSRS>
        <GeometryField encoding="PointFromColumns" x="$X_COL" y="$Y_COL" z="$Z_COL"/>
    </OGRVRTLayer>
</OGRVRTDataSource>
EOF

done



# echo $HEADER_LINES

# OUTPUT_SHP="${1}.shp"

# echo $OUTPUT_SHP

# Create CSV with WKT for each trajectory
#echo "WKT,traj_id" > temp_lines.csv

# Get unique trajectory numbers and create a line for each
#tail -n +$((HEADER_LINES + 1)) $1 | \
#    awk '{print $1, $11, $10}' | \
#    awk '
#    {
#        traj[$1] = traj[$1] sprintf("%s %s,", $2, $3)
#    }
#    END {
#        for (t in traj) {
#            gsub(/,$/, "", traj[t])
#            print "\"LINESTRING(" traj[t] ")\"," t
#        }
#    }' >> temp_lines.csv

# ogr2ogr -f "ESRI Shapefile" temp_lines.shp temp_lines.csv -a_srs "+proj=ob_tran +o_proj=longlat +o_lon_p=0 +o_lat_p=36.08852 +lon_0=-114.694858 +R=6371229 +no_defs"

# ogr2ogr -t_srs EPSG:4326 $OUTPUT_SHP temp_lines.shp


# rm temp_lines.csv temp_lines.shp

# echo "Created $OUTPUT_SHP"
