#!/bin/bash

# Path to your CSV file
CSV_FILE="users.csv"
LIZMAP_DIR="/var/www/stockach/lizmap"

echo "Starting user creation process..."
echo "=================================="

# Process each user
tail -n +2 "$CSV_FILE" | while IFS=';' read -r benutzerkennung vorname nachname projekt_vg organisation emailadresse; do
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
    
    # Add to group if needed
    if [ "$projekt_vg" = "*" ]; then
        echo "  -> Executing: php console.php acl2user:addgroup \"$username\" verwaltungsgemeinschaft"
        php console.php acl2user:addgroup $username verwaltungsgemeinschaft 2>&1
    fi
    
    echo "  -> Done with $username"
    echo "---"
done

echo "=================================="
echo "Process completed!"