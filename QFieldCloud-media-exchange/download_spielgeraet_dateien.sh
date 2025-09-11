#!/bin/bash
sudo -u www-data /home/gisadmin/qfieldcloud-env/bin/qfieldcloud-cli -u meyerlor -p KleinUndLeber2601 -U "https://qfieldcloud.gisgeometer.de/api/v1/" download-files d4203b47-c628-4ea7-b8a5-3c79ef112486 "/srv/data/rielasingen-worblingen/master" --filter "media/Spielgerät_Fotos/*"
sudo -u www-data /home/gisadmin/qfieldcloud-env/bin/qfieldcloud-cli -u meyerlor -p KleinUndLeber2601 -U "https://qfieldcloud.gisgeometer.de/api/v1/" download-files d4203b47-c628-4ea7-b8a5-3c79ef112486 "/srv/data/rielasingen-worblingen/master" --filter "media/Spielgerät_Dokumente/*" 
sudo -u www-data /home/gisadmin/qfieldcloud-env/bin/qfieldcloud-cli -u meyerlor -p KleinUndLeber2601 -U "https://qfieldcloud.gisgeometer.de/api/v1/" download-files e056c1db-b53f-46d3-900e-de8053b3f3cc "/srv/data/rielasingen-worblingen/master" --filter "media/Punkte/*" 
echo "Cron job executed successfully at $(date)"
