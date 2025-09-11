#!/bin/bash

# Lizmap Instance Update Script
# This script automates the upgrade process for Lizmap instances on Ubuntu

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root or with sudo
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Make sure file permissions are set correctly after upgrade."
    fi
}

# Function to validate paths
validate_path() {
    local path="$1"
    local type="$2"
    
    if [[ ! -e "$path" ]]; then
        print_error "$type path does not exist: $path"
        return 1
    fi
    return 0
}

# Function to create backup
create_backup() {
    local instance_path="$1"
    local backup_dir="${instance_path}_backup_$(date +%Y%m%d_%H%M%S)"
    
    print_status "Creating backup at: $backup_dir"
    cp -r "$instance_path" "$backup_dir"
    
    if [[ $? -eq 0 ]]; then
        print_success "Backup created successfully"
        echo "$backup_dir"
    else
        print_error "Failed to create backup"
        exit 1
    fi
}

# Function to preserve important files/directories
preserve_files() {
    local instance_path="$1"
    local temp_dir="$2"
    
    print_status "Preserving configuration and data files..."
    
    # Create temporary preservation directory
    mkdir -p "$temp_dir/preserved"
    
    # Preserve lizmap configuration
    if [[ -d "$instance_path/lizmap/var/config" ]]; then
        cp -r "$instance_path/lizmap/var/config" "$temp_dir/preserved/"
        print_status "Preserved lizmap configuration"
    fi
    
    # Preserve database
    if [[ -f "$instance_path/lizmap/var/db/jauth.db" ]]; then
        cp "$instance_path/lizmap/var/db/jauth.db" "$temp_dir/preserved/"
        print_status "Preserved authentication database"
    fi
    
    if [[ -f "$instance_path/lizmap/var/db/logs.db" ]]; then
        cp "$instance_path/lizmap/var/db/logs.db" "$temp_dir/preserved/"
        print_status "Preserved logs database"
    fi
    
    # Preserve custom themes if they exist
    if [[ -d "$instance_path/lizmap/www/themes" ]]; then
        cp -r "$instance_path/lizmap/www/themes" "$temp_dir/preserved/"
        print_status "Preserved custom themes"
    fi
    
    # Preserve any custom modifications in www/css or www/js
    if [[ -d "$instance_path/lizmap/www/css" ]]; then
        mkdir -p "$temp_dir/preserved/www"
        cp -r "$instance_path/lizmap/www/css" "$temp_dir/preserved/www/"
        print_status "Preserved custom CSS"
    fi
    
    if [[ -d "$instance_path/lizmap/www/js" ]]; then
        mkdir -p "$temp_dir/preserved/www"
        cp -r "$instance_path/lizmap/www/js" "$temp_dir/preserved/www/"
        print_status "Preserved custom JavaScript"
    fi
    
    if [[ -d "$instance_path/lizmap/www/altiprofil" ]]; then
        mkdir -p "$temp_dir/preserved/www"
        cp -r "$instance_path/lizmap/www/altiprofil" "$temp_dir/preserved/www/"
        print_status "Preserved AltiProfil"
    fi
    
    # Preserve log files
    if [[ -d "$instance_path/lizmap/var/log" ]]; then
        cp -r "$instance_path/lizmap/var/log" "$temp_dir/preserved/"
        print_status "Preserved log files"
    fi
    
    
    # Preserve custom lizmap modules
    if [[ -d "$instance_path/lizmap/lizmap-modules" ]]; then
        cp -r "$instance_path/lizmap/lizmap-modules" "$temp_dir/preserved/"
        print_status "Preserved custom lizmap modules"
    fi
}

# Function to extract new lizmap version
extract_lizmap() {
    local zip_path="$1"
    local temp_dir="$2"
    
    cd "$temp_dir"
    unzip -q "$zip_path" >&2
    
    # Find the extracted directory (it might have version number in name)
    local extracted_dir=$(find . -maxdepth 1 -type d -name "*lizmap*" | head -1)
    
    if [[ -z "$extracted_dir" ]]; then
        print_error "Could not find extracted Lizmap directory" >&2
        exit 1
    fi
    
    # Clean the directory name (remove leading ./)
    extracted_dir=$(basename "$extracted_dir")
    echo "$extracted_dir"
}

# Function to restore preserved files
restore_files() {
    local instance_path="$1"
    local temp_dir="$2"
    
    print_status "Restoring preserved files..."
    
    # Restore configuration
    if [[ -d "$temp_dir/preserved/config" ]]; then
        cp -r "$temp_dir/preserved/config" "$instance_path/lizmap/var/"
        print_status "Restored lizmap configuration"
    fi
    
    # Restore databases
    if [[ -f "$temp_dir/preserved/jauth.db" ]]; then
        cp "$temp_dir/preserved/jauth.db" "$instance_path/lizmap/var/db/"
        print_status "Restored authentication database"
    fi
    
    if [[ -f "$temp_dir/preserved/logs.db" ]]; then
        cp "$temp_dir/preserved/logs.db" "$instance_path/lizmap/var/db/"
        print_status "Restored logs database"
    fi
    
    # Restore themes
    if [[ -d "$temp_dir/preserved/themes" ]]; then
        cp -r "$temp_dir/preserved/themes" "$instance_path/lizmap/www/"
        print_status "Restored custom themes"
    fi
    
    # Restore custom CSS/JS
    if [[ -d "$temp_dir/preserved/www/css" ]]; then
        cp -r "$temp_dir/preserved/www/css" "$instance_path/lizmap/www/"
        print_status "Restored custom CSS"
    fi
    
    if [[ -d "$temp_dir/preserved/www/js" ]]; then
        cp -r "$temp_dir/preserved/www/js" "$instance_path/lizmap/www/"
        print_status "Restored custom JavaScript"
    fi
    
    # Restore logs
    if [[ -d "$temp_dir/preserved/log" ]]; then
        cp -r "$temp_dir/preserved/log" "$instance_path/lizmap/var/"
        print_status "Restored log files"
    fi
    
    # Restore GIS data in install directory
    if [[ -d "$temp_dir/preserved/install" ]]; then
        # Create install directory if it doesn't exist in new version
        mkdir -p "$instance_path/lizmap/install"
        
        # Copy all preserved install subdirectories
        cp -r "$temp_dir/preserved/install"/* "$instance_path/lizmap/install/"
        print_status "Restored GIS data and custom install directories"
    fi
    
    # Restore custom lizmap modules
    if [[ -d "$temp_dir/preserved/lizmap-modules" ]]; then
        # Create lizmap-modules directory if it doesn't exist in new version
        mkdir -p "$instance_path/lizmap/lizmap-modules"
        
        # Copy only if files exist
        shopt -s nullglob
        files=("$temp_dir/preserved/lizmap-modules"/*)
        if [[ ${#files[@]} -gt 0 ]]; then
            cp -r "${files[@]}" "$instance_path/lizmap/lizmap-modules/"
            print_status "Restored custom lizmap modules"
        else
            print_status "Lizmap-modules directory was empty - nothing to restore"
        fi
        shopt -u nullglob
    fi
}

# Function to set proper permissions
set_permissions() {
    local instance_path="$1"
    
    print_status "Setting proper permissions..."
    
    # Set ownership to www-data (common web server user on Ubuntu)
    chown -R www-data:www-data "$instance_path"
    
    # Set directory permissions
    find "$instance_path" -type d -exec chmod 755 {} \;
    
    # Set file permissions
    find "$instance_path" -type f -exec chmod 644 {} \;
    
    # Set specific permissions for lizmap directories
    if [[ -d "$instance_path/lizmap/var" ]]; then
        chmod -R 775 "$instance_path/lizmap/var"
        chown -R www-data:www-data "$instance_path/lizmap/var"
    fi
    
    if [[ -d "$instance_path/lizmap/www" ]]; then
        chmod -R 755 "$instance_path/lizmap/www"
        chown -R www-data:www-data "$instance_path/lizmap/www"
    fi
    
    print_success "Permissions set successfully"
}

# Main upgrade function
main() {
    # Check if correct number of arguments provided
    if [[ $# -ne 2 ]]; then
        print_error "Usage: $0 <instance_name> <zip_filename>"
        print_error "Example: $0 vetter lizmap-web-client-3.9.0-rc.3.zip"
        print_error "Note: Paths are relative to script location (/var/www)"
        exit 1
    fi
    
    # Get script directory (should be /var/www)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Build full paths from relative arguments
    INSTANCE_PATH="$SCRIPT_DIR/$1"
    ZIP_PATH="$SCRIPT_DIR/$2"
    
    # Remove trailing slashes from paths
    INSTANCE_PATH=$(echo "$INSTANCE_PATH" | sed 's:/*$::')
    ZIP_PATH=$(echo "$ZIP_PATH" | sed 's:/*$::')
    
    print_status "Starting Lizmap Upgrade Process"
    print_status "================================"
    print_status "Script location: $SCRIPT_DIR"
    
    # Check permissions
    check_permissions
    
    # Validate inputs
    validate_path "$INSTANCE_PATH" "Instance" || exit 1
    validate_path "$ZIP_PATH" "ZIP file" || exit 1
    
    # Show what will be upgraded
    print_status "Instance to upgrade: $INSTANCE_PATH"
    print_status "Using ZIP file: $ZIP_PATH"
    
    # Confirm before proceeding
    echo ""
    print_warning "This will upgrade the Lizmap instance: $1"
    print_warning "Using the ZIP file: $2"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Upgrade cancelled by user"
        exit 0
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    print_status "Using temporary directory: $TEMP_DIR"
    
    # Create backup
    BACKUP_PATH=$(create_backup "$INSTANCE_PATH")
    
    # Preserve important files
    preserve_files "$INSTANCE_PATH" "$TEMP_DIR"
    
    # Extract new version
    print_status "Extracting new Lizmap version..."
    EXTRACTED_DIR=$(extract_lizmap "$ZIP_PATH" "$TEMP_DIR")
    print_status "Extracted directory: $EXTRACTED_DIR"
    
    # Remove old lizmap directory (keep backup)
    print_status "Removing old Lizmap installation..."
    rm -rf "$INSTANCE_PATH/lizmap"
    
    # Copy new version
    print_status "Installing new Lizmap version..."
    cp -r "$TEMP_DIR/$EXTRACTED_DIR"/* "$INSTANCE_PATH/"
    
    # Restore preserved files
    restore_files "$INSTANCE_PATH" "$TEMP_DIR"
    
    # Set proper permissions
    set_permissions "$INSTANCE_PATH"
    
    # Run Lizmap installer/updater if it exists
    if [[ -f "$INSTANCE_PATH/lizmap/install/installer.php" ]]; then
        print_status "Running Lizmap installer..."
        cd "$INSTANCE_PATH/lizmap/install"
        php installer.php
    fi
    
    # Clean up temporary directory
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    
    # Final status
    echo ""
    print_success "Lizmap upgrade completed successfully!"
    print_success "Backup created at: $BACKUP_PATH"
    print_status "Please test your Lizmap instance and verify everything works correctly."
    print_status "If you encounter issues, you can restore from the backup."
    
    echo ""
    print_status "Recommended next steps:"
    echo "1. Clear your browser cache"
    echo "2. Test the Lizmap interface"
    echo "3. Check the logs for any errors"
    echo "4. Verify your projects are working correctly"
    
    if [[ -f "$INSTANCE_PATH/lizmap/var/log/messages.log" ]]; then
        echo "5. Check Lizmap logs: tail -f $INSTANCE_PATH/lizmap/var/log/messages.log"
    fi
}

# Run main function
main "$@"