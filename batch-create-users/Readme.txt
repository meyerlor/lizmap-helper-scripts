This script creates users in a lizmap database from a CSV file. If you want the users to be added into a
specific group (which must already exist on your lizmap instance!), split your csv into multiple csv's (one per group) - at
moment, the script only checks if the field "Gruppe" is not empty -> if it is not empty it puts the user into the 
group which is hardcoded in the script (change it to the matching group name on your server!)
