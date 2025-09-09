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
    version          - Version: 1=original, 2=edited, 3=final (default: 3)

OPTIONS:
    --author "Name"   - Set author name (default: AI-Assisted Author)
    --cover "path"    - Path to cover image (JPG/PNG/PDF, min 1600x2560 pixels)
    --backcover "path" - Path to back cover image (JPG/PNG/PDF, min 1600x2560 pixels)
    --isbn "number"   - Set ISBN for the book
    --publisher "name" - Set publisher name
    --year "YYYY"     - Publication year (default: current year)
    --generate-cover  - Auto-generate a simple cover if none provided

EXAMPLES:
    $0                        # Auto-detect most recent book
    $0 all                    # Export most recent book in all formats
    $0 epub --author "Jane"   # Export as EPUB with custom author
    $0 ./book_outputs/my-book epub 2 --cover "cover.jpg" --backcover "backcover.pdf" # Specify book and format

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
VERSION="3"
COVER_IMAGE=""
BACK_COVER=""
AUTHOR="AI-Assisted Author"
FAST=false
BACK_COVER_IMAGE=""
ISBN=""
PUBLISHER="Speedy Quick Publishing"
PUBLICATION_YEAR=$(date +"%Y")
GENERATE_COVER=false
ATTACH_COVER=false

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

# date: "$PUBLICATION_YEAR"
    
    cat > "$metadata_file" << EOF
---
title: "$title"
subtitle: "$SUB_TITLE"
author: "$AUTHOR"
rights: "Copyright © $PUBLICATION_YEAR $AUTHOR"
language: "en-US"
publisher: "$PUBLISHER"
papersize: 6in,9in
geometry: "top=2in, bottom=2in, inner=2in, outer=2in"
identifier:
  - scheme: ISBN
    text: "${ISBN:-[No ISBN Provided]}"
header-includes:
  - \usepackage{titlesec}
  - \titleformat{\section}[block]{\bfseries\Huge\centering}{}{0pt}{}
  - \titleformat{\subsection}[block]{\bfseries\Large\centering}{}{0pt}{}
  - \let\cleardoublepage\clearpage
  - \renewcommand{\chapterbreak}{\clearpage}
  - \usepackage[hidelinks]{hyperref}
  
$([ -n "$cover_basename" ] && echo "cover-image: \"$cover_basename\"")
---
EOF

    echo "$metadata_file"
}

# Function to generate a random author pen name from predefined list
generate_author_pen_name() {
    echo "🖋️ Selecting random author pen name..."
    
    # Use a predefined list of creative pen names
    local pen_names=(
        # "Elara Morgan"
        # "J.T. Blackwood"
        # "Sophia Wyndham"
        # "Xavier Stone"
        # "Leo Hawthorne"
        # "Isabella Quinn"
        # "Nathaniel Grey"
        # "Olivia Sterling"
        "Liam West"
        # "Mia Rivers"
        # "Noah Bennett"
        # "Ava Sinclair"
        # "Oliver James"
        # "Charlotte Wells"
        # "Jameson Blake"
        # "Luna Rivers"
        # "Ethan Cross"
        # "Zoe Hart"
        # "Mason Brooks"
        # "Amelia Rivers"
        # "Aiden Chase"
        # "Jasper Knight"
        # "Cassandra Vale"
        # "Dahlia Black"
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

    # Check for author photo
    local author_photo_path="$SCRIPT_DIR/author-photo.png"
    local author_photo_exports_path="${assets_dir}/author-photo.png"

    if [ -f "$author_photo_path" ]; then
        # Copy author photo to exports directory
        cp "$author_photo_path" "$author_photo_exports_path"
    else
        # Check in current directory
        if [ -f "author-photo.png" ]; then
            cp "author-photo.png" "$author_photo_exports_path"
        else
            echo "⚠️ Author photo not found, creating a placeholder"
            # Create a placeholder author photo
            $img_cmd -size 300x300 xc:white -gravity center \
                -pointsize 24 -fill black -annotate +0+0 "Author Photo" \
                "$author_photo_exports_path"
        fi
    fi

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
    BACK_COVER_IMAGE="$back_file"
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
    BACK_COVER_IMAGE="$back_file"
    return 0
}

# Generate multiple book covers via OpenAI Images API and allow selection
generate_book_covers() {
    local BOOK_TITLE="$1"
    local AUTHOR="$2"
    local DESCRIPTION="$3"
    local NUM_IMAGES="${4:-3}"
    local OUTPUT_DIR="${5:-.}"

    if [ -z "$OPENAI_API_KEY" ]; then
        echo "⚠️ OPENAI_API_KEY not set; cannot generate AI covers."
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "⚠️ jq is required to parse the image API response. Install jq or set GENERATE_COVER=false to use ImageMagick fallback."
        return 1
    fi

    mkdir -p "$OUTPUT_DIR"
    local PROMPT
    PROMPT="Generate a high-quality minimalist book cover in flat/vector style for a book titled '$BOOK_TITLE' by $AUTHOR. The cover should feature a central icon or image that represents the book's theme: $DESCRIPTION. Use solid colors, clean lines, and a minimalist aesthetic. Place the title '$BOOK_TITLE' centered above the main image in a large sans-serif font and the author '$AUTHOR' centered below in a smaller font."

    echo "🎨 Requesting $NUM_IMAGES cover image(s) from the image API..."

    # Build JSON request body safely using jq to avoid shell quoting issues
    REQUEST_BODY=$(jq -nc --arg prompt "$PROMPT" --arg size "1024x1024" --argjson n "$NUM_IMAGES" '
        {prompt: $prompt, n: $n, size: $size}
    ')

    RESPONSE=$(curl -s https://api.openai.com/v1/images/generations \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$REQUEST_BODY")

    echo "$RESPONSE"

    if [ -z "$RESPONSE" ]; then
        echo "⚠️ No response from image API"
        return 1
    fi

    # Save images
    local saved=()
    for i in $(seq 0 $((NUM_IMAGES-1))); do
        IMAGE_B64=$(echo "$RESPONSE" | jq -r ".data[$i].b64_json" 2>/dev/null)
        if [ -z "$IMAGE_B64" ] || [ "$IMAGE_B64" = "null" ]; then
            echo "⚠️ Image $((i+1)) missing from response"
            continue
        fi
        SAFE_TITLE=$(echo "$BOOK_TITLE" | tr ' /' '_' | tr -cd '[:alnum:]_-')
        IMAGE_FILE="$OUTPUT_DIR/${SAFE_TITLE}_cover_$((i+1)).png"
        echo "$IMAGE_B64" | base64 --decode > "$IMAGE_FILE"
        saved+=("$IMAGE_FILE")
        echo "✅ Saved cover $((i+1)): $IMAGE_FILE"
    done

    if [ ${#saved[@]} -eq 0 ]; then
        echo "⚠️ No covers saved"
        return 1
    fi

    # If running in non-interactive mode, pick the first image
    if [ ! -t 0 ]; then
        CHOICE=1
        echo "Non-interactive shell detected; selecting first generated cover: ${saved[0]}"
    else
        echo "Available covers:"
        local idx=1
        for f in "${saved[@]}"; do
            echo "  $idx) $(basename "$f")"
            idx=$((idx+1))
        done
        echo "Enter the number of the cover to use (1-${#saved[@]}). Press ENTER to choose 1:";
        read -r CHOICE
        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#saved[@]} ]; then
            CHOICE=1
        fi
    fi

    CHOSEN_FILE="${saved[$((CHOICE-1))]}"
    echo "🎯 Selected cover: $CHOSEN_FILE"

    # Export chosen cover path to the caller via COVER_IMAGE var
    COVER_IMAGE="$CHOSEN_FILE"
    return 0
}

# Attach an existing image file as the book cover (validate and optionally resize)
attach_existing_cover() {
    local provided_path="$1"
    local output_dir="$2"

    if [ -z "$provided_path" ]; then
        echo "⚠️ No cover path provided to attach_existing_cover"
        return 1
    fi

    if [ ! -f "$provided_path" ]; then
        echo "❌ Provided cover image not found: $provided_path"
        return 1
    fi

    # Ensure ImageMagick exists for optional resizing
    local img_cmd="convert"
    if command -v magick &> /dev/null; then
        img_cmd="magick"
    fi

    mkdir -p "$output_dir"
    local safe_basename="$(basename "$provided_path")"
    local dest="$output_dir/$safe_basename"

    # Copy first, then optionally resize if smaller than required
    cp -f "$provided_path" "$dest" 2>/dev/null || { echo "❌ Failed to copy cover image"; return 1; }

    # Check dimensions and resize only if smaller than 1024x1536
    if command -v identify &> /dev/null; then
        dims=$(identify -format "%wx%h" "$dest" 2>/dev/null || true)
        if [ -n "$dims" ]; then
            width=${dims%x*}
            height=${dims#*x}
            if [ "$width" -lt 1024 ] || [ "$height" -lt 1536 ]; then
                echo "⚠️ Cover image smaller than recommended 1024x1536 — resizing with ImageMagick upscale (may reduce quality)"
                $img_cmd "$dest" -resize 1024x1536\! "$dest" 2>/dev/null || true
            fi
        fi
    fi

    COVER_IMAGE="$dest"
    echo "✅ Attached existing cover: $(basename "$COVER_IMAGE")"
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
        --backcover)
            BACK_COVER_IMAGE="$2"
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
        --add-cover)
            # Accept a path to an existing image and mark it to be attached as the cover
            COVER_IMAGE="$2"
            ATTACH_COVER=true
            shift 2
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
BOOK_TITLE=$(head -n 1 "$OUTLINE_FILE" | sed 's/^# //; s/^BOOK TITLE:[[:space:]]*//' | tr -d '\r')

if [ -z "$BOOK_TITLE" ]; then
    BOOK_TITLE="Generated Book $(date +%Y-%m-%d)"
fi
# Extract subtitle for layout
SUB_TITLE=$(head -n 2 "$OUTLINE_FILE" | tail -n 1 | sed 's/^## //; s/^SUBTITLE:[[:space:]]*//' | tr -d '\r')

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

# Copy author photo into exports dir for inclusion in manuscript
AUTHOR_PHOTO_SRC="$SCRIPT_DIR/author-photo.png"
if [ -f "$AUTHOR_PHOTO_SRC" ]; then
    cp -f "$AUTHOR_PHOTO_SRC" "$EXPORTS_DIR/$(basename "$AUTHOR_PHOTO_SRC")" 2>/dev/null || true
fi
AUTHOR_PHOTO_BASENAME="$(basename "$AUTHOR_PHOTO_SRC")"

# Copy icon photo into exports dir for inclusion in manuscript
ICON_PHOTO_SRC="$SCRIPT_DIR/icon.png"
if [ -f "$ICON_PHOTO_SRC" ]; then
    cp -f "$ICON_PHOTO_SRC" "$EXPORTS_DIR/$(basename "$ICON_PHOTO_SRC")" 2>/dev/null || true
fi
ICON_BASENAME="$(basename "$ICON_PHOTO_SRC")"

# Copy the QR code image into exports dir for inclusion in manuscript
QR_CODE_SRC="$SCRIPT_DIR/qr-code.png"
if [ -f "$QR_CODE_SRC" ]; then
    cp -f "$QR_CODE_SRC" "$EXPORTS_DIR/$(basename "$QR_CODE_SRC")" 2>/dev/null || true
fi
QR_CODE="$(basename "$QR_CODE_SRC")"

# Copy the back cover pdf into exports dir for inclusion in manuscript
BACK_COVER_PDF_SRC="$SCRIPT_DIR/back-cover.png"
if [ -f "$BACK_COVER_PDF_SRC" ]; then
    cp -f "$BACK_COVER_PDF_SRC" "$EXPORTS_DIR/$(basename "$BACK_COVER_PDF_SRC")" 2>/dev/null || true
fi
BACK_COVER_PDF_BASENAME="$(basename "$BACK_COVER_PDF_SRC")"

# Copy back cover 1 image into exports dir for inclusion in manuscript
BACK_COVER1_SRC="$SCRIPT_DIR/back-cover-1.png"
if [ -f "$BACK_COVER1_SRC" ]; then
    cp -f "$BACK_COVER1_SRC" "$EXPORTS_DIR/$(basename "$BACK_COVER1_SRC")" 2>/dev/null || true
fi
BACK_COVER1_BASENAME="$(basename "$BACK_COVER1_SRC")"

# Copy cover 1 image into exports dir for inclusion in manuscript
COVER1_SRC="$SCRIPT_DIR/cover-1.png"
if [ -f "$COVER1_SRC" ]; then
    cp -f "$COVER1_SRC" "$EXPORTS_DIR/$(basename "$COVER1_SRC")" 2>/dev/null || true
fi
COVER1_BASENAME="$(basename "$COVER1_SRC")"

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
    COVER_IMAGE="$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
elif [ "$ATTACH_COVER" = true ]; then
    # Attempt to attach the provided cover image (path was set during args parsing)
    attach_existing_cover "$COVER_IMAGE" "$EXPORTS_DIR" || true
    if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
        # If attach_existing_cover set COVER_IMAGE to exports path, ensure it is used
        if [ "$COVER_IMAGE" != "$EXPORTS_DIR/$(basename "$COVER_IMAGE")" ]; then
            # ensure it's copied into exports dir
            cp -f "$COVER_IMAGE" "$EXPORTS_DIR/" 2>/dev/null || true
            COVER_IMAGE="$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
        fi
    fi
elif [ "$GENERATE_COVER" = true ]; then
    # Prefer AI-generated multiple covers if OpenAI key and jq are available
    if [ -n "$OPENAI_API_KEY" ] && command -v jq >/dev/null 2>&1; then
        # DESCRIPTION: use SUMMARY or a short excerpt as prompt description if available
        DESC="${SUMMARY:-$BOOK_TITLE}"
        generate_book_covers "$BOOK_TITLE" "$AUTHOR" "$DESC" 3 "$EXPORTS_DIR"
        # generate_book_covers sets COVER_IMAGE to the chosen file path on success
        if [ -n "$COVER_IMAGE" ] && [ -f "$COVER_IMAGE" ]; then
            echo "🖼️ Using selected AI cover: $COVER_IMAGE"
            cp "$COVER_IMAGE" "$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
            COVER_IMAGE="$EXPORTS_DIR/$(basename "$COVER_IMAGE")"
        else
            echo "⚠️ AI cover selection failed or was skipped; falling back to ImageMagick cover generation"
            generate_book_cover "$BOOK_TITLE" "$EXPORTS_DIR"
        fi
    else
        generate_book_cover "$BOOK_TITLE" "$EXPORTS_DIR"
    fi
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

# Process back cover image if provided
if [ -n "$BACK_COVER_IMAGE" ] && [ -f "$BACK_COVER_IMAGE" ]; then
    echo "🖼️ Using provided back cover: $BACK_COVER_IMAGE"
    cp "$BACK_COVER_IMAGE" "$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")"
    BACK_COVER_IMAGE="$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")"
elif [ "$ATTACH_BACK_COVER" = true ]; then
    # Attempt to attach the provided cover image (path was set during args parsing)
    attach_existing_cover "$BACK_COVER_IMAGE" "$EXPORTS_DIR" || true
    if [ -n "$BACK_COVER_IMAGE" ] && [ -f "$BACK_COVER_IMAGE" ]; then
        # If attach_existing_cover set BACK_COVER_IMAGE to exports path, ensure it is used
        if [ "$BACK_COVER_IMAGE" != "$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")" ]; then
            # ensure it's copied into exports dir
            cp -f "$BACK_COVER_IMAGE" "$EXPORTS_DIR/" 2>/dev/null || true
            BACK_COVER_IMAGE="$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")"
        fi
    fi
fi

# Ensure back cover image is properly set up before creating metadata
if [ -n "$BACK_COVER_IMAGE" ] && [ -f "$BACK_COVER_IMAGE" ]; then
    # Copy cover to exports directory if needed
    if [ "$BACK_COVER_IMAGE" != "$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")" ]; then
        cp "$BACK_COVER_IMAGE" "$EXPORTS_DIR/"
    fi
    BACK_COVER_IMAGE="$EXPORTS_DIR/$(basename "$BACK_COVER_IMAGE")"
    echo "📄 Back cover image prepared for ebook: $(basename "$BACK_COVER_IMAGE")"
fi

# Create metadata file for ebook exports
METADATA_FILE=$(generate_metadata "$BOOK_TITLE" "$EXPORTS_DIR")
# Extract subtitle for layout
SUB_TITLE=$(head -n 2 "$OUTLINE_FILE" | tail -n 1 | sed 's/^## //; s/^SUBTITLE:[[:space:]]*//' | tr -d '\r')

# Extract keywords for layout
# KEYWORDS=$(head -n 3 "$OUTLINE_FILE" | tail -n 1 | sed 's/^## //; s/^KEYWORDS:[[:space:]]*//' | tr -d '\r')

# $BOOK_TITLE


# date: "$PUBLICATION_YEAR"
# Start manuscript with complete front matter using markdown and LaTeX page breaks

# ---
# title: "$BOOK_TITLE"
# subtitle: "$SUB_TITLE"
# author: "$AUTHOR"
# rights: "Copyright © $PUBLICATION_YEAR $AUTHOR"
# language: "en-US"
# publisher: "$PUBLISHER"
# description: "$DESCRIPTION"
# subject: ""
# toc-title: "Table of Contents"
# header-includes:
#   - \usepackage{titlesec}
#   - \titleformat{\section}[block]{\bfseries\Huge\centering}{}{0pt}{}
#   - \titleformat{\subsection}[block]{\bfseries\Large\centering}{}{0pt}{}
# ---

## $SUB_TITLE 
### By $AUTHOR
#### Copyright © $PUBLICATION_YEAR

cat << EOF > "$MANUSCRIPT_FILE"

\renewcommand{\contentsname}{\Huge Table of Contents}
\thispagestyle{empty}
\newpage
\thispagestyle{empty}
\clearpage\vspace*{\fill}

::: {.centered}
\centering

$(if [ -f "$EXPORTS_DIR/$ICON_BASENAME" ]; then echo "![]($ICON_BASENAME){ width=40% } "; fi)

\raggedright
\flushleft
:::
\vspace{3em}

\begin{center}
{\fontsize{32}{36}\selectfont\bfseries $BOOK_TITLE}
\end{center}
\vspace{3em}
\begin{center}
{\fontsize{24}{28}\selectfont\bfseries $SUB_TITLE}
\end{center}
\vspace{2em}
\begin{center}
{\fontsize{18}{20}\selectfont\bfseries By $AUTHOR}
\end{center}
\begin{center}
{\fontsize{14}{16}\selectfont\bfseries Copyright © $PUBLICATION_YEAR}
\end{center}

## $SUB_TITLE
### By $AUTHOR
#### Copyright © $PUBLICATION_YEAR

\centering
::: {.logo}
$(if [ -f "$EXPORTS_DIR/playfulpath.png" ]; then echo "![](playfulpath.png){ width=40% } "; fi)
:::
\raggedright
\flushleft
\vspace*{\fill}\clearpage

\newpage

::: {.pagebreak}
:::
::: {.fillspace}
:::
::: {.copyright}

\clearpage\vspace*{\fill}
\centering
$(if [ -f "$EXPORTS_DIR/$LOGO_BASENAME" ]; then echo "![]($LOGO_BASENAME){ width=25% } "; fi)

$(if [ -n "$ISBN" ]; then echo "ISBN: $ISBN"; fi)

**Copyright Notice**

All rights reserved. No part of this publication may be reproduced, distributed, or transmitted in any form or by any means, including photocopying, recording, or other electronic or mechanical methods, without the prior written permission of the publisher.

**Copyright © $PUBLICATION_YEAR $AUTHOR**

**$PUBLISHER**

\raggedright
\flushleft
:::

\newpage

\clearpage

\setcounter{tocdepth}{2}
\tableofcontents
\newpage

\clearpage

::: {.pagebreak}
:::

::: {.newpage}
:::

::: {.fillspace}
:::

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
    # For first chapter, don't add extra newpage since we're coming from TOC
    if [ $CHAPTER_COUNTER -eq 1 ]; then
        echo "" >> "$MANUSCRIPT_FILE"
        echo "<a id=\"chapter-$CHAPTER_NUM\" class=\"chapter\"></a>" >> "$MANUSCRIPT_FILE"
        echo "" >> "$MANUSCRIPT_FILE"
    else
        echo "" >> "$MANUSCRIPT_FILE"
        echo "\newpage" >> "$MANUSCRIPT_FILE"
        echo "" >> "$MANUSCRIPT_FILE"
        echo "<a id=\"chapter-$CHAPTER_NUM\" class=\"chapter\"></a>" >> "$MANUSCRIPT_FILE"
        echo "" >> "$MANUSCRIPT_FILE"
    fi

    # Look up chapter display title from the outline to avoid duplicated titles
    # First try markdown format (### Chapter N: Title)
    outline_line=$(grep -i -m1 -E "^###[[:space:]]+Chapter[[:space:]]+${CHAPTER_NUM}[:\. ]" "$OUTLINE_FILE" || true)
    
    # If not found, try older formats
    if [ -z "$outline_line" ]; then
        outline_line=$(grep -i -m1 -E "Chapter[[:space:]]+${CHAPTER_NUM}[:\. -]*.*" "$OUTLINE_FILE" || true)
    fi
    
    if [ -n "$outline_line" ]; then
        # First remove markdown prefix if present
        DISPLAY_TITLE=$(echo "$outline_line" | sed 's/^###[[:space:]]*//')
        
        # Then clean up the title
        DISPLAY_TITLE=$(echo "$DISPLAY_TITLE" | sed -E 's/^[[:space:]]*[Cc]hapter[[:space:]]+'${CHAPTER_NUM}'[:\. -]*//; s/^[[:space:]]*'${CHAPTER_NUM}'[\.)[:space:]-]*//')
        DISPLAY_TITLE=$(echo "$DISPLAY_TITLE" | sed -E 's/^[[:space:]]*[Cc]hapter[[:space:]]*[0-9]+[:\. -]*//i; s/^[[:space:]]*[0-9]+[\.)[:space:]-]*//')
        DISPLAY_TITLE=$(echo "$DISPLAY_TITLE" | sed 's/^ *//; s/ *$//')
        [ -z "$DISPLAY_TITLE" ] && DISPLAY_TITLE="Chapter ${CHAPTER_NUM}"
    else
        DISPLAY_TITLE="Chapter ${CHAPTER_NUM}"
    fi
    CLEAN_CHAPTER_TITLE=$(echo "$DISPLAY_TITLE" | sed -e "s/^Chapter $CHAPTER_NUM: //; s/^Chapter $CHAPTER_NUM //")

    # Split chapter title at first colon to create H1/H2/H3 structure
    if [[ "$CLEAN_CHAPTER_TITLE" == *":"* ]]; then
        # Extract part before first colon for the main chapter title and part after for subtitle
        CHAPTER_MAIN_TITLE=$(echo "$CLEAN_CHAPTER_TITLE" | cut -d: -f1 | sed 's/^ *//; s/ *$//')
        CHAPTER_SUBTITLE=$(echo "$CLEAN_CHAPTER_TITLE" | cut -d: -f2- | sed 's/^ *//; s/ *$//')

        # Use a single heading section for all title information
        echo "# Chapter $CHAPTER_NUM {.chapter-title}" >> "$MANUSCRIPT_FILE"
        echo "## $CHAPTER_MAIN_TITLE {.chapter-main-title}" >> "$MANUSCRIPT_FILE"
        echo "" >> "$MANUSCRIPT_FILE"
        # H3: subtitle (optional)
        if [ -n "$CHAPTER_SUBTITLE" ]; then
            echo "### $CHAPTER_SUBTITLE {.chapter-subtitle}" >> "$MANUSCRIPT_FILE"
        fi
    else
        # No colon found: Use CLEAN_CHAPTER_TITLE as the main title
        echo "# Chapter $CHAPTER_NUM {.chapter-title}" >> "$MANUSCRIPT_FILE"
        echo "## $CLEAN_CHAPTER_TITLE {.chapter-main-title}" >> "$MANUSCRIPT_FILE"
    fi
    echo "" >> "$MANUSCRIPT_FILE"

    # Process chapter content and clean it, but remove heading lines so we don't duplicate titles
    CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
    
    # First pass: Remove all metadata sections with comprehensive pattern matching
    # macOS sed doesn't support (?i) case-insensitive flag, so we'll use grep for case-insensitive filtering
    CLEAN_CONTENT=$(echo "$CHAPTER_CONTENT" | grep -v -i -E "^(PLAGIARISM|COPYRIGHT)[ _/]*ANALYSIS:?" | 
        grep -v -i -E "^(COPYRIGHT|PLAGIARISM)[ _/]*RISK:?" | 
        grep -v -i -E "^FLAGGED[ _]*SECTIONS:?" |
        grep -v -i -E "^(ISSUES|PROBLEMS)[ _]*FOUND:?" |
        grep -v -i -E "^WRITING[ _]*GUIDELINES:?" |
        grep -v -i -E "^DETAILED[ _]*ANALYSIS:?" |
        grep -v -i -E "^RECOMMENDATIONS?:?" |
        grep -v -i -E "^IMPORTANT[ _]*WORD[ _]*COUNT[ _]*REQUIREMENT:?" |
        grep -v -i -E "^REWRITING[ _]*REQUIREMENTS?:?" |
        grep -v -i -E "^The final answer is:" |
        grep -v -i -E "^\**The content needs to be rewritten" |
        grep -v -i -E "^\*\*WRITING[ _]*GUIDELINES:?\*\*" |
        grep -v -i -E "^\*\*PLAGIARISM[ _/]*ANALYSIS:?\*\*" |
        grep -v -i -E "^\*\*COPYRIGHT[ _]*ANALYSIS:?\*\*" |
        grep -v -i -E "^\*\*REWRITING[ _]*REQUIREMENTS:?\*\*" |
        grep -v -i -E "^ORIGINALITY[ _]*SCORE:?" |
        grep -v -i -E "^PLAGIARISM[ _]*RISK:?" |
        grep -v -i -E "^COPYRIGHT[ _]*RISK:?" |
        grep -v -i -E "^ISSUES[ _]*FOUND:?" |
        grep -v -i -E "^Chapter Rewrite:?" |
        grep -v -i -E "^Please rewrite the entire chapter" |
        grep -v -i -E "^NOTE TO WRITER:?" |
        grep -v -i -E "^STYLE NOTES?:?" |
        grep -v -i -E "^AI[ _]*GENERATED[ _]*CONTENT:?" |
        grep -v -i -E "^\*\*AI[ _]*GENERATED[ _]*CONTENT:?\*\*" |
        grep -v -i -E "^Generated with AI" |
        grep -v -i -E "^This content was generated by" |
        sed 's/Figure 1: Book Cover//g'
    )

    # Second pass: Remove trailing paragraphs that contain rewriting goals or prompt info
    # Since this requires complex pattern matching that's difficult with grep, we'll use awk instead
    CLEAN_CONTENT=$(echo "$CLEAN_CONTENT" | awk '
        BEGIN { skip = 0; content = ""; }
        tolower($0) ~ /^in this chapter(,| we)/ { skip = 1; next; }
        tolower($0) ~ /^this chapter (meets|follows|adheres to)/ { skip = 1; next; }
        tolower($0) ~ /^i have (written|created|completed)/ { skip = 1; next; }
        tolower($0) ~ /^the chapter (now|has been|is) (complete|written)/ { skip = 1; next; }
        tolower($0) ~ /^note: this chapter/ { skip = 1; next; }
        tolower($0) ~ /^note to editor:/ { skip = 1; next; }
        tolower($0) ~ /^next steps:/ { skip = 1; next; }
        tolower($0) ~ /^next chapter:/ { skip = 1; next; }
        tolower($0) ~ /^word count:/ { skip = 1; next; }
        tolower($0) ~ /^chapter length:/ { skip = 1; next; }
        tolower($0) ~ /^this draft (meets|satisfies|fulfills)/ { skip = 1; next; }
        tolower($0) ~ /^as requested, this chapter/ { skip = 1; next; }
        tolower($0) ~ /^end of chapter/ { skip = 1; next; }
        !skip { print $0; }
    ')
    
    # Remove duplicate chapter titles, including the formats we've seen in the example
    FORMATTED_CONTENT=$(echo "$CLEAN_CONTENT" | 
        # First, remove headings in the first few lines
        sed '1,5{/^# /d; /^\*\*/d; /^Chapter [0-9]/d;}' |
        # Remove any line that contains the full chapter title
        grep -v -F "$CLEAN_CHAPTER_TITLE" |
        # Remove any line that contains "Chapter N:" followed by the title
        grep -v -E "^Chapter ${CHAPTER_NUM}:.*${CLEAN_CHAPTER_TITLE}" |
        # Remove lines with just the chapter number and title
        grep -v -E "^Chapter ${CHAPTER_NUM}[[:space:]]+${CLEAN_CHAPTER_TITLE}"
    )

    # Further formatting for subsections
    # Avoid converting bold (**text**) into headings (prevents unwanted TOC entries).
    # Instead, remove bold markup while keeping the text inline.
    FORMATTED_CONTENT=$(echo "$FORMATTED_CONTENT" | sed -E 's/\*\*([^*]+)\*\*/\1/g')

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

# Function: insert extra sections (epilogue, glossary, discussion, appendices)
# "thank-you-readers.md"
insert_extra_sections() {
    local base_dir="$BOOK_DIR"
    local files=("epilogue.md" "glossary.md" "discussion.md" "appendices.md" "further-reading.md" "endnotes.md")
    for f in "${files[@]}"; do
        path="$base_dir/$f"
        if [ -f "$path" ]; then
        TITLE=$(grep -m1 -E '^# ' "$path" | sed 's/^# *//')
        [ -z "$TITLE" ] && TITLE="${f%.*}"  
            echo "📎 Inserting extra section: $f"
            echo "\pagebreak" >> "$MANUSCRIPT_FILE"
            echo "\newpage" >> "$MANUSCRIPT_FILE"
            echo "" >> "$MANUSCRIPT_FILE"
            if [ $path != "$base_dir/thank-you-readers.md" ]; then
                echo "# $TITLE" >> "$MANUSCRIPT_FILE"
            fi
            echo "" >> "$MANUSCRIPT_FILE"
            # Remove title from the path file
            tail -n +2 "$path" >> "$MANUSCRIPT_FILE"
            echo "\pagebreak" >> "$MANUSCRIPT_FILE"
            if [ "$path" == "$base_dir/epilogue.md" ]; then
                # Add a simple end note to the manuscript instead
                cat << EOF >> "$MANUSCRIPT_FILE"
\pagebreak
\vspace{10cm}
\begin{center}
\textnormal{---------------------------------------------}
\end{center}
\begin{center}
\textit{Copyright © $PUBLICATION_YEAR $AUTHOR. All rights reserved.}
\end{center}
\begin{center}
\textit{Published by $PUBLISHER}
\end{center}
EOF
            fi
        fi
    done
}

insert_extra_sections

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
# Use find instead of ls with globbing which is safer
PLAGIARISM_REPORTS=()
while IFS= read -r -d '' file; do
    PLAGIARISM_REPORTS+=("$file")
done < <(find "${BOOK_DIR}" -name "chapter_*_plagiarism_report.md" -print0 2>/dev/null || true)
# Similarly use find for backup files
BACKUP_FILES=()
while IFS= read -r -d '' file; do
    BACKUP_FILES+=("$file")
done < <(find "${BOOK_DIR}" -name "chapter_*.md.backup_*" -print0 2>/dev/null || true)

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

# If a generated bibliography exists (from generate_references.sh), append it here
BIB_FILE="$BOOK_DIR/final_bibliography.md"
if [ -f "$BIB_FILE" ]; then
    # Copy the original bibliography into the exports directory for convenience
    cp -f "$BIB_FILE" "$EXPORTS_DIR/" 2>/dev/null || true
else
    echo "ℹ️ No generated bibliography found at $BIB_FILE"
fi

cat << EOF >> "$MANUSCRIPT_FILE"
\pagebreak
\begin{center}
\section{References}
\end{center}

::: {.pagebreak}
:::
::: {.newpage}
:::

# References

EOF


cat "$BIB_FILE" >> "$MANUSCRIPT_FILE"

cat << EOF >> "$MANUSCRIPT_FILE"
\begin{center}
\textit{Copyright © $PUBLICATION_YEAR $AUTHOR. All rights reserved.}
\end{center}
\begin{center}
\textit{Published by $PUBLISHER}
\end{center}
EOF

cat << EOF >> "$MANUSCRIPT_FILE"
::: {.pagebreak}
:::
::: {.newpage}
:::

\pagebreak
\newpage

## About the Author
EOF

# Insert image using raw LaTeX if it exists
if [ -f "$AUTHOR_PHOTO_BASENAME" ]; then
  cat << EOF >> "$MANUSCRIPT_FILE"

$(if [ -f "$EXPORTS_DIR/$AUTHOR_PHOTO_BASENAME" ]; then echo "![]($AUTHOR_PHOTO_BASENAME){ width=50% } "; fi)


EOF
fi
# \includegraphics[width=0.5\\textwidth]{$AUTHOR_PHOTO_BASENAME}
# Elara Morgan is a passionate non-fiction author who explores the intricacies of human experience and the world around us. With a gift for making complex topics accessible, she bridges the gap between academic research and everyday life, empowering readers with knowledge that is both insightful and practical. Drawing on her background in education and the humanities, she distills ideas into engaging narratives that resonate widely. Her books are praised for their clarity, warmth, and thoughtful challenges to conventional wisdom. Beyond writing, Elara finds inspiration in nature—hiking New Hampshire's trails, tending her garden, and cherishing family time in Portsmouth. These pursuits ground her while fueling her creativity, making her life and work a testament to curiosity and the joy of discovery.

cat << EOF >> "$MANUSCRIPT_FILE"
\vspace{1cm}

Liam West is a digital strategist, entrepreneur, and creator who has helped countless individuals and brands harness the power of micro-influence to grow their presence and monetize their passions. With years of experience navigating the ever-evolving landscape of social media and online business, Liam specializes in breaking down complex strategies into simple, actionable steps that anyone can follow.

Through his work, Liam has guided aspiring creators, small business owners, and niche influencers to build authentic brands, cultivate engaged communities, and create sustainable income streams online. His mission is to empower everyday people to realize that influence isn't about millions of followers—it's about making a meaningful impact within your niche.

When he's not writing, speaking, or coaching, Liam enjoys exploring new cities, sipping fine coffee, and finding inspiration in the stories of creators worldwide.

\vspace{2cm}

::: {.pagebreak}
:::

\pagebreak

\clearpage\vspace*{\fill}

::: {.fillspace}
:::
::: {.copyright}

\centering
$(if [ -f "$EXPORTS_DIR/$LOGO_BASENAME" ]; then echo "![]($LOGO_BASENAME){ width=25% } "; fi)
\raggedright
\flushleft

\centering
$(if [ -n "$ISBN" ]; then echo "ISBN: $ISBN"; fi)

**Copyright Notice**

All intellectual property rights, including copyrights, in this book are owned by $PUBLISHER and/or the author. This work is protected under national and international copyright laws. Any unauthorized reproduction, distribution, or public display of this material is strictly prohibited. For permission requests, please contact the $PUBLISHER.

**Copyright © $PUBLICATION_YEAR $AUTHOR**

**$PUBLISHER**
\raggedright
\flushleft
:::

::: {.pagebreak}
:::

![](back-cover-1.png)

![](back-cover.png)
EOF

# If a back cover was generated, include it as the final page
# if [ -n "$BACK_COVER" ] && [ -f "$BACK_COVER" ]; then
#     echo "" >> "$MANUSCRIPT_FILE"
#     echo "" >> "$MANUSCRIPT_FILE"
#     echo "![]($(basename "$BACK_COVER"))" >> "$MANUSCRIPT_FILE"
#     echo "\thispagestyle{empty}" >> "$MANUSCRIPT_FILE"
#     # Copy back cover to exports directory only if different
#     if [ "$BACK_COVER" != "$EXPORTS_DIR/$(basename "$BACK_COVER")" ]; then
#         cp "$BACK_COVER" "$EXPORTS_DIR/"
#     fi
# fi

celebration "Manuscript Complete!"

echo "✅ Manuscript created: $(basename "$MANUSCRIPT_FILE")"
echo "📊 Total words: $TOTAL_WORDS"
echo "📄 Estimated pages: $((TOTAL_WORDS / 250))"

# Optionally generate references if GEMINI API key is available
# if [ -n "${GEMINI_API_KEY:-}" ]; then
#     echo "🔗 Generating references via generate_references.sh (Gemini)..."
#     # Run in background so main compile doesn't block too long; user can disable by unsetting GEMINI_API_KEY
#     "$SCRIPT_DIR/generate_references.sh" "$BOOK_DIR" 2>/dev/null &
# else
#     echo "ℹ️ To auto-generate references after compile, set GEMINI_API_KEY and re-run; or run generate_references.sh manually."
# fi

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
h1, h2, h3 {
  text-align: center;
  margin-left: auto;
  margin-right: auto;
}
h1 {
  font-size: 24pt;
  margin-top: 15px;
  margin-bottom: 10px;
  font-weight: bold;
}
h1.chapter-title {
  text-align: center;
  font-size: 24pt;
  margin-top: 30px;
  margin-bottom: 15px;
  font-weight: bold;
}
.toc-header {
  text-align: center;
  font-size: 24pt;
  margin-top: 60px;
  margin-bottom: 40px;
}
h2 { 
  margin-top: 10px;
  margin-bottom: 10px;
  font-size: 18pt;
  text-align: center;
}
h3 { 
  margin-top: 10px;
  margin-bottom: 10px;
  font-size: 16pt;
  text-align: center;
}
h4 {
  margin-top: 10px;
  margin-bottom: 10px;
  font-size: 14pt;
  text-align: center;
}
.chapter-main-title, .chapter-subtitle {
  text-align: center;
  display: block;
}
.title { font-size: 28pt; text-align: center; }
.author { font-size: 16pt; text-align: center; }
.date { font-size: 14pt; text-align: center; }
.publisher { font-size: 14pt; text-align: center; }
.rights { font-size: 14pt; text-align: center; }
.logo { text-align: center; margin: 3em auto; }
p {
  margin-bottom: 15px;
  orphans: 3;
  widows: 3;
}
.chapter {
  height: 50px;
}
.titlepage {
  text-align: center;
  margin-top: 20%;
}
.titlepage h1 {
  font-size: 2.5em;
  font-weight: bold;
  margin-bottom: 1em;
  text-align: center;
}
.titlepage h2 {
  font-size: 1.8em;
  font-weight: bold;
  margin-bottom: 1em;
  text-align: center;
}
.titlepage p {
  font-size: 1.2em;
  margin: 0.5em 0;
  text-align: center;
}
.copyright {
  text-align: center;
  margin: 10% auto;
  font-size: 0.9em;
  line-height: 1.5;
}
#TOC ol ol {
  list-style-type: none;
}
.pagebreak {
  page-break-before: always; /* older readers */
  break-before: page;        /* EPUB3 standard */
}
.fillspace {
  height: 20vh; /* 20% of viewport height */
}
.copyright {
  text-align: center;
  font-family: serif;         /* matches LaTeX serif fonts */
  font-size: 0.9em;
  line-height: 1.5;
  margin-top: 2em;
}
.copyright strong {
  font-weight: bold;
}
span.copyright-notice {
  display: block;
  font-weight: bold;
  font-size: 1.2em;
  margin: 1em 0;
  text-align: center;
}
.centered {
  text-align: center;
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
            
            # Build pandoc input list and options so EPUB matches PDF manuscript
            input_basename="$(basename "$input_file")"
            css_basename="$(basename "$css")"
            metadata_basename="$(basename "$metadata")"
            cover_basename=""
            [ -n "$cover" ] && cover_basename="$(basename "$cover")"

                        # # Prepare a temporary back-cover markdown file if a back cover image exists in the output dir
                        # back_md=""
                        # if [ -n "$BACK_COVER_IMAGE" ] && [ -f "$output_dir/$(basename "$BACK_COVER_IMAGE")" ]; then
                        #         back_basename="$(basename "$BACK_COVER_IMAGE")"
                        #         back_md="$output_dir/_backcover_insert.md"
                        #         if [ ! -f "$back_md" ]; then
                        #                 printf "\n\n![](%s)\n" "$back_basename" > "$back_md"
                        #         fi
                        # fi


            # Run pandoc from the output directory so image paths resolve correctly. Use --toc and set chapter level
            (cd "$output_dir" && {
                if [ -n "$cover_basename" ]; then
                    if [ -n "$back_md" ]; then
                        pandoc -f markdown -t epub3 \
                            --epub-cover-image="$COVER1_BASENAME" \
                            --css="$css_basename" \
                            --metadata-file="$metadata_basename" \
                            --toc --toc-depth=2 --resource-path=. \
                            --epub-chapter-level=1 --epub-title-page=true \
                            --split-level=1 -o "$(basename "$output_file")" "$input_basename" "$(basename "$back_md")"
                    else
                        pandoc -f markdown -t epub3 \
                            --epub-cover-image="$COVER1_BASENAME" \
                            --css="$css_basename" \
                            --metadata-file="$metadata_basename" \
                            --toc --toc-depth=2 --resource-path=. \
                            --epub-chapter-level=1 --epub-title-page=true \
                            --split-level=1 -o "$(basename "$output_file")" "$input_basename"
                    fi
                else
                    if [ -n "$back_md" ]; then
                        pandoc -f markdown -t epub3 \
                            --css="$css_basename" \
                            --metadata-file="$metadata_basename" \
                            --toc --toc-depth=2 --resource-path=. \
                            --epub-chapter-level=1 --epub-title-page=true \
                            --split-level=1 -o "$(basename "$output_file")" "$input_basename" "$(basename "$back_md")"
                    else
                        pandoc -f markdown -t epub3 \
                            --css="$css_basename" \
                            --metadata-file="$metadata_basename" \
                            --toc --toc-depth=2 --resource-path=. \
                            --epub-chapter-level=1 --epub-title-page=true \
                            --split-level=1 -o "$(basename "$output_file")" "$input_basename"
                    fi
                fi
            })
            
            echo "✅ EPUB created: $(basename "$output_file")"
            return 0
            ;;
            
        pdf)
            output_file="${output_dir}/$(basename "$input_file" .md).pdf"
            echo "📄 Generating PDF format..."
            cover="$COVER_IMAGE"
            echo "$COVER_IMAGE"
#             cat << 'EOF' > "$EXPORTS_DIR/cover.tex"
# \def\cover{$cover}
# \usepackage{graphicx}
# \usepackage{geometry}

# \AtBeginDocument{%
#   \thispagestyle{empty}
#   \newgeometry{margin=0mm}
#   \includegraphics[width=\paperwidth,height=\paperheight,keepaspectratio=false]{cover.png}
#   \thispagestyle{empty}
#   \includegraphics[width=\paperwidth,height=\paperheight,keepaspectratio=false]{cover-1.png}
#   \restoregeometry
#   \newpage
# }

# \AtEndDocument{%
#   \newpage
#   \thispagestyle{empty}
#   \newgeometry{margin=0mm}
#   \includegraphics[width=\paperwidth,height=\paperheight,keepaspectratio=false]{back-cover-1.png}
#   \thispagestyle{empty}
#   \includegraphics[width=\paperwidth,height=\paperheight,keepaspectratio=false]{back-cover.png}
#   \restoregeometry
# }
# EOF

            # Prepare latex helpers and optionally include back cover if present and is .jpg or .png
            if [ -n "$BACK_COVER_IMAGE" ] && [ -f "$BACK_COVER_IMAGE" ] && [[ "$BACK_COVER_IMAGE" == *.jpg || "$BACK_COVER_IMAGE" == *.png ]]; then
                backcover="$(basename "$BACK_COVER_IMAGE")"

                # Guard against extremely large images which can stall lualatex
                if command -v identify >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
                    dims=$(identify -format "%w %h" "$BACK_COVER_IMAGE" 2>/dev/null || true)
                    width=$(echo "$dims" | awk '{print $1}')
                    height=$(echo "$dims" | awk '{print $2}')
                    # Resize to proportional with max width/height
                    maxdim=3000
                    if [ -n "$width" ] && [ -n "$height" ] && ( [ "$width" -gt $maxdim ] || [ "$height" -gt $maxdim ] ); then
                        echo "⚠️ Back cover image large (${width}x${height}), resizing to avoid lualatex stalls"
                        # Calculate proportional dimensions
                        if [ "$width" -gt "$height" ]; then
                            newwidth=$maxdim
                            newheight=$((height * maxdim / width))
                        else
                            newheight=$maxdim
                            newwidth=$((width * maxdim / height))
                        fi
                        echo "⚠️ Resizing back cover image to ${newwidth}x${newheight}"
                        convert "$BACK_COVER_IMAGE" -resize ${newwidth}x${newheight}\> "$BACK_COVER_IMAGE" 2>/dev/null || true
                    fi
                fi
            fi

#             cat << EOF > "$EXPORTS_DIR/back-cover.tex"
# \usepackage{pdfpages}

# \AtEndDocument{%
#   \includepdf[pages=-,scale=1]{back-cover.pdf}
# }
# EOF

            cat << 'EOF' > "$EXPORTS_DIR/titles.tex"
\renewcommand{\maketitle}{}
\usepackage{titlesec}
\usepackage{tocloft}

\cftpagenumbersoff{section}
\cftpagenumberson{subsection}

\titleformat{\section}{\fontsize{28}{32}\selectfont\bfseries}{\thesection}{1em}{}
\titleformat{\subsection}{\fontsize{20}{24}\selectfont\bfseries}{\thesubsection}{1em}{}
\titleformat{\subsubsection}{\fontsize{14}{18}\selectfont\bfseries}{\thesubsubsection}{1em}{}
EOF

            # -H cover.tex \
            # -H back-cover.tex \
            # Try direct PDF generation first (run lualatex non-interactively to avoid hangs)
            (cd "$output_dir" && pandoc -f markdown -t pdf \
                --pdf-engine=lualatex \
                --pdf-engine-opt='-interaction=nonstopmode' \
                --pdf-engine-opt='-halt-on-error' \
                --metadata-file="$(basename "$metadata")" \
                -H titles.tex \
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
                
                echo "📚 Converting to MOBI format (for Kindle)..."
                
                # Build conversion command based on available cover
                local convert_cmd="ebook-convert \"$epub_file\" \"$output_file\" \
                    --title=\"$title\" \
                    --authors=\"$AUTHOR\" \
                    --publisher=\"$PUBLISHER\" \
                    --language=\"en\""
                
                # Only add cover parameter if the file actually exists
                if [ -n "$cover" ] && [ -f "$cover" ]; then
                    convert_cmd="$convert_cmd --cover=\"$cover\""
                    echo "   🖼️ Using cover: $(basename "$cover")"
                else
                    echo "   ⚠️ No cover image found, creating without cover"
                fi
                
                # Add ISBN if available
                if [ -n "$ISBN" ]; then
                    convert_cmd="$convert_cmd --isbn=\"$ISBN\""
                fi
                
                # Execute the conversion
                eval "$convert_cmd"
                
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
                
                # Build conversion command based on available cover
                local convert_cmd="ebook-convert \"$epub_file\" \"$output_file\" \
                    --title=\"$title\" \
                    --authors=\"$AUTHOR\" \
                    --publisher=\"$PUBLISHER\" \
                    --language=\"en\""
                
                # Only add cover parameter if the file actually exists
                if [ -n "$cover" ] && [ -f "$cover" ]; then
                    convert_cmd="$convert_cmd --cover=\"$cover\""
                    echo "   🖼️ Using cover: $(basename "$cover")"
                else
                    echo "   ⚠️ No cover image found, creating without cover"
                fi
                
                # Add ISBN if available
                if [ -n "$ISBN" ]; then
                    convert_cmd="$convert_cmd --isbn=\"$ISBN\""
                fi
                
                # Execute the conversion
                eval "$convert_cmd"
                
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
    if [ "$GENERATE_COVER" = true ]; then
        # Generate both front and back covers and set COVER_IMAGE/BACK_COVER
        generate_book_cover "$BOOK_TITLE" "$EXPORTS_DIR" || true
    else
        # Only set COVER_IMAGE if the file actually exists
        if [ -f "$EXPORTS_DIR/generated_cover_front.jpg" ]; then
            COVER_IMAGE="$EXPORTS_DIR/generated_cover_front.jpg"
        else
            echo "⚠️ No cover image provided and auto-generation not enabled"
            # Leave COVER_IMAGE empty to signal no cover available
            COVER_IMAGE=""
        fi
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