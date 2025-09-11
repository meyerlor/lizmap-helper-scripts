Use with care!

The script will upgrade your instance with one command.

To use, place the script into /var/www/    (this is where my LWC instances are) and call the script like:

sudo -u www-data ./upgrade_lizmap.sh exampleinstance lizmap-web-client-3.9.2.zip

No trailing "/" after exampleinstance  !!
The script will first create a copy of the exampleinstance folder "exampleinstance_backup_TIMESTAMP", so if things go wrong,
just delete "exampleinstance" and rename "exampleinstance_backup_TIMESTAMP" to "exampleinstance".

If you are using modules beside "AltiProfile" you need to add the needed folders
in the "preserve" and "restore" blocks of the script.