#!/bin/bash

# Migrate loose book files to organized directory structure
# This script organizes all loose book_outline files into proper book directories

set -e

echo "🔧 Starting book outputs migration..."
echo "📁 Analyzing existing book files..."

BOOK_OUTPUTS_DIR="./book_outputs"

if [ ! -d "$BOOK_OUTPUTS_DIR" ]; then
    echo "❌ Error: book_outputs directory not found"
    exit 1
fi

cd "$BOOK_OUTPUTS_DIR"

# Function to sanitize book title for use as folder name
sanitize_book_title() {
    local topic="$1"
    
    # Convert to lowercase, remove apostrophes, then replace non-alphanumeric with dashes
    echo "$topic" | tr '[:upper:]' '[:lower:]' | \
                   sed "s/'//g" | \
                   sed 's/[^a-z0-9 ]/-/g' | \
                   sed 's/[[:space:]]\+/-/g' | \
                   sed 's/-\{2,\}/-/g' | \
                   sed 's/^-*//g' | \
                   sed 's/-*$//g' | \
                   cut -c1-50
}

# Function to extract book title from outline file
extract_book_title() {
    local file="$1"
    
    # Try to find the book title in the first few lines
    # Look for lines that contain "Title:" or start with "# " or "## "
    local title=""
    
    # Try different patterns to extract title
    title=$(head -n 20 "$file" | grep -i "^title:" | head -1 | sed 's/^[Tt]itle:[[:space:]]*//' | sed 's/[*#]*//g' | xargs)
    
    if [ -z "$title" ]; then
        title=$(head -n 20 "$file" | grep "^# " | head -1 | sed 's/^# *//' | sed 's/[*#]*//g' | xargs)
    fi
    
    if [ -z "$title" ]; then
        title=$(head -n 20 "$file" | grep "^## " | head -1 | sed 's/^## *//' | sed 's/[*#]*//g' | xargs)
    fi
    
    if [ -z "$title" ]; then
        # Fallback: use first substantial line
        title=$(head -n 10 "$file" | grep -v "^$" | grep -v "^---" | head -1 | sed 's/[*#]*//g' | xargs)
    fi
    
    if [ -z "$title" ]; then
        # Final fallback: use filename
        title=$(basename "$file" .md | sed 's/book_outline_//' | sed 's/_[0-9]*$//')
    fi
    
    echo "$title"
}

# Function to extract timestamp from filename
extract_timestamp() {
    local file="$1"
    echo "$file" | grep -o '[0-9]\{8\}_[0-9]\{6\}' | head -1
}

echo "📖 Processing loose outline files..."

# Process all loose outline files and group them by timestamp
for file in book_outline_*.md; do
    if [ -f "$file" ]; then
        echo "   Processing: $file"
        
        title=$(extract_book_title "$file")
        timestamp=$(extract_timestamp "$file")
        
        if [ -n "$title" ] && [ -n "$timestamp" ]; then
            sanitized_title=$(sanitize_book_title "$title")
            dir_name="${sanitized_title}-${timestamp}"
            
            echo "     📝 Title: $title"
            echo "     📁 Folder: $dir_name"
            echo "     ⏰ Timestamp: $timestamp"
            
            # Create directory if it doesn't exist
            if [ ! -d "$dir_name" ]; then
                echo "     📂 Creating directory: $dir_name"
                mkdir -p "$dir_name"
            fi
            
            # Determine the target filename based on the original filename
            if [[ "$file" == book_outline_reviewed_* ]]; then
                target_name="book_outline_reviewed.md"
            elif [[ "$file" == book_outline_final_* ]]; then
                target_name="book_outline_final.md"
            else
                target_name="book_outline.md"
            fi
            
            echo "     📄 Moving $file -> $dir_name/$target_name"
            mv "$file" "$dir_name/$target_name"
            
        else
            echo "     ⚠️  Could not extract title or timestamp from $file"
            # Create a fallback directory
            fallback_dir="unknown-book-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$fallback_dir"
            echo "     📄 Moving $file -> $fallback_dir/book_outline.md"
            mv "$file" "$fallback_dir/book_outline.md"
        fi
        echo ""
    fi
done

echo ""
echo "✅ Migration completed!"
echo "📊 Summary:"

# Count directories created
dir_count=$(ls -d */ 2>/dev/null | wc -l)
echo "   📁 Total book directories: $dir_count"
echo "   📂 Directory structure:"

# List all directories
for dir in */; do
    if [ -d "$dir" ]; then
        file_count=$(ls -1 "$dir"*.md 2>/dev/null | wc -l)
        echo "     📖 $dir ($file_count files)"
    fi
done

echo ""
echo "🎉 All book files are now organized in separate directories!"
echo "💡 You can now use tools like easy_book_generator.sh to work with these organized books."
