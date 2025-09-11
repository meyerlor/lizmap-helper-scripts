#!/bin/bash

# Path to your CSV file
CSV_FILE="users.csv"
# Change to your lizmaps directory!
LIZMAP_DIR="/var/www/YOURDIRECTORY/lizmap"

echo "Starting user creation process..."
echo "=================================="

# Process each user
tail -n +2 "$CSV_FILE" | while IFS=';' read -r benutzerkennung vorname nachname organisation emailadresse; do
    # Skip empty lines
    if [ -z "$emailadresse" ]; then
        continue
    fi
    
    # Convert to lowercase
    username=$(echo "$emailadresse" | cut -d'@' -f1 | tr '[:upper:]' '[:lower:]')
    email_lower=$(echo "$emailadresse" | tr '[:upper:]' '[:lower:]')
    
    echo "Processing: $username ($email_lower)"
    
    # Change to lizmap directory
    cd "$LIZMAP_DIR"
    
    # Show and execute the user creation command
    echo "  -> Executing: php console.php jcommunity:user:create \"$username\" \"$email_lower\""
    php console.php jcommunity:user:create $username $email_lower 2>&1
    
    # Add to group if needed - CHANGE the two occurences of -> GruppeA <- to whatever your group's name on your LWC instance is!
    if [ "$Gruppe" = "*" ]; then
        echo "  -> Executing: php console.php acl2user:addgroup \"$username\" GruppeA"
        php console.php acl2user:addgroup $username GruppeA 2>&1
    fi
    
    echo "  -> Done with $username"
    echo "---"
done

echo "=================================="
echo "Process completed!"