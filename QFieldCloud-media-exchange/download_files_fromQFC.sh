#!/bin/bash
sudo -u www-data /home/username/qfieldcloud-env/bin/qfieldcloud-cli -u QFC_Username -p your_password -U "https://app.qfield.cloud/api/v1/" download-files d4203b47-c628-9432-b8a5-3c79ef112486 "/srv/data/some_folder/" --filter "media/Example_pcitures/*"
echo "Cron job executed successfully at $(date)"
