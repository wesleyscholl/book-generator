#!/bin/bash

# Book Compilation Script with Version Support
# Combines outline and chapters into final manuscript
# Usage: ./compile_book.sh book_directory [output_format] [version]

set -e

# Animation functions
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))
    
    printf "\r📚 Progress: ["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d/%d (%d%%)" $current $total $percentage
}

typewriter() {
    local text="$1"
    local delay="${2:-0.03}"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%c" "${text:$i:1}"
        sleep $delay
    done
    echo
}

celebration() {
    local message="$1"
    local colors=("31" "32" "33" "34" "35" "36")
    
    for i in {1..10}; do
        local color=${colors[$((RANDOM % ${#colors[@]}))]}
        printf "\r\033[${color}m🎉 $message 🎉\033[0m"
        sleep 0.2
        printf "\r\033[K"
        sleep 0.1
    done
    
    echo "🎉 $message 🎉"
}

show_help() {
    cat << EOF
Book Compilation Script with Version Support

USAGE:
    $0 book_directory [output_format] [version]

ARGUMENTS:
    book_directory    - Directory containing outline and chapter files
    output_format     - Format: markdown|html|pdf (default: markdown)
    version          - Version: 1=original, 2=edited, 3=final (default: 1)

EXAMPLES:
    $0 ./book_outputs/book_outline_20241201_143022
    $0 ./book_outputs/book_outline_20241201_143022 html 2
    $0 ./book_outputs/book_outline_20241201_143022 pdf 3

FEATURES:
    - Combines all chapters in order
    - Supports original, edited, and final versions
    - Generates table of contents with proper links
    - Calculates comprehensive word count statistics
    - Creates clean manuscript ready for publishing
    - Optional HTML/PDF output (requires pandoc)
    - Progress animations and status updates
EOF
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

BOOK_DIR="$1"
OUTPUT_FORMAT="${2:-markdown}"
VERSION="${3:-1}"

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

# Determine chapter file pattern based on version
case $VERSION in
    2)
        CHAPTER_PATTERN="chapter_*_edited.md"
        VERSION_NAME="edited"
        FALLBACK_PATTERN="chapter_*.md"
        ;;
    3)
        CHAPTER_PATTERN="chapter_*_final.md"
        VERSION_NAME="final"
        FALLBACK_PATTERN="chapter_*_edited.md"
        FALLBACK2_PATTERN="chapter_*.md"
        ;;
    *)
        CHAPTER_PATTERN="chapter_*.md"
        VERSION_NAME="original"
        ;;
esac

typewriter "🔍 Looking for $VERSION_NAME chapters..."

# Find chapter files with fallback logic
CHAPTER_FILES=()

# Try primary pattern
for file in "$BOOK_DIR"/$CHAPTER_PATTERN; do
    if [[ -f "$file" && "$file" != *"_review.md" && "$file" != *"_proofed.md" ]]; then
        CHAPTER_FILES+=("$file")
    fi
done

# Fallback for edited/final versions
if [ ${#CHAPTER_FILES[@]} -eq 0 ] && [ "$VERSION" != "1" ]; then
    echo "⚠️  No $VERSION_NAME chapters found, trying fallback..."
    
    if [ "$VERSION" = "3" ] && [ -n "$FALLBACK_PATTERN" ]; then
        for file in "$BOOK_DIR"/$FALLBACK_PATTERN; do
            if [[ -f "$file" && "$file" != *"_review.md" && "$file" != *"_final.md" ]]; then
                CHAPTER_FILES+=("$file")
                VERSION_NAME="edited (fallback)"
            fi
        done
    fi
    
    if [ ${#CHAPTER_FILES[@]} -eq 0 ] && [ -n "$FALLBACK2_PATTERN" ]; then
        for file in "$BOOK_DIR"/$FALLBACK2_PATTERN; do
            if [[ -f "$file" && "$file" != *"_"*.md ]]; then
                CHAPTER_FILES+=("$file")
                VERSION_NAME="original (fallback)"
            fi
        done
    fi
fi

# Sort chapter files naturally
IFS=$'\n' CHAPTER_FILES=($(sort -V <<< "${CHAPTER_FILES[*]}"))

if [ ${#CHAPTER_FILES[@]} -eq 0 ]; then
    echo "❌ Error: No chapter files found in $BOOK_DIR"
    echo "Available files:"
    ls -la "$BOOK_DIR"/*.md 2>/dev/null | head -10
    exit 1
fi

echo "📖 Found ${#CHAPTER_FILES[@]} chapters ($VERSION_NAME version)"

# Extract book title from outline
BOOK_TITLE=$(grep -i -m1 -E "(^#[^#]|title)" "$OUTLINE_FILE" | sed 's/^#*\s*//;s/^[Tt]itle:\s*//' | head -1)
if [ -z "$BOOK_TITLE" ]; then
    BOOK_TITLE="Generated Book $(date +%Y-%m-%d)"
fi

# Create manuscript
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MANUSCRIPT_FILE="${BOOK_DIR}/manuscript_${VERSION_NAME}_${TIMESTAMP}.md"

typewriter "✍️ Creating manuscript: $(basename "$MANUSCRIPT_FILE")"

# Start manuscript with enhanced header
cat << EOF > "$MANUSCRIPT_FILE"
# $BOOK_TITLE

*Generated on $(date +"%B %d, %Y")*  
*Version: $VERSION_NAME*  
*Chapters: ${#CHAPTER_FILES[@]}*

---

## Table of Contents

EOF

echo "📋 Building table of contents..."

# Generate table of contents
CHAPTER_COUNT=0
for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_COUNT=$((CHAPTER_COUNT + 1))
    
    # Extract chapter number from filename
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" | sed -E 's/chapter_([0-9]+).*/\1/')
    
    # Extract chapter title from first line or content
    CHAPTER_TITLE=$(head -1 "$CHAPTER_FILE" | sed 's/^#*\s*//')
    
    # If first line isn't a title, search for one
    if [[ ! "$CHAPTER_TITLE" =~ Chapter.*: ]] && [[ ! "$CHAPTER_TITLE" =~ ^# ]]; then
        CHAPTER_TITLE=$(grep -m1 "^# " "$CHAPTER_FILE" | sed 's/^#\s*//' || echo "Chapter $CHAPTER_NUM")
    fi
    
    # Clean up title
    CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/^#*\s*//')
    if [[ ! "$CHAPTER_TITLE" =~ ^Chapter ]]; then
        CHAPTER_TITLE="Chapter $CHAPTER_NUM: $CHAPTER_TITLE"
    fi
    
    echo "- [$CHAPTER_TITLE](#chapter-$CHAPTER_NUM)" >> "$MANUSCRIPT_FILE"
    echo "  📄 Added: $CHAPTER_TITLE"
    sleep 0.1
done

echo "" >> "$MANUSCRIPT_FILE"
echo "---" >> "$MANUSCRIPT_FILE"
echo "" >> "$MANUSCRIPT_FILE"

# Add chapters to manuscript with progress tracking
echo ""
typewriter "📚 Assembling chapters into manuscript..."
echo ""

TOTAL_WORDS=0
CHAPTER_COUNTER=0

for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_COUNTER=$((CHAPTER_COUNTER + 1))
    
    # Show progress
    show_progress $CHAPTER_COUNTER ${#CHAPTER_FILES[@]}
    echo ""
    
    # Extract chapter number
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" | sed -E 's/chapter_([0-9]+).*/\1/')
    
    echo "📝 Processing Chapter $CHAPTER_NUM..."
    
    # Add chapter anchor for TOC linking
    echo "<a id=\"chapter-$CHAPTER_NUM\"></a>" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    
    # Process chapter content
    CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
    
    # Ensure chapter starts with proper heading
    if [[ ! "$CHAPTER_CONTENT" =~ ^#[[:space:]] ]]; then
        FIRST_LINE=$(echo "$CHAPTER_CONTENT" | head -1)
        if [[ "$FIRST_LINE" =~ Chapter.*: ]] || [[ "$FIRST_LINE" =~ ^# ]]; then
            # First line looks like a title
            CLEAN_TITLE=$(echo "$FIRST_LINE" | sed 's/^#*\s*//')
            echo "# $CLEAN_TITLE" >> "$MANUSCRIPT_FILE"
            echo "$CHAPTER_CONTENT" | tail -n +2 >> "$MANUSCRIPT_FILE"
        else
            # No clear title found, create one
            echo "# Chapter $CHAPTER_NUM" >> "$MANUSCRIPT_FILE"
            echo "$CHAPTER_CONTENT" >> "$MANUSCRIPT_FILE"
        fi
    else
        # Already has proper heading
        echo "$CHAPTER_CONTENT" >> "$MANUSCRIPT_FILE"
    fi
    
    echo "" >> "$MANUSCRIPT_FILE"
    echo "---" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    
    # Calculate word count
    CHAPTER_WORDS=$(wc -w < "$CHAPTER_FILE")
    TOTAL_WORDS=$((TOTAL_WORDS + CHAPTER_WORDS))
    
    echo "✅ Chapter $CHAPTER_NUM added ($CHAPTER_WORDS words)"
    sleep 0.3
done

echo ""

# Add comprehensive metadata section
cat << EOF >> "$MANUSCRIPT_FILE"

## Book Statistics & Metadata

### Content Overview
- **Total Chapters:** ${#CHAPTER_FILES[@]}
- **Total Word Count:** $TOTAL_WORDS words
- **Average Chapter Length:** $((TOTAL_WORDS / ${#CHAPTER_FILES[@]})) words
- **Estimated Page Count:** $((TOTAL_WORDS / 250)) pages (250 words/page)
- **Version Used:** $VERSION_NAME
- **Generated:** $(date +"%B %d, %Y at %I:%M %p")

### Plagiarism Check Summary
EOF

# Add plagiarism checking summary if reports exist
PLAGIARISM_REPORTS=($(ls "${BOOK_DIR}"/chapter_*_plagiarism_report.md 2>/dev/null))
BACKUP_FILES=($(ls "${BOOK_DIR}"/chapter_*.md.backup_* 2>/dev/null))

if [ ${#PLAGIARISM_REPORTS[@]} -gt 0 ]; then
    echo "- **Plagiarism Checks Performed:** ${#PLAGIARISM_REPORTS[@]} chapters" >> "$MANUSCRIPT_FILE"
    echo "- **Chapters Rewritten for Originality:** ${#BACKUP_FILES[@]}" >> "$MANUSCRIPT_FILE"
    
    # Calculate average originality score
    TOTAL_ORIGINALITY=0
    VALID_SCORES=0
    
    for report in "${PLAGIARISM_REPORTS[@]}"; do
        if [ -f "$report" ]; then
            SCORE=$(grep "ORIGINALITY_SCORE:" "$report" | sed 's/ORIGINALITY_SCORE: //' | grep -o '[0-9]*' | head -1)
            if [ -n "$SCORE" ] && [ "$SCORE" -gt 0 ]; then
                TOTAL_ORIGINALITY=$((TOTAL_ORIGINALITY + SCORE))
                VALID_SCORES=$((VALID_SCORES + 1))
            fi
        fi
    done
    
    if [ $VALID_SCORES -gt 0 ]; then
        AVG_ORIGINALITY=$((TOTAL_ORIGINALITY / VALID_SCORES))
        echo "- **Average Originality Score:** $AVG_ORIGINALITY/10" >> "$MANUSCRIPT_FILE"
        
        if [ $AVG_ORIGINALITY -ge 8 ]; then
            echo "- **Originality Assessment:** Excellent (98%+ original content)" >> "$MANUSCRIPT_FILE"
        elif [ $AVG_ORIGINALITY -ge 6 ]; then
            echo "- **Originality Assessment:** Good (85%+ original content)" >> "$MANUSCRIPT_FILE"
        else
            echo "- **Originality Assessment:** Acceptable (manual review recommended)" >> "$MANUSCRIPT_FILE"
        fi
    fi
else
    echo "- **Plagiarism Checking:** Not performed or reports not found" >> "$MANUSCRIPT_FILE"
fi

cat << EOF >> "$MANUSCRIPT_FILE"

### Chapter Breakdown
EOF

# Add detailed chapter statistics
for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" | sed -E 's/chapter_([0-9]+).*/\1/')
    CHAPTER_WORDS=$(wc -w < "$CHAPTER_FILE")
    CHAPTER_TITLE=$(head -1 "$CHAPTER_FILE" | sed 's/^#*\s*//' | cut -c1-50)
    
    echo "- **Chapter $CHAPTER_NUM:** $CHAPTER_WORDS words - $CHAPTER_TITLE..." >> "$MANUSCRIPT_FILE"
done

cat << EOF >> "$MANUSCRIPT_FILE"

### File Information
- **Source Directory:** $(basename "$BOOK_DIR")
- **Outline File:** $(basename "$OUTLINE_FILE")
- **Manuscript File:** $(basename "$MANUSCRIPT_FILE")
- **Compilation Date:** $(date)

---

*This book was generated using AI assistance and compiled automatically with version control.*
EOF

celebration "Manuscript Complete!"

echo "✅ Manuscript created: $(basename "$MANUSCRIPT_FILE")"
echo "📊 Total words: $TOTAL_WORDS"
echo "📄 Estimated pages: $((TOTAL_WORDS / 250))"

# Generate additional formats if requested
case $OUTPUT_FORMAT in
    html)
        if command -v pandoc >/dev/null 2>&1; then
            HTML_FILE="${BOOK_DIR}/manuscript_${VERSION_NAME}_${TIMESTAMP}.html"
            echo "🌐 Converting to HTML..."
            pandoc -f markdown -t html5 --standalone --toc \
                --css=<(echo "body{font-family:Georgia,serif;line-height:1.6;max-width:800px;margin:auto;padding:20px}") \
                -o "$HTML_FILE" "$MANUSCRIPT_FILE"
            echo "🌐 HTML version created: $(basename "$HTML_FILE")"
        else
            echo "⚠️  pandoc not found. Install with: sudo apt install pandoc"
        fi
        ;;
    pdf)
        if command -v pandoc >/dev/null 2>&1; then
            PDF_FILE="${BOOK_DIR}/manuscript_${VERSION_NAME}_${TIMESTAMP}.pdf"
            echo "📄 Converting to PDF..."
            pandoc -f markdown --pdf-engine=xelatex --toc \
                -V geometry:margin=1in -V fontsize=11pt \
                -o "$PDF_FILE" "$MANUSCRIPT_FILE" 2>/dev/null || {
                echo "⚠️  PDF generation failed. Trying with different engine..."
                pandoc -f markdown --pdf-engine=pdflatex --toc \
                    -V geometry:margin=1in -V fontsize=11pt \
                    -o "$PDF_FILE" "$MANUSCRIPT_FILE" 2>/dev/null || {
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

# Final summary
echo ""
echo "📊 Compilation Complete!"
echo "📁 Output directory: $BOOK_DIR"
echo "📖 Chapters compiled: ${#CHAPTER_FILES[@]} ($VERSION_NAME version)"
echo "📝 Total words: $TOTAL_WORDS"
echo "📄 Manuscript file: $(basename "$MANUSCRIPT_FILE")"

# Quality assessment
echo ""
echo "📈 Quality Assessment:"
if [ $TOTAL_WORDS -ge 25000 ] && [ $TOTAL_WORDS -le 35000 ]; then
    echo "✅ Word count is perfect for publishing (25k-35k range)"
elif [ $TOTAL_WORDS -ge 20000 ]; then
    echo "✅ Word count is good for publishing (20k+ range)"
else
    echo "⚠️  Word count may be low for full-length book ($TOTAL_WORDS words)"
fi

AVG_CHAPTER_LENGTH=$((TOTAL_WORDS / ${#CHAPTER_FILES[@]}))
if [ $AVG_CHAPTER_LENGTH -ge 2000 ] && [ $AVG_CHAPTER_LENGTH -le 3000 ]; then
    echo "✅ Chapter length is ideal (2k-3k words average)"
elif [ $AVG_CHAPTER_LENGTH -ge 1500 ]; then
    echo "✅ Chapter length is good (1.5k+ words average)"
else
    echo "⚠️  Chapters may be short ($AVG_CHAPTER_LENGTH words average)"
fi

echo ""
echo "📋 All generated files:"
ls -la "$BOOK_DIR"/*.md "$BOOK_DIR"/*.html "$BOOK_DIR"/*.pdf 2>/dev/null | grep -E "(manuscript|outline)" | sort -k9

echo ""
echo "🚀 Ready for publishing!"
echo "   📖 KDP Upload: Use the markdown or PDF file"
echo "   🌐 Website: Use HTML version"
echo "   ✏️  Further editing: Open markdown file in your preferred editor"
echo "   📧 Sharing: PDF version is most portable"