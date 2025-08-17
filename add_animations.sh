#!/bin/bash

# This script will add animations to sleep commands in the full_book_generator.sh script

# Make a backup
cp full_book_generator.sh full_book_generator.sh.bak

# Replace sleep 5 in the plagiarism check function with snake_spinner
sed -i '' '167s/sleep 5 # Add delay between retries/snake_spinner 5 "Preparing retry attempt"/' full_book_generator.sh

# Replace sleep 5 in the rewrite chapter function with radar_spinner
sed -i '' '376s/sleep 5 # Add delay between retries/radar_spinner 5 "Preparing retry attempt"/' full_book_generator.sh

# Replace sleep 3 in the detailed analysis function with bouncing_bar
sed -i '' '507s/sleep 3/bouncing_bar 3 "Preparing for retry"/' full_book_generator.sh

# Replace sleep 2 in the outline review step with rainbow_text
sed -i '' '1344s/sleep 2/rainbow_text 2 "Preparing review step"/' full_book_generator.sh

# Replace sleep 2 in the final draft step with loading_dots
sed -i '' '1391s/sleep 2/loading_dots 2 "Preparing final draft"/' full_book_generator.sh

echo "Animations added to all applicable sleep commands!"
