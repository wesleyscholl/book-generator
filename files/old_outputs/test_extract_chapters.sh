#!/bin/bash

# Test script for extract_chapters function
# Creates a test outline file and verifies the extract_chapters function

# Create a test outline file
cat > /tmp/test_outline.md << 'EOF'
# Book Title: Testing Extract Chapters
## Subtitle: A Technical Test

SUMMARY:
This is a sample book outline for testing the extract_chapters function.

THEMES:
1. Testing
2. Parsing
3. Robustness

CHAPTERS:
Chapter 1: Introduction to Testing
This chapter introduces testing concepts and methodologies.

Chapter 2: Advanced Testing
This chapter covers advanced testing techniques.

# Chapter 3: Edge Cases
This chapter explores edge cases in testing.

WORD COUNT DISTRIBUTION:
Introduction: 3000
Chapter 1-15: 3300 per chapter
Conclusion: 2000
Total: 54500

- Chapter 1-4: 8,000 words each
- Chapters 5-6: 6,000 words each
- Chapters 7-10: 4,000 words each
- Chapters 11-12: 3,000 words each
- Chapters 13-14: 2,500 words each

Chapter 4-6: These will be combined
Chapter 7: Final Chapter
This is the final chapter of the book.

1. Appendix A
2. Appendix B
EOF

# Define the extract_chapters function for standalone testing
# This is to avoid sourcing the entire full_book_generator.sh which requires arguments
extract_chapters() {
    local outline_file="$1"
    local temp_file=$(mktemp)
    local filtered_file=$(mktemp)
    
    # First, filter out the WORD COUNT DISTRIBUTION section and chapter ranges
    awk '
    BEGIN { skip = 0; }
    /^WORD COUNT DISTRIBUTION/ { skip = 1; next; }
    /^[[:space:]]*$/ { if (skip == 1) skip = 0; }
    # Skip chapter ranges with different formats
    /Chapter[[:space:]]+[0-9]+-[0-9]+/ { next; } # Skip "Chapter 1-15"
    /Chapter[[:space:]]+[0-9]+[[:space:]]*-[[:space:]]*[0-9]+/ { next; } # Skip "Chapter 1 - 15"
    /Chapters?[[:space:]]+[0-9]+-[0-9]+/ { next; } # Skip "Chapters 1-15"
    /Chapters?[[:space:]]+[0-9]+[[:space:]]*-[[:space:]]*[0-9]+/ { next; } # Skip "Chapters 1 - 15"
    /^[[:space:]]*-[[:space:]]*Chapters?[[:space:]]+[0-9]+-[0-9]+/ { next; } # Skip "- Chapters 1-15"
    /^[[:space:]]*-[[:space:]]*Chapter[[:space:]]+[0-9]+-[0-9]+/ { next; } # Skip "- Chapter 1-15"
    /^[[:space:]]*•[[:space:]]*Chapters?[[:space:]]+[0-9]+-[0-9]+/ { next; } # Skip "• Chapters 1-15"
    /[0-9]+[[:space:]]*words[[:space:]]*each/ { next; } # Skip any line with "words each"
    { if (skip == 0) print; }
    ' "$outline_file" > "$filtered_file"
    
    # Look for chapter patterns in the filtered outline
    # This handles various outline formats
    grep -i -E "(chapter|ch\.)\s*[0-9]+.*:" "$filtered_file" | \
    grep -v -E "[0-9]+-[0-9]+" | \
    grep -v -E "words[[:space:]]*each" | \
    sed -E 's/^[^0-9]*([0-9]+)[^:]*:\s*(.*)$/\1|\2/' | \
    head -20 > "$temp_file"
    
    # If no chapters found with that pattern, try different formats
    if [ ! -s "$temp_file" ]; then
        grep -i -E "^#+ *(chapter|ch\.)" "$filtered_file" | \
        grep -v -E "[0-9]+-[0-9]+" | \
        grep -v -E "words[[:space:]]*each" | \
        sed -E 's/^#+\s*(chapter|ch\.?)\s*([0-9]+)[^:]*:?\s*(.*)$/\2|\3/' >> "$temp_file"
    fi
    
    # If still no chapters, try numbered list format
    if [ ! -s "$temp_file" ]; then
        grep -E "^[0-9]+\." "$filtered_file" | \
        sed -E 's/^([0-9]+)\.\s*(.*)$/\1|\2/' | \
        head -15 >> "$temp_file"
    fi
    
    # Output the results and clean up
    cat "$temp_file"
    rm -f "$temp_file" "$filtered_file"
}

# No need to source the full script now

# Now test the extract_chapters function
echo "Testing extract_chapters function with the test outline..."
echo "Expected to see chapters 1, 2, 3, 7 and possibly numbered items 1, 2"
echo "Should NOT see 'Chapter 1-15' or 'Chapter 4-6'"
echo "-------------------------------------------------"
extract_chapters /tmp/test_outline.md
echo "-------------------------------------------------"

# Clean up
rm /tmp/test_outline.md
echo "Test complete!"
