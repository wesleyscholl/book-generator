#!/bin/bash

# Book Compilation Script
# Combines outline and chapters into final manuscript
# Usage: ./compile_book.sh book_directory [output_format]

set -e

show_help() {
    cat << EOF
Book Compilation Script

USAGE:
    $0 book_directory [output_format]

ARGUMENTS:
    book_directory    - Directory containing outline and chapter files
    output_format     - Format: markdown|html|pdf (default: markdown)

EXAMPLES:
    $0 ./book_outputs/book_outline_20241201_143022
    $0 ./book_outputs/book_outline_20241201_143022 html
    $0 ./book_outputs/book_outline_20241201_143022 pdf

FEATURES:
    - Combines all chapters in order
    - Generates table of contents
    - Calculates word count statistics
    - Creates clean manuscript ready for publishing
    - Optional HTML/PDF output (requires pandoc)
EOF
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

BOOK_DIR="$1"
OUTPUT_FORMAT="${2:-markdown}"

# Validate directory
if [ ! -d "$BOOK_DIR" ]; then
    echo "❌ Error: Directory '$BOOK_DIR' not found"
    exit 1
fi

# Find outline file
OUTLINE_FILE=""
for file in "$BOOK_DIR"/book_outline_*.md "$BOOK_DIR"/outline.md "$BOOK_DIR"/*.md; do
    if [[ -f "$file" && "$file" != *"chapter_"* && "$file" != *"manuscript"* ]]; then
        OUTLINE_FILE="$file"
        break
    fi
done

if [ -z "$OUTLINE_FILE" ]; then
    echo "❌ Error: No outline file found in $BOOK_DIR"
    exit 1
fi

echo "📚 Compiling book from: $BOOK_DIR"
echo "📋 Using outline: $(basename "$OUTLINE_FILE")"

# Extract book title from outline
BOOK_TITLE=$(grep -i -m1 "title\|# " "$OUTLINE_FILE" | sed 's/^#*\s*//;s/^[Tt]itle:\s*//' | head -1)
if [ -z "$BOOK_TITLE" ]; then
    BOOK_TITLE="Generated Book $(date +%Y-%m-%d)"
fi

# Create manuscript
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MANUSCRIPT_FILE="${BOOK_DIR}/manuscript_${TIMESTAMP}.md"

echo "✍️ Creating manuscript: $(basename "$MANUSCRIPT_FILE")"

# Start manuscript
cat << EOF > "$MANUSCRIPT_FILE"
# $BOOK_TITLE

*Generated on $(date +"%B %d, %Y")*

---

## Table of Contents

EOF

# Find and sort chapter files
CHAPTER_FILES=($(ls "$BOOK_DIR"/chapter_*.md 2>/dev/null | sort -V))

if [ ${#CHAPTER_FILES[@]} -eq 0 ]; then
    echo "❌ Error: No chapter files found in $BOOK_DIR"
    exit 1
fi

echo "📖 Found ${#CHAPTER_FILES[@]} chapters"

# Generate table of contents
for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" .md | sed 's/chapter_//')
    CHAPTER_TITLE=$(head -1 "$CHAPTER_FILE" | sed 's/^#*\s*//')
    
    # If first line isn't a title, extract from content
    if [[ ! "$CHAPTER_TITLE" =~ ^Chapter ]]; then
        CHAPTER_TITLE=$(grep -m1 "^# " "$CHAPTER_FILE" | sed 's/^#\s*//' || echo "Chapter $CHAPTER_NUM")
    fi
    
    echo "- [Chapter $CHAPTER_NUM: $CHAPTER_TITLE](#chapter-$CHAPTER_NUM)" >> "$MANUSCRIPT_FILE"
done

echo "" >> "$MANUSCRIPT_FILE"
echo "---" >> "$MANUSCRIPT_FILE"
echo "" >> "$MANUSCRIPT_FILE"

# Add chapters to manuscript
TOTAL_WORDS=0
for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" .md | sed 's/chapter_//')
    
    echo "📝 Adding Chapter $CHAPTER_NUM..."
    
    # Add chapter anchor
    echo "<a id=\"chapter-$CHAPTER_NUM\"></a>" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    
    # Process chapter content
    CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
    
    # Ensure chapter starts with proper heading
    if [[ ! "$CHAPTER_CONTENT" =~ ^#[[:space:]] ]]; then
        FIRST_LINE=$(echo "$CHAPTER_CONTENT" | head -1)
        if [[ "$FIRST_LINE" =~ Chapter ]]; then
            echo "# $FIRST_LINE" >> "$MANUSCRIPT_FILE"
            echo "$CHAPTER_CONTENT" | tail -n +2 >> "$MANUSCRIPT_FILE"
        else
            echo "# Chapter $CHAPTER_NUM" >> "$MANUSCRIPT_FILE"
            echo "$CHAPTER_CONTENT" >> "$MANUSCRIPT_FILE"
        fi
    else
        echo "$CHAPTER_CONTENT" >> "$MANUSCRIPT_FILE"
    fi
    
    echo "" >> "$MANUSCRIPT_FILE"
    echo "---" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    
    # Calculate word count
    CHAPTER_WORDS=$(wc -w < "$CHAPTER_FILE")
    TOTAL_WORDS=$((TOTAL_WORDS + CHAPTER_WORDS))
done

# Add metadata section
cat << EOF >> "$MANUSCRIPT_FILE"

## Book Statistics

- **Total Chapters:** ${#CHAPTER_FILES[@]}
- **Total Word Count:** $TOTAL_WORDS words
- **Average Chapter Length:** $((TOTAL_WORDS / ${#CHAPTER_FILES[@]})) words
- **Generated:** $(date)

---

*This book was generated using AI assistance and compiled automatically.*
EOF

echo "✅ Manuscript created: $(basename "$MANUSCRIPT_FILE")"

# Generate additional formats if requested
case $OUTPUT_FORMAT in
    html)
        if command -v pandoc >/dev/null 2>&1; then
            HTML_FILE="${BOOK_DIR}/manuscript_${TIMESTAMP}.html"
            pandoc -f markdown -t html5 --standalone --toc -o "$HTML_FILE" "$MANUSCRIPT_FILE"
            echo "🌐 HTML version created: $(basename "$HTML_FILE")"
        else
            echo "⚠️  pandoc not found. Install with: sudo apt install pandoc"
        fi
        ;;
    pdf)
        if command -v pandoc >/dev/null 2>&1; then
            PDF_FILE="${BOOK_DIR}/manuscript_${TIMESTAMP}.pdf"
            pandoc -f markdown --pdf-engine=xelatex --toc -o "$PDF_FILE" "$MANUSCRIPT_FILE" 2>/dev/null || {
                echo "⚠️  PDF generation failed. Trying with different engine..."
                pandoc -f markdown --pdf-engine=pdflatex --toc -o "$PDF_FILE" "$MANUSCRIPT_FILE" 2>/dev/null || {
                    echo "⚠️  PDF generation failed. Install LaTeX: sudo apt install texlive-xetex"
                }
            }
            if [ -f "$PDF_FILE" ]; then
                echo "📄 PDF version created: $(basename "$PDF_FILE")"
            fi
        else
            echo "⚠️  pandoc not found. Install with: sudo apt install pandoc"
        fi
        ;;
esac

# Final statistics
echo ""
echo "📊 Compilation Complete!"
echo "📁 Output directory: $BOOK_DIR"
echo "📖 Chapters compiled: ${#CHAPTER_FILES[@]}"
echo "📝 Total words: $TOTAL_WORDS"
echo "📄 Manuscript file: $(basename "$MANUSCRIPT_FILE")"
echo ""

# List all files
echo "📋 All generated files:"
ls -la "$BOOK_DIR"/*.md "$BOOK_DIR"/*.html "$BOOK_DIR"/*.pdf 2>/dev/null | grep -v "chapter_" || true

echo ""
echo "🚀 Ready for publishing!"
echo "   Upload to KDP: Use the markdown or PDF file"
echo "   Website publishing: Use HTML version"
echo "   Further editing: Open markdown file in your preferred editor"