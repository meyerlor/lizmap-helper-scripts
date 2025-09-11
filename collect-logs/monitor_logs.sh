#!/bin/bash

# Log Monitor Script for Lizmap/QGIS Server Debugging
# Monitors all relevant logs during load testing

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="/tmp/lizmap_debug_logs_${TIMESTAMP}"
DURATION=${1:-300}  # Default 5 minutes

echo "=== Lizmap/QGIS Server Log Monitor ==="
echo "Monitoring logs for ${DURATION} seconds..."
echo "Logs will be saved to: ${LOG_DIR}"
echo "Press Ctrl+C to stop monitoring"
echo "========================================="

# Create log directory
mkdir -p "${LOG_DIR}"

# Function to cleanup background processes
cleanup() {
    echo "Stopping log monitoring..."
    jobs -p | xargs -r kill
    echo "Log files saved in: ${LOG_DIR}"
    echo "Summary:"
    ls -la "${LOG_DIR}/"
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM

# Start monitoring various logs in background

# 1. QGIS Server logs
echo "Starting QGIS Server log monitoring..."
sudo tail -f /var/log/qgis/qgis-server.log > "${LOG_DIR}/qgis-server.log" 2>&1 &

# 2. QGIS Service systemd logs
echo "Starting QGIS systemd log monitoring..."
sudo journalctl -u qgis.service -f > "${LOG_DIR}/qgis-systemd.log" 2>&1 &

# 3. Nginx access logs (all virtual hosts)
echo "Starting Nginx access log monitoring..."
sudo tail -f /var/log/nginx/access.log > "${LOG_DIR}/nginx-access.log" 2>&1 &

# 4. Nginx error logs
echo "Starting Nginx error log monitoring..."
sudo tail -f /var/log/nginx/error.log > "${LOG_DIR}/nginx-error.log" 2>&1 &

# 5. System resource monitoring
echo "Starting system resource monitoring..."
{
    echo "=== System Resource Monitor ==="
    echo "Timestamp,CPU_Usage,Memory_Usage,Load_1min,Load_5min,Load_15min,QGIS_Processes,QGIS_Memory_MB"
    while true; do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        memory_usage=$(free | grep Mem | awk '{printf("%.1f", ($3/$2) * 100.0)}')
        load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')
        load_1min=$(echo $load_avg | cut -d',' -f1 | xargs)
        load_5min=$(echo $load_avg | cut -d',' -f2 | xargs)
        load_15min=$(echo $load_avg | cut -d',' -f3 | xargs)
        
        # Count QGIS processes and their memory usage
        qgis_processes=$(ps aux | grep qgisserver | grep -v grep | wc -l)
        qgis_memory=$(ps aux | grep qgisserver | grep -v grep | awk '{sum += $6} END {printf("%.0f", sum/1024)}')
        
        echo "${timestamp},${cpu_usage},${memory_usage},${load_1min},${load_5min},${load_15min},${qgis_processes},${qgis_memory}"
        sleep 5
    done
} > "${LOG_DIR}/system-resources.csv" 2>&1 &

# 6. QGIS process monitoring
echo "Starting QGIS process monitoring..."
{
    echo "=== QGIS Process Monitor ==="
    while true; do
        echo "=== $(date) ==="
        ps aux | grep qgisserver | grep -v grep
        echo ""
        sleep 10
    done
} > "${LOG_DIR}/qgis-processes.log" 2>&1 &

# 7. Network connection monitoring on port 7200
echo "Starting network connection monitoring..."
{
    echo "=== Network Connections Monitor (Port 7200) ==="
    while true; do
        echo "=== $(date) ==="
        sudo netstat -tulpn | grep 7200
        echo "Active connections:"
        sudo ss -tupln | grep 7200
        echo ""
        sleep 10
    done
} > "${LOG_DIR}/network-connections.log" 2>&1 &

# 8. Disk I/O monitoring
echo "Starting disk I/O monitoring..."
{
    echo "=== Disk I/O Monitor ==="
    while true; do
        echo "=== $(date) ==="
        iostat -x 1 1 | grep -E "(Device|srv|sda|sdb|nvme)"
        echo ""
        sleep 30
    done
} > "${LOG_DIR}/disk-io.log" 2>&1 &

# 9. Monitor specific Lizmap error logs (if they exist)
if [ -d "/var/www" ]; then
    echo "Starting Lizmap application log monitoring..."
    {
        find /var/www -name "*.log" -path "*/temp/lizmap/*" 2>/dev/null | while read logfile; do
            if [ -f "$logfile" ]; then
                echo "=== Monitoring: $logfile ==="
                tail -f "$logfile" 2>/dev/null &
            fi
        done
        wait
    } > "${LOG_DIR}/lizmap-app.log" 2>&1 &
fi

# 10. PHP-FPM logs (if available)
if [ -f "/var/log/php8.3-fpm.log" ]; then
    echo "Starting PHP-FPM log monitoring..."
    sudo tail -f /var/log/php8.3-fpm.log > "${LOG_DIR}/php-fpm.log" 2>&1 &
elif [ -f "/var/log/php8.2-fpm.log" ]; then
    echo "Starting PHP-FPM log monitoring..."
    sudo tail -f /var/log/php8.2-fpm.log > "${LOG_DIR}/php-fpm.log" 2>&1 &
fi

# Create a summary script for later analysis
cat > "${LOG_DIR}/analyze_logs.sh" << 'EOF'
#!/bin/bash
echo "=== Log Analysis Summary ==="
echo "Directory: $(pwd)"
echo "Files:"
ls -la

echo -e "\n=== QGIS Server Error Count ==="
if [ -f "qgis-server.log" ]; then
    grep -i error qgis-server.log | wc -l
    echo "Sample errors:"
    grep -i error qgis-server.log | head -5
fi

echo -e "\n=== Nginx 504 Errors ==="
if [ -f "nginx-access.log" ]; then
    grep " 504 " nginx-access.log | wc -l
    echo "Sample 504 errors:"
    grep " 504 " nginx-access.log | head -5
fi

echo -e "\n=== System Resource Peaks ==="
if [ -f "system-resources.csv" ]; then
    echo "Peak CPU usage:"
    tail -n +2 system-resources.csv | sort -t',' -k2 -nr | head -1
    echo "Peak Memory usage:"
    tail -n +2 system-resources.csv | sort -t',' -k3 -nr | head -1
    echo "Peak QGIS Memory usage:"
    tail -n +2 system-resources.csv | sort -t',' -k8 -nr | head -1
fi

echo -e "\n=== Time Analysis ==="
echo "Log monitoring started: $(head -1 system-resources.csv 2>/dev/null | cut -d',' -f1)"
echo "Log monitoring ended: $(tail -1 system-resources.csv 2>/dev/null | cut -d',' -f1)"
EOF

chmod +x "${LOG_DIR}/analyze_logs.sh"

echo "Log monitoring started. Background processes running:"
jobs -l

# Run for specified duration or until interrupted
if [ "$DURATION" != "0" ]; then
    sleep "$DURATION"
    cleanup
else
    # Run indefinitely until Ctrl+C
    while true; do
        sleep 60
        echo "Still monitoring... ($(date))"
    done
fi