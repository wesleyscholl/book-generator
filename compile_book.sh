#!/bin/bash

# Book Compilation Script with Version Support & Multi-Format Export
# Combines outline and chapters into final manuscript and exports in multiple formats
# Usage: ./compile_book.sh book_directory [output_format] [version]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required tools
check_requirements() {
    local missing_tools=()
    
    # Essential for PDF generation
    if ! command -v pandoc &> /dev/null; then
        missing_tools+=("pandoc")
    fi
    
    # For EPUB generation
    if ! command -v pandoc &> /dev/null; then
        missing_tools+=("pandoc")
    fi
    
    # For better PDF output
    if ! command -v pdflatex &> /dev/null && ! command -v xelatex &> /dev/null; then
        missing_tools+=("texlive")
    fi
    
    # For cover generation
    if ! command -v convert &> /dev/null; then
        missing_tools+=("imagemagick")
    fi
    
    # Return tool status
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "⚠️  Missing tools for full functionality: ${missing_tools[*]}"
        echo "   Installation suggestions:"
        echo "   - pandoc: brew install pandoc"
        echo "   - texlive: brew install --cask mactex"
        echo "   - imagemagick: brew install imagemagick"
        return 1
    fi
    return 0
}

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

celebration() {
    local message="$1"
    echo "🎉 $message 🎉"
}

show_help() {
    cat << EOF
Book Compilation Script with Multi-Format Export

USAGE:
    $0 [book_directory] [output_format] [version] [options]

ARGUMENTS:
    book_directory    - Directory containing outline and chapter files
                        (Optional: will auto-detect most recent book if omitted)
    output_format     - Format: all|epub|pdf|html|markdown|mobi|azw3 (default: all)
    version          - Version: 1=original, 2=edited, 3=final (default: 1)

OPTIONS:
    --author "Name"   - Set author name (default: AI-Assisted Author)
    --cover "path"    - Path to cover image (JPG/PNG, min 1600x2560 pixels)
    --isbn "number"   - Set ISBN for the book
    --publisher "name" - Set publisher name
    --year "YYYY"     - Publication year (default: current year)
    --generate-cover  - Auto-generate a simple cover if none provided

EXAMPLES:
    $0                        # Auto-detect most recent book
    $0 all                    # Export most recent book in all formats
    $0 epub --author "Jane"   # Export as EPUB with custom author
    $0 ./book_outputs/my-book epub 2 --cover "cover.jpg"   # Specify book and format

FEATURES:
    - Combines all chapters in order
    - Supports original, edited, and final versions
    - Generates complete ebooks with proper formatting
    - Creates industry-standard EPUB, MOBI, AZW3, PDF formats
    - Includes cover page, title page, TOC, copyright page
    - Properly formats chapters with heading hierarchies
    - Supports metadata for online publishing platforms
EOF
}

# Parse arguments with extended options support
BOOK_DIR=""
OUTPUT_FORMAT="all"  # Default to all formats
VERSION="1"
COVER_IMAGE=""
BACK_COVER=""
AUTHOR="AI-Assisted Author"
FAST=false
COVER_IMAGE=""
BACK_COVER=""
ISBN=""
PUBLISHER="Self-Published"
PUBLICATION_YEAR=$(date +"%Y")
GENERATE_COVER=false

# Function to generate book metadata
generate_metadata() {
    local title="$1"
    local output_dir="$2"
    local metadata_file="${output_dir}/metadata.yaml"
    
    # Get cover image basename if it exists
    local cover_basename=""
    if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
        cover_basename=$(basename "$COVER_IMAGE")
    fi
    
    cat > "$metadata_file" << EOF
---
title: "$title"
author: "$AUTHOR"
date: "$PUBLICATION_YEAR"
titlepage: false
rights: "Copyright © $PUBLICATION_YEAR $AUTHOR. All rights reserved."
language: "en-US"
publisher: "$PUBLISHER"
identifier:
  - scheme: ISBN
    text: "${ISBN:-[No ISBN Provided]}"
classoption: openany
header-includes:
  - \usepackage{titlesec}
  - \titleformat{\section}[block]{\bfseries\Huge\centering}{}{0pt}{}
  - \titleformat{\subsection}[block]{\bfseries\Large\centering}{}{0pt}{}
  - \let\cleardoublepage\clearpage
  - \renewcommand{\chapterbreak}{\clearpage}
  
$([ -n "$cover_basename" ] && echo "cover-image: \"$cover_basename\"")
...
EOF

    echo "$metadata_file"
}

# Function to generate a random author pen name from predefined list
generate_author_pen_name() {
    echo "🖋️ Selecting random author pen name..."
    
    # Use a predefined list of creative pen names
    local pen_names=(
        "Elara Morgan"
        "J.T. Blackwood"
        "Sophia Wyndham"
        "Xavier Stone"
        "Leo Hawthorne"
        "Isabella Quinn"
        "Nathaniel Grey"
        "Olivia Sterling"
        "Liam West"
        "Mia Rivers"
        "Noah Bennett"
        "Ava Sinclair"
        "Oliver James"
        "Charlotte Wells"
        "Jameson Blake"
        "Luna Rivers"
        "Ethan Cross"
        "Zoe Hart"
        "Mason Brooks"
        "Amelia Rivers"
        "Aiden Chase"
        "Jasper Knight"
        "Cassandra Vale"
        "Dahlia Black"
    )
    
    # Select a random pen name from the list
    local random_index=$((RANDOM % ${#pen_names[@]}))
    AUTHOR="${pen_names[$random_index]}"
    echo "✅ Selected author pen name: $AUTHOR"
}

# Function to generate a book cover using Ollama or ImageMagick
generate_book_cover() {
    local title="$1"
    local output_dir="$2"
    local front_file="${output_dir}/generated_cover_front.jpg"
    local back_file="${output_dir}/generated_cover_back.jpg"

    # Split title into main and subtitle at the LAST colon so prefixes like
    # 'Book Title:' remain part of the visible main title.
    local main_title="$title"
    local last_sub_title=""
    if [[ "$title" == *":"* ]]; then
        # Get substring after last colon
        last_sub_title="${title##*: }"
        # Get everything before the last colon (preserve earlier colons/prefixes)
        main_title="${title%: $last_sub_title}"
    fi

    # Determine ImageMagick command (prefer magick if present)
    local img_cmd="convert"
    if command -v magick &> /dev/null; then
        img_cmd="magick"
    fi

    if ! command -v convert &> /dev/null && ! command -v magick &> /dev/null; then
        echo "⚠️ ImageMagick not found. Cannot generate cover."
        return 1
    fi
    
    # Create a directory for assets if it doesn't exist
    local assets_dir="${output_dir}/assets"
    mkdir -p "$assets_dir"
    
    # Create directory for temporary files
    local temp_dir="${assets_dir}/temp"
    mkdir -p "$temp_dir"

    echo "🎨 Creating simple black and white book covers with ImageMagick..."
    
    # Check for publisher logo
    local logo_path="$SCRIPT_DIR/speedy-quick-publishing-logo.png"
    local logo_exports_path="${assets_dir}/speedy-quick-publishing-logo.png"
    
    if [ -f "$logo_path" ]; then
        # Copy logo to exports directory
        cp "$logo_path" "$logo_exports_path"
    else
        # Check in current directory
        if [ -f "speedy-quick-publishing-logo.png" ]; then
            cp "speedy-quick-publishing-logo.png" "$logo_exports_path"
        else
            echo "⚠️ Publisher logo not found, creating a placeholder"
            # Create a placeholder logo
            $img_cmd -size 300x100 xc:white -gravity center \
                -pointsize 24 -fill black -annotate +0+0 "$PUBLISHER" \
                "$logo_exports_path"
        fi
    fi

    # Simple black & white cover generation (no external AI)
    # Ensure the publisher logo is placed in the exports dir and used on back/copyright pages
    local logo_basename="$(basename "$logo_exports_path")"
    local logo_for_export="${output_dir}/${logo_basename}"
    if [ -f "$logo_exports_path" ]; then
        cp -f "$logo_exports_path" "$logo_for_export" 2>/dev/null || true
    fi

    # Prepare title and subtitle text for the front cover (keep existing 'Book Title:' prefix if present)
    # Use printf so we get real newline characters for ImageMagick's caption:
    local caption_text
    if [ -n "$last_sub_title" ]; then
        caption_text=$(printf "%s\n\n%s" "$main_title" "$last_sub_title")
    else
        caption_text="$main_title"
    fi

    # Create front cover: white background, black text centered
    $img_cmd -size 1600x2560 xc:white "$front_file"
    # Title in middle
    local main_pt=72
    if [ ${#main_title} -gt 80 ]; then
        main_pt=44
    elif [ ${#main_title} -gt 40 ]; then
        main_pt=60
    fi
    # Draw main title and subtitle explicitly so they appear reliably
    local font_arg=""
    if $img_cmd -list font | grep -iq "arial" 2>/dev/null; then
        font_arg="-font Arial"
    fi

    # Place main title slightly above center
    $img_cmd "$front_file" -gravity center $font_arg -pointsize $main_pt -fill black -annotate +0-120 "$main_title" "$front_file"

    # Place subtitle under the main title
    local sub_pt
    if [ -n "$last_sub_title" ]; then
        sub_pt=$((main_pt / 2 + 8))
        $img_cmd "$front_file" -gravity center $font_arg -pointsize $sub_pt -fill black -annotate +0+60 "$last_sub_title" "$front_file"
    else
        # fallback subtitle size
        sub_pt=$((main_pt / 2 + 4))
    fi

    # Add author above the bottom and make it match the subtitle size (bigger)
    if [ -n "$AUTHOR" ]; then
        $img_cmd "$front_file" -gravity South $font_arg -pointsize $sub_pt -fill black -annotate +0+220 "By $AUTHOR" "$front_file"
    fi

    # Replace publisher text with the publisher logo at the bottom center
    if [ -f "$logo_for_export" ]; then
        local front_logo_tmp="${temp_dir}/logo_front_small.png"
        # Resize small logo
        $img_cmd "$logo_for_export" -resize 160x160 "$front_logo_tmp" 2>/dev/null || cp -f "$logo_for_export" "$front_logo_tmp" 2>/dev/null || true
        # Composite the small logo at the very bottom center
        $img_cmd "$front_file" "$front_logo_tmp" -gravity South -geometry +0+40 -compose over -composite "$front_file"
        rm -f "$front_logo_tmp" 2>/dev/null || true
    fi

    # Create back cover: plain white with centered logo
    $img_cmd -size 1600x2560 xc:white "$back_file"
    if [ -f "$logo_for_export" ]; then
        # Resize logo to sit above the bottom so copyright can appear under it
        local logo_tmp="${temp_dir}/logo_resized.png"
        $img_cmd "$logo_for_export" -resize 400x400 "$logo_tmp" 2>/dev/null || cp -f "$logo_for_export" "$logo_tmp" 2>/dev/null || true
        # Composite the logo slightly above the bottom center
        $img_cmd "$back_file" "$logo_tmp" -gravity South -geometry +0+80 -compose over -composite "$back_file"
        # Add copyright line under the logo (closer to the bottom)
        $img_cmd "$back_file" -gravity South -pointsize 18 -fill black -annotate +0+75 "Copyright © $PUBLICATION_YEAR" "$back_file"
        rm -f "$logo_tmp" 2>/dev/null || true
    else
        # Fallback: add publisher name centered
        $img_cmd "$back_file" -gravity center -pointsize 28 -fill black -annotate +0+0 "$PUBLISHER" "$back_file"
    fi

    COVER_IMAGE="$front_file"
    BACK_COVER="$back_file"
    # ensure files saved with high quality
    $img_cmd "$front_file" -quality 95 "$front_file" 2>/dev/null || true
    $img_cmd "$back_file" -quality 95 "$back_file" 2>/dev/null || true
    # copy logo to exports root if present
    if [ -f "$logo_exports_path" ]; then
        cp -f "$logo_exports_path" "$output_dir/$(basename "$logo_exports_path")" 2>/dev/null || true
    fi
    return 0

    # Compute adaptive point sizes based on title length
    local title_len=${#main_title}
    local main_pt=90
    if [ $title_len -gt 120 ]; then
        main_pt=40
    elif [ $title_len -gt 80 ]; then
        main_pt=52
    elif [ $title_len -gt 50 ]; then
        main_pt=70
    fi
    local sub_pt=$((main_pt / 2 + 10))

    # Create front cover background
    $img_cmd -size 1600x2560 gradient:'#2b5876'-'#4e4376' -distort Arc 120 "$front_file"

    # Add texture overlay
    $img_cmd "$front_file" \( -size 1600x2560 plasma:fractal -blur 0x6 -colorspace Gray -auto-level -evaluate Multiply 0.6 \) -compose Overlay -composite "$front_file"

    # Prepare caption image for the title (so it wraps and scales)
    # Use a constrained width so long titles wrap neatly
    local caption_width=1200
    # Prepare caption content
    # Use printf again to ensure newlines are present
    local caption_text
    if [ -n "$last_sub_title" ]; then
        caption_text=$(printf "%s\n\n%s" "$main_title" "$last_sub_title")
    else
        caption_text="$main_title"
    fi

    # Create a transparent label with the title text using caption to wrap
    $img_cmd -background none -fill white -font Arial -size ${caption_width}x800 -gravity center -pointsize $main_pt caption:"$caption_text" miff:- | \
        $img_cmd - "$front_file" -gravity center -compose over -composite "$front_file"

    # Add author line and publisher line with subtle shadow
    $img_cmd "$front_file" -gravity South -pointsize 36 -fill white -annotate +0+220 "By $AUTHOR" "$front_file"
    $img_cmd "$front_file" -gravity South -pointsize 28 -fill white -annotate +0+160 "$PUBLISHER" "$front_file"

    # Create back cover: use same background and place a short blurb (first paragraph of outline if present)
    $img_cmd -size 1600x2560 gradient:'#4e4376'-'#2b5876' -distort Arc 120 "$back_file"
    $img_cmd "$back_file" \( -size 1600x2560 plasma:fractal -blur 0x6 -colorspace Gray -auto-level -evaluate Multiply 0.6 \) -compose Overlay -composite "$back_file"

    # Try to extract a short blurb from the outline if available
    local blurb=""
    if [ -n "${OUTLINE_FILE:-}" ] && [ -f "$OUTLINE_FILE" ]; then
        blurb=$(awk 'BEGIN{RS=""; getline; print; exit}' "$OUTLINE_FILE" | tr '\n' ' ' | sed 's/\s\+/ /g' | cut -c1-900)
    fi
    if [ -z "$blurb" ]; then
        blurb="A captivating read. Discover the ideas and stories within."
    fi

    # Create caption for back blurb
    $img_cmd -background none -fill white -font Arial -size 1200x1400 -gravity center -pointsize 28 caption:"$blurb" miff:- | \
        $img_cmd - "$back_file" -gravity center -compose over -composite "$back_file"

    # Add publisher and ISBN block at bottom
    $img_cmd "$back_file" -gravity South -pointsize 22 -fill white -annotate +0+120 "$PUBLISHER  •  $PUBLICATION_YEAR" "$back_file"
    if [ -n "$ISBN" ]; then
        $img_cmd "$back_file" -gravity South -pointsize 20 -fill white -annotate +0+80 "ISBN: $ISBN" "$back_file"
    fi

    echo "✅ Front cover created: $(basename "$front_file")"
    echo "✅ Back cover created: $(basename "$back_file")"

    COVER_IMAGE="$front_file"
    BACK_COVER="$back_file"
    return 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --author)
            AUTHOR="$2"
            shift 2
            ;;
        --cover)
            COVER_IMAGE="$2"
            shift 2
            ;;
        --isbn)
            ISBN="$2"
            shift 2
            ;;
        --publisher)
            PUBLISHER="$2"
            shift 2
            ;;
        --year)
            PUBLICATION_YEAR="$2"
            shift 2
            ;;
        --generate-cover)
            GENERATE_COVER=true
            shift
            ;;
        --fast)
            # Fast mode: skip slow mobi/azw3 conversions and some post-processing
            FAST=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            # If argument is a known format, set it directly (for convenience)
            if [ "$1" = "markdown" ] || [ "$1" = "html" ] || [ "$1" = "pdf" ] || [ "$1" = "epub" ] || [ "$1" = "mobi" ] || [ "$1" = "azw3" ] || [ "$1" = "all" ]; then
                OUTPUT_FORMAT="$1"
                shift
                continue
            fi
            
            # If argument is a known version, set it directly (for convenience)
            if [ "$1" = "1" ] || [ "$1" = "2" ] || [ "$1" = "3" ]; then
                VERSION="$1"
                shift
                continue
            fi
            
            # If BOOK_DIR is empty, and this isn't a known format/version, it must be the book directory
            if [ -z "$BOOK_DIR" ]; then
                BOOK_DIR="$1"
            else
                echo "❌ Unknown argument: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Auto-detect book directories if not provided
if [ -z "$BOOK_DIR" ]; then
    OUTPUTS_DIR="$SCRIPT_DIR/book_outputs"
    
    if [ ! -d "$OUTPUTS_DIR" ]; then
        echo "❌ Error: book_outputs directory not found"
        show_help
        exit 1
    fi
    
    # Find the most recent book directory
    echo "🔍 No book directory specified, looking for most recent book in outputs folder..."
    
    # List book directories, sort by modification time (newest first)
    AVAILABLE_BOOKS=()
    while IFS= read -r dir; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != "." ] && [ "$(basename "$dir")" != ".." ]; then
            AVAILABLE_BOOKS+=("$dir")
        fi
    done < <(find "$OUTPUTS_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -0 ls -dt)
    
    # Check if any books were found
    if [ ${#AVAILABLE_BOOKS[@]} -eq 0 ]; then
        echo "❌ Error: No book directories found in $OUTPUTS_DIR"
        exit 1
    fi
    
    # Use the most recent book directory
    BOOK_DIR="${AVAILABLE_BOOKS[0]}"
    echo "✅ Using most recent book: $(basename "$BOOK_DIR")"
else
    # Validate directory if manually specified
    if [ ! -d "$BOOK_DIR" ]; then
        echo "❌ Error: Directory '$BOOK_DIR' not found"
        exit 1
    fi
fi

# Find outline file - prioritize final versions
OUTLINE_FILE=""

# First, try to find book_outline_final_*.md files
for file in "$BOOK_DIR"/book_outline_final_*.md; do
    if [[ -f "$file" && "$file" != *"chapter_"* && "$file" != *"manuscript"* ]]; then
        OUTLINE_FILE="$file"
        break
    fi
done

# If no final outline found, fallback to regular book_outline_*.md files
if [ -z "$OUTLINE_FILE" ]; then
    for file in "$BOOK_DIR"/book_outline_*.md "$BOOK_DIR"/outline.md "$BOOK_DIR"/*.md; do
        if [[ -f "$file" && "$file" != *"chapter_"* && "$file" != *"manuscript"* && "$file" != *"final"* ]]; then
            OUTLINE_FILE="$file"
            break
        fi
    done
fi

if [ -z "$OUTLINE_FILE" ]; then
    echo "❌ Error: No outline file found in $BOOK_DIR"
    exit 1
fi

echo "📚 Compiling book from: $BOOK_DIR"
echo "📋 Using outline: $(basename "$OUTLINE_FILE")"
# Show book metadata
BOOK_TITLE=$(grep -i -m1 -E "(^#[^#]|title)" "$OUTLINE_FILE" | sed 's/^#*\s*//;s/^[Tt]itle:\s*//' | head -1)
if [ -z "$BOOK_TITLE" ]; then
    BOOK_TITLE="$(basename "$BOOK_DIR")"
fi
echo "📖 Book title: $BOOK_TITLE"
echo "👤 Author: $AUTHOR"
echo "🏢 Publisher: $PUBLISHER"

# Determine chapter file pattern based on version
case $VERSION in
    2)
        VERSION_NAME="edited"
        ;;
    3)
        VERSION_NAME="final"
        ;;
    *)
        VERSION_NAME="original"
        ;;
esac

echo "🔎 Looking for $VERSION_NAME chapters..."

# -----------------------------
# Extract chapter numbers from outline
# -----------------------------
echo "🔍 Extracting chapter numbers from outline..."
CHAPTER_NUMS_LIST=$(grep -oE 'Chapter[[:space:]]+[0-9]+' "$OUTLINE_FILE" \
    | awk '{print $2}' \
    | sort -n -u | paste -sd, -)

CHAPTER_COUNT=$(echo "$CHAPTER_NUMS_LIST" | tr ',' '\n' | wc -l)
echo "📋 Found $CHAPTER_COUNT chapters in outline"

# -----------------------------
# Build CHAPTER_FILES in outline order
# -----------------------------
CHAPTER_FILES=()
IFS=',' read -r -a OUTLINE_CHAPTERS <<< "$CHAPTER_NUMS_LIST"

for chapter_num in "${OUTLINE_CHAPTERS[@]}"; do
    primary_file=""
    case $VERSION in
        3)
            [[ -f "$BOOK_DIR/chapter_${chapter_num}_final.md" ]] && primary_file="$BOOK_DIR/chapter_${chapter_num}_final.md"
            ;;
        2)
            [[ -f "$BOOK_DIR/chapter_${chapter_num}_edited.md" ]] && primary_file="$BOOK_DIR/chapter_${chapter_num}_edited.md"
            ;;
        *)
            [[ -f "$BOOK_DIR/chapter_${chapter_num}.md" ]] && primary_file="$BOOK_DIR/chapter_${chapter_num}.md"
            ;;
    esac

    # Fallbacks
    if [ -z "$primary_file" ]; then
        for suffix in "_edited" "_final" ""; do
            candidate="$BOOK_DIR/chapter_${chapter_num}${suffix}.md"
            if [[ -f "$candidate" && "$candidate" != *"_review.md" && "$candidate" != *"_proofed.md" ]]; then
                primary_file="$candidate"
                break
            fi
        done
    fi

    if [ -n "$primary_file" ]; then
        CHAPTER_FILES+=("$primary_file")
    else
        echo "⚠️  Warning: Could not find any file for chapter $chapter_num"
    fi
done

# -----------------------------
# Sort chapter files numerically (safe for spaces)
# -----------------------------
if [ ${#CHAPTER_FILES[@]} -gt 0 ]; then
    # Sort using IFS=$'\n' and read into a new array
    IFS=$'\n' sorted=($(printf "%s\n" "${CHAPTER_FILES[@]}" | sort -V))
    unset IFS
    CHAPTER_FILES=("${sorted[@]}")
else
    echo "❌ Error: No chapter files found in $BOOK_DIR"
    ls -la "$BOOK_DIR"/*.md 2>/dev/null | head -10

    # Autodetect
    echo "🔄 Trying to autodetect chapter files..."
    for file in "$BOOK_DIR"/chapter_*.md; do
        if [[ -f "$file" && "$file" != *"_review.md" && "$file" != *"_proofed.md" && "$file" != *"_edited.md" && "$file" != *"_final.md" ]]; then
            CHAPTER_FILES+=("$file")
        fi
    done

    if [ ${#CHAPTER_FILES[@]} -eq 0 ]; then
        echo "❌ Error: No chapter files could be autodetected either"
        exit 1
    else
        echo "✅ Autodetected ${#CHAPTER_FILES[@]} chapter files"
        IFS=$'\n' sorted=($(printf "%s\n" "${CHAPTER_FILES[@]}" | sort -V))
        unset IFS
        CHAPTER_FILES=("${sorted[@]}")
    fi
fi

echo "📖 Found ${#CHAPTER_FILES[@]} chapters ($VERSION_NAME version)"
echo "📋 Chapter files to be included:"
for file in "${CHAPTER_FILES[@]}"; do
    echo "   - $(basename "$file")"
done

# -----------------------------
# Extract book title
# -----------------------------
BOOK_TITLE=$(grep -i -m1 -E "(^#[^#]|title)" "$OUTLINE_FILE" \
    | sed 's/^#*\s*//;s/^[Tt]itle:\s*//;s/[Bb]ook [Tt]itle://;s/^ *//;s/ *$//;s/:.*//;' \
    | head -1)

if [ -z "$BOOK_TITLE" ]; then
    BOOK_TITLE="Generated Book $(date +%Y-%m-%d)"
fi
# Keep any 'Book Title:' prefix as requested; extract subtitle for layout
SUB_TITLE="$(grep -i -m1 -E "(^#[^#]|title)" "$OUTLINE_FILE" | sed 's/^#*\s*//;s/^[Tt]itle:\s*//;s/[Bb]ook [Tt]itle://;s/^ *//;s/ *$//;' | cut -d ':' -f 2- | head -1)"

# Create manuscript
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MANUSCRIPT_FILE="${BOOK_DIR}/manuscript_${VERSION_NAME}_${TIMESTAMP}.md"
EXPORTS_DIR="${BOOK_DIR}/exports_${TIMESTAMP}"
mkdir -p "$EXPORTS_DIR"

# Copy publisher logo into exports dir for inclusion in manuscript (small logo on title/copyright pages)
PUBLISHER_LOGO_SRC="$SCRIPT_DIR/speedy-quick-publishing-logo.png"
if [ -f "$PUBLISHER_LOGO_SRC" ]; then
    cp -f "$PUBLISHER_LOGO_SRC" "$EXPORTS_DIR/$(basename "$PUBLISHER_LOGO_SRC")" 2>/dev/null || true
fi
# Basename for referencing the logo in the manuscript and exports
LOGO_BASENAME="$(basename "$PUBLISHER_LOGO_SRC")"

echo "📑 Creating manuscript: $(basename "$MANUSCRIPT_FILE")"

# Generate random author pen name if requested
if [ "$AUTHOR" = "AI-Assisted Author" ]; then
    # We're using the default author name, so we can randomize it
    generate_author_pen_name
fi

# Process cover image if provided
if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
    echo "🖼️ Using provided cover: $COVER_IMAGE"
    cp "$COVER_IMAGE" "$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
elif [ "$GENERATE_COVER" = true ]; then
    generate_book_cover "$BOOK_TITLE" "$EXPORTS_DIR"
fi

# Ensure cover image is properly set up before creating metadata
if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
    # Copy cover to exports directory if needed
    if [ "$COVER_IMAGE" != "$EXPORTS_DIR/$(basename "$COVER_IMAGE")" ]; then
        cp "$COVER_IMAGE" "$EXPORTS_DIR/"
    fi
    COVER_IMAGE="$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
    echo "📄 Cover image prepared for ebook: $(basename "$COVER_IMAGE")"
fi

# Create metadata file for ebook exports
METADATA_FILE=$(generate_metadata "$BOOK_TITLE" "$EXPORTS_DIR")

# Start manuscript with complete front matter using markdown and LaTeX page breaks
cat << EOF > "$MANUSCRIPT_FILE"
---
title: "$BOOK_TITLE"
author: "$AUTHOR"
date: "$PUBLICATION_YEAR"
titlepage: false
rights: "Copyright © $PUBLICATION_YEAR $AUTHOR"
language: "en-US"
header-includes:
  - \usepackage{titlesec}
  - \titleformat{\section}[block]{\bfseries\Huge\centering}{}{0pt}{}
  - \titleformat{\subsection}[block]{\bfseries\Large\centering}{}{0pt}{}
---

\renewcommand{\contentsname}{Table of Contents}
\thispagestyle{empty}
\newpage
\thispagestyle{empty}
\clearpage\vspace*{\fill}
# $BOOK_TITLE {.unnumbered .unlisted}
## $SUB_TITLE
\vspace{12em}

## By $AUTHOR
## © $PUBLICATION_YEAR


$(if [ -f "$EXPORTS_DIR/$LOGO_BASENAME" ]; then echo "## ![]($LOGO_BASENAME){ width=40% } "; fi)
\vspace*{\fill}\clearpage

\newpage

\clearpage\vspace*{\fill}
$(if [ -f "$EXPORTS_DIR/$LOGO_BASENAME" ]; then echo "## ![]($LOGO_BASENAME){ width=75% } "; fi)

\centerline{\textbf{Copyright © $PUBLICATION_YEAR $AUTHOR}}
\centerline{\textbf{$PUBLISHER}}
$(if [ -n "$ISBN" ]; then echo "ISBN: $ISBN"; fi)
All rights reserved. No part of this publication may be reproduced, distributed, or transmitted in any form or by any means, including photocopying, recording, or other electronic or mechanical methods, without the prior written permission of the publisher.

\newpage

\clearpage
\setcounter{tocdepth}{1}
\tableofcontents
\clearpage

\newpage

EOF

# Add chapters to manuscript with progress tracking
echo ""
echo "📖 Assembling chapters into manuscript..."
echo ""

TOTAL_WORDS=0
CHAPTER_COUNTER=0
CHAPTER_WORD_COUNTS_FILE=$(mktemp)

for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_COUNTER=$((CHAPTER_COUNTER + 1))
    
    # Extract chapter number
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" | sed -E 's/chapter_([0-9]+).*/\1/')

    echo "📝 Processing Chapter $CHAPTER_NUM..."

    # Add chapter anchor and proper page break for ebook formats
    echo "" >> "$MANUSCRIPT_FILE"
    echo "\newpage" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    echo "<a id=\"chapter-$CHAPTER_NUM\" class=\"chapter\"></a>" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"

    # Look up chapter display title from the outline to avoid duplicated titles
    outline_line=$(grep -i -m1 -E "Chapter[[:space:]]+${CHAPTER_NUM}[:\. -]*.*" "$OUTLINE_FILE" || true)
    if [ -n "$outline_line" ]; then
        DISPLAY_TITLE=$(echo "$outline_line" | sed -E 's/^[[:space:]]*[Cc]hapter[[:space:]]+'${CHAPTER_NUM}'[:\. -]*//; s/^[[:space:]]*'${CHAPTER_NUM}'[\.)[:space:]-]*//')
        DISPLAY_TITLE=$(echo "$DISPLAY_TITLE" | sed -E 's/^[[:space:]]*[Cc]hapter[[:space:]]*[0-9]+[:\. -]*//i; s/^[[:space:]]*[0-9]+[\.)[:space:]-]*//')
        DISPLAY_TITLE=$(echo "$DISPLAY_TITLE" | sed 's/^ *//; s/ *$//')
        [ -z "$DISPLAY_TITLE" ] && DISPLAY_TITLE="Chapter ${CHAPTER_NUM}"
    else
        DISPLAY_TITLE="Chapter ${CHAPTER_NUM}"
    fi
    CLEAN_CHAPTER_TITLE=$(echo "$DISPLAY_TITLE" | sed -e "s/^Chapter $CHAPTER_NUM: //; s/^Chapter $CHAPTER_NUM //")

    # Split chapter title at first colon to create H1/H2 structure
    if [[ "$CLEAN_CHAPTER_TITLE" == *":"* ]]; then
        # Extract part before first colon for H1
        CHAPTER_MAIN_TITLE=$(echo "$CLEAN_CHAPTER_TITLE" | cut -d: -f1 | sed 's/^ *//; s/ *$//')
        # Extract part after first colon for H2
        CHAPTER_SUBTITLE=$(echo "$CLEAN_CHAPTER_TITLE" | cut -d: -f2- | sed 's/^ *//; s/ *$//')
        
        # Write split title structure to manuscript
        echo "# Chapter $CHAPTER_NUM: $CHAPTER_MAIN_TITLE {.chapter-title}" >> "$MANUSCRIPT_FILE"
        echo "" >> "$MANUSCRIPT_FILE"
        echo "## $CHAPTER_SUBTITLE" >> "$MANUSCRIPT_FILE"
    else
        # No colon found, use original format
        echo "# Chapter $CHAPTER_NUM: $CLEAN_CHAPTER_TITLE {.chapter-title}" >> "$MANUSCRIPT_FILE"
    fi
    echo "" >> "$MANUSCRIPT_FILE"

    # Process chapter content and clean it, but remove heading lines so we don't duplicate titles
    CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
    
    # First pass: Remove all metadata sections with comprehensive pattern matching
    CLEAN_CONTENT=$(echo "$CHAPTER_CONTENT" | sed -E -i '
        # Remove standard metadata sections (case insensitive)
        /(?i)^(PLAGIARISM|COPYRIGHT)[ _\/]*ANALYSIS:?/,/^$/d;
        /(?i)^(COPYRIGHT|PLAGIARISM)[ _\/]*RISK:?/,/^$/d;
        /(?i)^FLAGGED[ _]*SECTIONS:?/,/^$/d;
        /(?i)^(ISSUES|PROBLEMS)[ _]*FOUND:?/,/^$/d;
        /(?i)^WRITING[ _]*GUIDELINES:?/,/^$/d;
        /(?i)^DETAILED[ _]*ANALYSIS:?/,/^$/d;
        /(?i)^RECOMMENDATIONS?:?/,/^$/d;
        /(?i)^IMPORTANT[ _]*WORD[ _]*COUNT[ _]*REQUIREMENT:?/,/^$/d;
        /(?i)^REWRITING[ _]*REQUIREMENTS?:?/,/^$/d;
        /(?i)^The final answer is:/,/^$/d;
        /(?i)^\**The content needs to be rewritten/,/^$/d;
        
        # Remove all variations of markdown-formatted guidelines
        /(?i)^\*\*WRITING[ _]*GUIDELINES:?\*\*/,/^$/d;
        /(?i)^\*\*PLAGIARISM[ _\/]*ANALYSIS:?\*\*/,/^$/d;
        /(?i)^\*\*COPYRIGHT[ _]*ANALYSIS:?\*\*/,/^$/d;
        /(?i)^\*\*REWRITING[ _]*REQUIREMENTS:?\*\*/,/^$/d;
        
        # Remove score and risk indicators
        /(?i)^ORIGINALITY[ _]*SCORE:?/d;
        /(?i)^PLAGIARISM[ _]*RISK:?/d;
        /(?i)^COPYRIGHT[ _]*RISK:?/d;
        /(?i)^ISSUES[ _]*FOUND:?/d;
        
        # Remove chapter rewrite markers
        /(?i)^Chapter Rewrite:?/d;
        /(?i)^Please rewrite the entire chapter/d;
        
        # Remove specific phrases
        s/Figure 1: Book Cover//g;
        
        # Remove note sections
        /(?i)^NOTE TO WRITER:?/,/^$/d;
        /(?i)^STYLE NOTES?:?/,/^$/d;
        
        # Remove AI-generated headers
        /(?i)^AI[ _]*GENERATED[ _]*CONTENT:?/,/^$/d;
        /(?i)^\*\*AI[ _]*GENERATED[ _]*CONTENT:?\*\*/,/^$/d;
        /(?i)^Generated with AI/d;
        /(?i)^This content was generated by/d;
    ')

    # Second pass: Remove trailing paragraphs that contain rewriting goals or prompt info
    CLEAN_CONTENT=$(echo "$CLEAN_CONTENT" | sed -E '
        # Remove common trailing metadata patterns
        /(?i)^In this chapter(,| we)/,$d;
        /(?i)^This chapter (meets|follows|adheres to)/,$d;
        /(?i)^I have (written|created|completed)/,$d;
        /(?i)^The chapter (now|has been|is) (complete|written)/,$d;
        /(?i)^Note: This chapter/,$d;
        /(?i)^Note to editor:/,$d;
        /(?i)^Next steps:/,$d;
        /(?i)^Next chapter:/,$d;
        /(?i)^Word count:/,$d;
        /(?i)^Chapter length:/,$d;
        /(?i)^This draft (meets|satisfies|fulfills)/,$d;
        /(?i)^As requested, this chapter/,$d;
        /(?i)^END OF CHAPTER/,$d;
    ')
    
    # Remove first heading lines if they match common chapter title patterns to avoid duplicates
    FORMATTED_CONTENT=$(echo "$CLEAN_CONTENT" | sed '1,3{/^# /d; /^\*\*/d; /^Chapter [0-9]/d;}' )

    # Further formatting for subsections
    FORMATTED_CONTENT=$(echo "$FORMATTED_CONTENT" | sed -E 's/^([*][*][^:]+:[*][*]) ([A-Z]) /\1\n\2 /g' | sed -E 's/^[*][*]([^:]+):[*][*]/## \1/g')

    # Append cleaned content
    echo "$FORMATTED_CONTENT" >> "$MANUSCRIPT_FILE"
    
    echo "" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    
    # Calculate word count and store it
    CHAPTER_WORDS=$(wc -w < "$CHAPTER_FILE")
    echo "$CHAPTER_NUM:$CHAPTER_WORDS" >> "$CHAPTER_WORD_COUNTS_FILE"
    TOTAL_WORDS=$((TOTAL_WORDS + CHAPTER_WORDS))
    
    echo "✅ Chapter $CHAPTER_NUM added ($CHAPTER_WORDS words)"
done

echo ""

# Create a separate metadata file instead of adding it to the manuscript
METADATA_STATS_FILE="${EXPORTS_DIR}/book_metadata_stats.md"

# Write metadata to separate file
cat << EOF > "$METADATA_STATS_FILE"
# Book Statistics & Metadata

## Content Overview
- **Title:** $BOOK_TITLE
- **Author:** $AUTHOR
- **Publisher:** $PUBLISHER
- **Total Chapters:** ${#CHAPTER_FILES[@]}
- **Total Word Count:** $TOTAL_WORDS words
- **Average Chapter Length:** $((TOTAL_WORDS / ${#CHAPTER_FILES[@]})) words
- **Estimated Page Count:** $((TOTAL_WORDS / 250)) pages (250 words/page)
- **Version Used:** $VERSION_NAME
- **Generated:** $(date +"%B %d, %Y at %I:%M %p")

## Plagiarism Check Summary
EOF

# Add plagiarism checking summary if reports exist
PLAGIARISM_REPORTS=($(ls "${BOOK_DIR}"/chapter_*_plagiarism_report.md 2>/dev/null))
BACKUP_FILES=($(ls "${BOOK_DIR}"/chapter_*.md.backup_* 2>/dev/null))

if [ ${#PLAGIARISM_REPORTS[@]} -gt 0 ]; then
    echo "- **Plagiarism Checks Performed:** ${#PLAGIARISM_REPORTS[@]} chapters" >> "$METADATA_STATS_FILE"
    echo "- **Chapters Rewritten for Originality:** ${#BACKUP_FILES[@]}" >> "$METADATA_STATS_FILE"
    
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
        echo "- **Average Originality Score:** $AVG_ORIGINALITY/10" >> "$METADATA_STATS_FILE"
        
        if [ $AVG_ORIGINALITY -ge 8 ]; then
            echo "- **Originality Assessment:** Excellent (98%+ original content)" >> "$METADATA_STATS_FILE"
        elif [ $AVG_ORIGINALITY -ge 6 ]; then
            echo "- **Originality Assessment:** Good (85%+ original content)" >> "$METADATA_STATS_FILE"
        else
            echo "- **Originality Assessment:** Acceptable (manual review recommended)" >> "$METADATA_STATS_FILE"
        fi
    fi
else
    echo "- **Plagiarism Checking:** Not performed or reports not found" >> "$METADATA_STATS_FILE"
fi

cat << EOF >> "$METADATA_STATS_FILE"

## Chapter Breakdown
EOF

# Add detailed chapter statistics - reuse stored word counts
for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" | sed -E 's/chapter_([0-9]+).*/\1/')
    CHAPTER_WORDS=$(grep "^$CHAPTER_NUM:" "$CHAPTER_WORD_COUNTS_FILE" | cut -d: -f2)
    
    # Get clean chapter title (simplified)
    CHAPTER_TITLE=$(head -5 "$CHAPTER_FILE" | grep -E "^#|^\*\*" | head -1 | sed 's/^#\s*//; s/^\*\*\(.*\)\*\*$/\1/' | cut -c1-50)
    [ -z "$CHAPTER_TITLE" ] && CHAPTER_TITLE="Chapter $CHAPTER_NUM"
    
    echo "- **Chapter $CHAPTER_NUM:** $CHAPTER_WORDS words - $CHAPTER_TITLE..." >> "$METADATA_STATS_FILE"
done

# Clean up temporary file
rm -f "$CHAPTER_WORD_COUNTS_FILE"

cat << EOF >> "$METADATA_STATS_FILE"

## File Information
- **Source Directory:** $(basename "$BOOK_DIR")
- **Outline File:** $(basename "$OUTLINE_FILE")
- **Manuscript File:** $(basename "$MANUSCRIPT_FILE")
- **Compilation Date:** $(date)
EOF

# Add a simple end note to the manuscript instead
cat << EOF >> "$MANUSCRIPT_FILE"
\newpage
\section{}
---

*Copyright © $PUBLICATION_YEAR $AUTHOR. All rights reserved.*
*Published by $PUBLISHER*
EOF

# If a back cover was generated, include it as the final page
if [ -n "$BACK_COVER" ] && [ -f "$BACK_COVER" ]; then
    echo "" >> "$MANUSCRIPT_FILE"
    echo "" >> "$MANUSCRIPT_FILE"
    echo "![]($(basename "$BACK_COVER"))" >> "$MANUSCRIPT_FILE"
    echo "\thispagestyle{empty}" >> "$MANUSCRIPT_FILE"
    # Copy back cover to exports directory only if different
    if [ "$BACK_COVER" != "$EXPORTS_DIR/$(basename "$BACK_COVER")" ]; then
        cp "$BACK_COVER" "$EXPORTS_DIR/"
    fi
fi

celebration "Manuscript Complete!"

echo "✅ Manuscript created: $(basename "$MANUSCRIPT_FILE")"
echo "📊 Total words: $TOTAL_WORDS"
echo "📄 Estimated pages: $((TOTAL_WORDS / 250))"

# Define CSS for HTML and EPUB formats
BOOK_CSS="
body { 
  font-family: 'Palatino', 'Georgia', serif; 
  line-height: 1.6;
  max-width: 800px; 
  margin: auto;
  padding: 20px;
  text-align: justify;
  font-size: 12pt;
}
h1.chapter-title {
  text-align: center;
  font-size: 24pt;
  margin-top: 60px;
  margin-bottom: 60px;
  font-weight: bold;
  page-break-before: always;
}
.toc-container {
  page-break-after: always;
}
.toc-header {
  text-align: center;
  font-size: 24pt;
  margin-top: 60px;
  margin-bottom: 40px;
}
h2 { 
  margin-top: 40px;
  margin-bottom: 20px;
  font-size: 18pt;
}
h3 { 
  margin-top: 30px;
  margin-bottom: 15px;
  font-size: 16pt;
}
.title { font-size: 28pt; text-align: center; }
.author { font-size: 16pt; text-align: center; }
.date { font-size: 14pt; text-align: center; }
p {
  margin-bottom: 15px;
  orphans: 3;
  widows: 3;
}
.chapter {
  display: block;
  height: 50px;
}
"

# Create a CSS file for styling
echo "$BOOK_CSS" > "$EXPORTS_DIR/book.css"

# Function to generate ebook formats
generate_ebook_format() {
    local format="$1"
    local input_file="$2"
    local title="$3"
    local metadata="$4"
    local css="$5"
    local cover="$6"
    local output_dir="$7"
    local output_file=""
    
    case "$format" in
        epub)
            output_file="${output_dir}/$(basename "$input_file" .md).epub"
            echo "📚 Generating EPUB format..."
            
            # Ensure we have a valid cover image path
            if [ -n "$cover" ] && [ -f "$cover" ]; then
                # Get just the filename
                local cover_basename=$(basename "$cover")
                
                # Make sure it exists in the output directory
                if [ ! -f "${output_dir}/${cover_basename}" ]; then
                    echo "   🖼️ Copying cover to exports directory..."
                    cp "$cover" "${output_dir}/"
                fi
                
                # Update cover path to the file in the output directory
                cover="${output_dir}/${cover_basename}"
                
                echo "   🖼️ Using cover: ${cover_basename}"
            else
                echo "   ⚠️ No valid cover image found"
                cover=""
            fi
            
            # Generate EPUB with cover if we have one
            if [ -n "$cover" ] && [ -f "$cover" ]; then
                # Run pandoc from the output directory so image paths resolve correctly
                (cd "$output_dir" && pandoc -f markdown -t epub3 \
                    --epub-cover-image="$(basename "$cover")" \
                    --css="$(basename "$css")" \
                    --metadata-file="$(basename "$metadata")" \
                    --split-level=1 \
                    -o "$(basename "$output_file")" "$(basename "$input_file")")
            else
                # Run pandoc from the output directory so image paths resolve correctly
                (cd "$output_dir" && pandoc -f markdown -t epub3 \
                    --css="$(basename "$css")" \
                    --metadata-file="$(basename "$metadata")" \
                    --split-level=1 \
                    -o "$(basename "$output_file")" "$(basename "$input_file")")
            fi
            
            echo "✅ EPUB created: $(basename "$output_file")"
            return 0
            ;;
            
        pdf)
            output_file="${output_dir}/$(basename "$input_file" .md).pdf"
            echo "📄 Generating PDF format..."
            
            # Try direct PDF generation first (simplest approach)
            (cd "$output_dir" && pandoc -f markdown -t pdf --pdf-engine=lualatex \
                --metadata-file="$(basename "$metadata")" \
                -o "$(basename "$output_file")" "$(basename "$input_file")") && {
                echo "✅ PDF created: $(basename "$output_file")"
                return 0
            }
            
            echo "⚠️  Standard PDF generation failed, creating print-friendly HTML instead..."
            html_output="${output_dir}/$(basename "$input_file" .md)_print.html"
            
            # Create a nice print-friendly HTML version
            (cd "$output_dir" && pandoc -f markdown -t html5 \
                --standalone \
                --metadata-file="$(basename "$metadata")" \
                --css="$(basename "$css")" \
                -o "$(basename "$html_output")" "$(basename "$input_file")")
            
            # Add print-specific CSS
            cat >> "$css" << EOF

/* Print-specific styles */
@media print {
    @page {
        margin: 1in;
        @bottom-center {
            content: counter(page);
        }
    }
    body {
        font-family: "Palatino", "Georgia", serif;
        font-size: 12pt;
        line-height: 1.5;
    }
    h1 {
        page-break-before: always;
    }
    h1.chapter-title {
        margin-top: 3in;
        text-align: center;
        font-size: 24pt;
    }
    h2, h3 {
        page-break-after: avoid;
    }
    p {
        widows: 3;
        orphans: 3;
    }
}
EOF
            
            echo "✅ Print-ready HTML created: $(basename "$html_output")"
            echo "   ℹ️  Open this file in a browser and use Print → Save as PDF"
            echo "   📄 PDF conversion unsuccessful - missing required tools"
            
            return 0
            ;;
            
        html)
            output_file="${output_dir}/$(basename "$input_file" .md).html"
            echo "🌐 Generating HTML format..."
            
            # CSS file should already be in the output directory
            local css_basename=$(basename "$css")
            
            (cd "$output_dir" && pandoc -f markdown -t html5 \
                --standalone \
                --metadata-file="$(basename "$metadata")" \
                --css="$css_basename" \
                -o "$(basename "$output_file")" "$(basename "$input_file")")
            
            echo "✅ HTML created: $(basename "$output_file")"
            return 0
            ;;
            
        mobi)
            if command -v ebook-convert &> /dev/null; then
                local epub_file="${output_dir}/$(basename "$input_file" .md).epub"
                output_file="${output_dir}/$(basename "$input_file" .md).mobi"
                
                # Check if EPUB exists, create if needed
                if [ ! -f "$epub_file" ]; then
                    generate_ebook_format "epub" "$input_file" "$title" "$metadata" "$css" "$cover" "$output_dir"
                fi
                
                echo "� Converting to MOBI format (for Kindle)..."
                ebook-convert "$epub_file" "$output_file" \
                    --title="$title" \
                    --authors="$AUTHOR" \
                    --publisher="$PUBLISHER" \
                    --cover="$cover" \
                    --language="en" \
                    --isbn="$ISBN"
                
                echo "✅ MOBI created: $(basename "$output_file")"
            else
                echo "⚠️  Calibre tools not found. Install with: brew install calibre"
                return 1
            fi
            ;;
            
        azw3)
            if command -v ebook-convert &> /dev/null; then
                local epub_file="${output_dir}/$(basename "$input_file" .md).epub"
                output_file="${output_dir}/$(basename "$input_file" .md).azw3"
                
                # Check if EPUB exists, create if needed
                if [ ! -f "$epub_file" ]; then
                    generate_ebook_format "epub" "$input_file" "$title" "$metadata" "$css" "$cover" "$output_dir"
                fi
                
                echo "📚 Converting to AZW3 format (enhanced Kindle)..."
                ebook-convert "$epub_file" "$output_file" \
                    --title="$title" \
                    --authors="$AUTHOR" \
                    --publisher="$PUBLISHER" \
                    --cover="$cover" \
                    --language="en" \
                    --isbn="$ISBN"
                
                echo "✅ AZW3 created: $(basename "$output_file")"
            else
                echo "⚠️  Calibre tools not found. Install with: brew install calibre"
                return 1
            fi
            ;;
            
        *)
            echo "⚠️  Unknown format: $format"
            return 1
            ;;
    esac
}

# Generate requested formats
echo ""
echo "📚 Exporting book in requested formats..."

# Set default cover if none provided
if [ -z "$COVER_IMAGE" ]; then
    COVER_IMAGE="$EXPORTS_DIR/generated_cover.jpg"
    if [ ! -f "$COVER_IMAGE" ] && [ "$GENERATE_COVER" = true ]; then
    # Generate both front and back covers and set COVER_IMAGE/BACK_COVER
    generate_book_cover "$BOOK_TITLE" "$EXPORTS_DIR" || true
    fi
fi

# Copy manuscript to exports directory and use the copy for pandoc so image paths resolve
cp "$MANUSCRIPT_FILE" "$EXPORTS_DIR/"
MANUSCRIPT_FILE="$EXPORTS_DIR/$(basename "$MANUSCRIPT_FILE")"

# Post-process manuscript to ensure page-break tokens become valid pandoc raw LaTeX blocks
echo "🔧 Post-processing manuscript for PDF page breaks..."
# Replace PAGE_BREAK_TOKEN if present
if grep -q "PAGE_BREAK_TOKEN" "$MANUSCRIPT_FILE" 2>/dev/null; then
    perl -0777 -pe 's/PAGE_BREAK_TOKEN/\\n\\newpage/g' -i "$MANUSCRIPT_FILE"
    echo "   ✅ Replaced PAGE_BREAK_TOKEN with raw LaTeX blocks"
fi
# Also replace any literal {=latex}\n\newpage\n occurrences (escaped sequences)
if grep -q "\\n\\newpage\\n" "$MANUSCRIPT_FILE" 2>/dev/null; then
    perl -0777 -pe 's/\\n\\newpage\\n/\\\\newpage\n/g' -i "$MANUSCRIPT_FILE"
    echo "   ✅ Fixed escaped page-break sequences"
fi

# Export in requested format(s)
case $OUTPUT_FORMAT in
    all)
        echo "🚀 Generating requested ebook formats (fast=$FAST)..."
        # Run epub/pdf/html in parallel to save wall time
        generate_ebook_format "epub" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR" &
        generate_ebook_format "pdf" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR" &
        generate_ebook_format "html" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR" &
        wait

        # MOBI/AZW3 conversions are slow (Calibre). Skip in fast mode, else run in background.
        if [ "$FAST" = false ]; then
            if command -v ebook-convert &> /dev/null; then
                generate_ebook_format "mobi" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR" &
                generate_ebook_format "azw3" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR" &
                wait
            else
                echo "⚠️ Calibre not found; skipping mobi/azw3 conversions"
            fi
        else
            echo "⚡ Fast mode: skipped mobi/azw3 conversions"
        fi
        ;;
    epub|pdf|html|mobi|azw3)
        echo "📚 Generating $OUTPUT_FORMAT format..."
        generate_ebook_format "$OUTPUT_FORMAT" "$MANUSCRIPT_FILE" "$BOOK_TITLE" "$METADATA_FILE" "$EXPORTS_DIR/book.css" "$COVER_IMAGE" "$EXPORTS_DIR"
        ;;
    markdown)
        echo "📝 Manuscript created in markdown format only."
        ;;
    *)
        echo "❌ Unknown output format: $OUTPUT_FORMAT"
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
find "$EXPORTS_DIR" -type f | sort

echo ""
echo "🚀 Ready for publishing!"
echo "   📂 Exports directory: $EXPORTS_DIR"
echo "   📱 For e-readers: Use EPUB format"
echo "   📱 For Kindle: Use MOBI or AZW3 format"
echo "   📄 For print: Use PDF format"
echo "   🌐 For websites: Use HTML format"
echo "   ✏️ For editing: Use the markdown file"
echo ""
echo "📚 Publishing Platforms:"
echo "   📕 Amazon KDP: https://kdp.amazon.com (upload EPUB or MOBI)"
echo "   📗 Apple Books: https://authors.apple.com (upload EPUB)"
echo "   📘 Barnes & Noble Press: https://press.barnesandnoble.com (upload EPUB)"
echo "   📙 Kobo: https://kobo.com/writinglife (upload EPUB)"
echo "   📓 Google Play Books: https://play.google.com/books/publish (upload EPUB)"
echo "   📔 Smashwords: https://smashwords.com (upload EPUB)"
echo "   📒 Draft2Digital: https://draft2digital.com (upload EPUB)"
echo ""
echo "✅ Your book is ready for the world!"