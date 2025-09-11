This script will create all logs which could possibly have anything to do with your LWC for a set duration (default is 5min).
Call the script like: ./monitor_logs.sh 60    if you want to collect the logs for only 60s.
The Logs will end up in:  /tmp/lizmap_debug_logs_TIMESTAMP

Following logs will be collected:
1. QGIS Server logs
2. QGIS Service systemd logs
3. Nginx access logs (all virtual hosts)
4. Nginx error logs
5. System resource monitoring
6. QGIS process monitoring
7. Network connection monitoring on port 7200 (default py-qgis-server port)
8. Disk I/O monitoring
9. Monitor specific Lizmap error logs (won't work if you log into Postgres)
10. PHP-FPM logs (if available, you might need to change the script's code to match your php version (script covers php8.2 and php 8.3)

The script will create a analyze_logs.sh script in the log folder which helps you to analyze the collected logs (WIP!)

Strg+C will abort log collection!