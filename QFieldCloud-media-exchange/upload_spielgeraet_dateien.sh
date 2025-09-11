#!/bin/bash
# Define the directories and filters
UPLOAD_DIR="/srv/data/rielasingen-worblingen/master"
FILTER_1="media/Spielgerät_Fotos/*"
FILTER_2="media/Spielgerät_Dokumente/*"

# Get the current timestamp minus 22 hours
TIME_22H_AGO=$(date -d '22 hours ago' +"%Y-%m-%d %H:%M:%S")

# Find files modified in the last 24 hours for both directories
FILES_TO_UPLOAD_1=$(find "$UPLOAD_DIR" -type f -newermt "$TIME_22H_AGO" -name "*.*")

# Upload files if there are any found
if [ -n "$FILES_TO_UPLOAD_1" ]; then
    # Upload files in media/Spielgerät_Fotos
    sudo -u www-data /home/gisadmin/qfieldcloud-env/bin/qfieldcloud-cli -u meyerlor -p KleinUndLeber2601 -U "https://qfieldcloud.gisgeometer.de/api/v1/" upload-files d4203b47-c628-4ea7-b8a5-3c79ef112486 "$UPLOAD_DIR" --filter "$FILTER_1"
fi

if [ -n "$FILES_TO_UPLOAD_2" ]; then
    # Upload files in media/Spielgerät_Dokumente
    sudo -u www-data /home/gisadmin/qfieldcloud-env/bin/qfieldcloud-cli -u meyerlor -p KleinUndLeber2601 -U "https://qfieldcloud.gisgeometer.de/api/v1/" upload-files d4203b47-c628-4ea7-b8a5-3c79ef112486 "$UPLOAD_DIR" --filter "$FILTER_2"
fi


