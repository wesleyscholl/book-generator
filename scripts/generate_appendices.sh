#!/usr/bin/env bash
# Generate appendices and extras for a book using Gemini (shell-only)
# Usage: generate_appendices.sh /path/to/book
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
BOOK_DIR="${1:-.}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-1.5-pro}"
GEMINI_KEY="${GEMINI_API_KEY:-}" # must be exported by caller/user
COOLDOWN_BASE=${COOLDOWN_BASE:-60}   # base seconds
COOLDOWN_JITTER=${COOLDOWN_JITTER:-10} # random jitter max
MAX_RETRIES=${MAX_RETRIES:-2}

MAX_TOKENS=65000
TEMP_DIR="$BOOK_DIR/temp_appendices"
BOOK_TITLE=""

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
[ -n "$GEMINI_KEY" ] || { echo "GEMINI_API_KEY environment variable must be set" >&2; exit 1; }

mkdir -p "$TEMP_DIR"

log() { printf '%s %s\n' "[appendices]" "$*"; }

# Colors
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
RESET="\033[0m"

# Animation function for waiting periods
show_wait_animation() {
    local wait_time=$1
    local message=$2
    local animation_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local start_time=$(date +%s)
    local end_time=$((start_time + wait_time))
    local current_time=$start_time
    
    # Hide cursor
    echo -en "\033[?25l"
    
    while [ $current_time -lt $end_time ]; do
        local remaining=$((end_time - current_time))
        local char="${animation_chars[$i]}"
        echo -ne "\r${CYAN}${char}${RESET} ${message} (${YELLOW}${remaining}s${RESET} remaining)     "
        i=$(((i + 1) % ${#animation_chars[@]}))
        sleep 0.1
        current_time=$(date +%s)
    done
    
    # Show cursor and clear line
    echo -e "\r\033[K${GREEN}✓${RESET} ${message} completed!     "
    echo -en "\033[?25h"
}

# Source the multi-provider helper (smart_api_call). This script requires it.
if [ -f "$SCRIPT_DIR/multi_provider_ai_simple.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/multi_provider_ai_simple.sh"
else
  log "ERROR: multi_provider_ai_simple.sh not found; this script requires smart_api_call. Please place multi_provider_ai_simple.sh alongside this script."
  exit 1
fi

random_sleep() {
  local jitter=$((RANDOM % COOLDOWN_JITTER))
  local delay=$((COOLDOWN_BASE + jitter))
  log "Cooling down for ${delay}s (base=${COOLDOWN_BASE}s jitter=${jitter}s)"
  # API rate limit delay
  show_wait_animation "$delay" "API cooldown"
}

extract_json_block() {
  local raw=$1
  local dst=$2
  if grep -q '```json' "$raw" 2>/dev/null; then
    sed -n '/```json/,/```/p' "$raw" | sed '1d;$d' > "$dst" && return 0
  fi
  # naive first { ... } block
  awk 'BEGIN{p=0} /\{/ {if(!p){p=1; print; next}} p{print} /\}/{if(p){exit}}' "$raw" > "$dst" && return 0
  cp "$raw" "$dst"
}

# Function to extract book metadata from chapters and outline
extract_book_metadata() {
    local book_dir="$1"
    local temp_dir="${TEMP_DIR:-$book_dir/temp_appendices}"
    local temp_file="$temp_dir/metadata.json"
    
    log "Extracting book metadata from chapters and outline..." >&2
    
    # Ensure temp directory exists
    if [ ! -d "$temp_dir" ]; then
        mkdir -p "$temp_dir" || {
            log "ERROR: Failed to create temp directory $temp_dir" >&2
            return 1
        }
    fi
    
    # Find outline file
    local outline_file=""
    for f in "$book_dir"/book_outline*.md "$book_dir"/outline*.md; do
        if [ -f "$f" ]; then
            outline_file="$f"
            break
        fi
    done
    
    if [ -z "$outline_file" ]; then
        log "No outline file found, searching in all .md files..." >&2
        for f in "$book_dir"/*.md; do
            if [ -f "$f" ] && grep -q -i "^# " "$f"; then
                outline_file="$f"
                break
            fi
        done
    fi
    
    if [ -z "$outline_file" ]; then
        log "ERROR: Could not find outline or any markdown file with title in $book_dir" >&2
        log "Available files in $book_dir:" >&2
        ls -la "$book_dir"/*.md 2>/dev/null | head -5 | while read line; do log "  $line" >&2; done || log "  No .md files found" >&2
        return 1
    fi
    
    log "Using outline file: $outline_file" >&2
    
    # Extract title and other metadata
    local title=$(grep -m 1 -i "^# " "$outline_file" | sed 's/^# //')
    local subtitle=$(grep -m 1 -i "^## " "$outline_file" | sed 's/^## //')
    
    # Find a chapter to extract tone and style
    local sample_chapter=""
    for f in "$book_dir"/chapter_*.md; do
        if [ -f "$f" ]; then
            sample_chapter="$f"
            break
        fi
    done
    
    # Create metadata JSON
    cat > "$temp_file" << EOF
{
    "title": "${title:-Untitled Book}",
    "subtitle": "${subtitle:-}",
    "outline_file": "$(basename "$outline_file")",
    "sample_chapter": "$(basename "${sample_chapter:-}")"
}
EOF
    
    # Verify the file was created successfully
    if [ ! -f "$temp_file" ]; then
        log "ERROR: Failed to create metadata file $temp_file" >&2
        return 1
    fi
    
    log "Successfully created metadata file with title '${title:-Untitled Book}'" >&2
    echo "$temp_file"
}

# Function to generate a specific extra section
generate_section() {
    local section_type="$1"
    local metadata_file="$2"
    local output_file="$3"
    
    log "Generating $section_type..."
    
    # Create temp files for raw output and parsed JSON
    local raw_out="$TEMP_DIR/raw_${section_type}_$(date +%s).txt"
    
    # Check if metadata file exists
    if [ ! -f "$metadata_file" ]; then
        log "ERROR: Metadata file not found: $metadata_file"
        return 1
    fi
    
    # Get metadata content
    local metadata_content=$(cat "$metadata_file")
    local title=$(echo "$metadata_content" | jq -r '.title')
    local subtitle=$(echo "$metadata_content" | jq -r '.subtitle')
    local outline_file="$BOOK_DIR/$(echo "$metadata_content" | jq -r '.outline_file')"
    local sample_chapter="$BOOK_DIR/$(echo "$metadata_content" | jq -r '.sample_chapter')"
    
    # Generate prompt based on section type
    local prompt=""
    case "$section_type" in
        preface)
            prompt="You are a professional book writer. Create a preface for the book titled \"$title\"${subtitle:+: $subtitle}.

The preface should:
1. Explain the purpose, scope, and goals of the book
2. Discuss what inspired you to write this book
3. Acknowledge any challenges or unique approaches taken in creating the work
4. Mention the intended audience and how they will benefit from reading
5. Be around 600-800 words in length
6. Be written in the first person from the author's perspective
7. Set the appropriate tone for the rest of the book
8. Use the provided book title within the Preface

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to match the writing style:
$(head -n 100 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Create a complete, well-structured preface in markdown format. Start with '# Preface' as the heading. Do not include any explanations or notes outside of the preface content itself."
            ;;
        introduction)
            prompt="You are a professional book writer. Create an introduction for the book titled \"$title\"${subtitle:+: $subtitle}.

The introduction should:
1. Present the main subject and theme of the book
2. Provide necessary background information or context
3. Establish the key questions, problems, or issues the book will address
4. Outline the structure of the book and what each chapter covers
5. Explain the methodology or approach used
6. Hook the reader's interest and make them want to continue reading
7. Be around 1000-1500 words in length

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to match the writing style:
$(head -n 100 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Create a complete, well-structured introduction in markdown format. Start with '# Introduction' as the heading. Do not include any explanations or notes outside of the introduction content itself."
            ;;
        dedication)
            prompt="You are a professional book writer. Create a dedication page for the book titled \"$title\"${subtitle:+: $subtitle}.

The dedication should:
1. Be brief and heartfelt (typically 1-3 sentences)
2. Be dedicated to someone meaningful (family, mentor, supporters, etc.)
3. Avoid being overly sentimental while still conveying genuine emotion
4. Be formatted simply and elegantly
5. Follow standard book dedication conventions

Create a complete dedication in markdown format. Start with '# Dedication' as the heading. Do not include any explanations or notes outside of the dedication content itself."
            ;;
        acknowledgments)
            prompt="You are a professional book writer. Create an acknowledgments page for the book titled \"$title\"${subtitle:+: $subtitle}.

The acknowledgments should:
1. Thank individuals who contributed to the book's development (research assistants, editors, early readers, etc.)
2. Recognize any organizations or institutions that provided support
3. Express gratitude to family members and close friends who provided emotional support
4. Mention any grants, fellowships, or financial assistance received
5. Be gracious and sincere without being excessively long
6. Be organized in a logical manner (often from professional to personal connections)

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Create complete acknowledgments in markdown format. Start with '# Acknowledgments' as the heading. Do not include any explanations or notes outside of the acknowledgments content itself."
            ;;
        prologue)
            prompt="You are a professional book writer. Create a prologue for the book titled \"$title\"${subtitle:+: $subtitle}.

The prologue should:
1. Set the scene or establish important background information for the main content
2. Introduce key themes, conflicts, or questions that will be explored
3. Create intrigue or tension to draw the reader into the book
4. Be written in a narrative style that complements the main text
5. Be around 800-1000 words in length
6. Stand somewhat apart from but connect meaningfully to the main content

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to match the writing style:
$(head -n 100 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Create a complete, well-structured prologue in markdown format. Start with '# Prologue' as the heading. Do not include any explanations or notes outside of the prologue content itself."
            ;;
        endnotes)
            prompt="You are a professional book writer. Create endnotes for the book titled \"$title\"${subtitle:+: $subtitle}.

The endnotes should:
1. Provide additional information, clarifications, or citations for key points made in the main text
2. Be organized by chapter, with clear references to specific passages
3. Follow a consistent format and citation style
4. Include a mix of citations, explanatory notes, and references to other works
5. Be academically sound while remaining accessible to general readers

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to understand what requires notation:
$(head -n 200 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Create complete, well-structured endnotes in markdown format. Start with '# Endnotes' as the heading. Organize by chapter and use a consistent format. Do not include any explanations outside of the endnotes content itself."
            ;;
        further_reading)
            prompt="You are a professional book writer. Create a 'Further Reading' section for the book titled \"$title\"${subtitle:+: $subtitle}.

The Further Reading section should:
1. Recommend 15-25 high-quality books, articles, papers, or other resources related to the book's topics
2. Organize recommendations by theme, chapter, or subject area
3. Include a brief description (1-2 sentences) of each recommended work
4. Cover both foundational/classic works and recent publications where appropriate
5. Include a mix of academic and accessible resources when possible
6. Be formatted clearly and consistently

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Create a complete, well-structured Further Reading section in markdown format. Start with '# Further Reading' as the heading. Do not include any explanations outside of the Further Reading content itself."
            ;;
        reader_thanks)
            prompt="You are a professional book writer. Create a 'Thank You to Readers' section for the book titled \"$title\"${subtitle:+: $subtitle}.

The Thank You section should:
1. Express sincere gratitude to readers for choosing and reading the book
2. Acknowledge the value of their time and attention
3. Briefly reflect on what you hope readers have gained from the book
4. Politely request that readers consider leaving an Amazon review if they found the book valuable
5. Mention how reviews help other readers discover the book and support the author's work
6. Invite readers to connect through social media, a website, or newsletter if applicable
7. Be warm, genuine, and not overly promotional in tone
8. Be around 300-400 words in length

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Create a complete, well-structured Thank You section in markdown format. Start with '# A Note to Readers' as the heading. Do not include any explanations outside of the Thank You content itself."
            ;;
        epilogue)
            prompt="You are a professional book writer. Create an epilogue for the book titled \"$title\"${subtitle:+: $subtitle}.

The epilogue should:
1. Provide closure to the main themes and ideas presented throughout the book
2. Summarize key takeaways or lessons learned
3. Offer final thoughts, reflections, or a call to action for the reader
4. Be around 800-1000 words in length
5. Maintain the same tone and style as the rest of the book
6. Include a brief look toward the future or next steps

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to match the writing style:
$(head -n 100 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Create a complete, well-structured epilogue in markdown format. Start with '# Epilogue' as the heading. Do not include any explanations or notes outside of the epilogue content itself."
            ;;
        glossary)
            prompt="You are a professional book writer. Create a comprehensive glossary for the book titled \"$title\"${subtitle:+: $subtitle}.

The glossary should:
1. Include 30-50 key terms and concepts discussed in the book
2. Provide clear, concise definitions for each term
3. Be alphabetically organized
4. Include terms that might be unfamiliar to the target audience or that have specific meanings in the context of the book
5. Be formatted in markdown with '# Glossary' as the main heading

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to identify relevant terms:
$(head -n 200 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Generate a complete, well-formatted glossary in markdown format. Include only the glossary content, starting with the heading '# Glossary'."
            ;;
        discussion)
            prompt="You are a professional book writer. Create a discussion guide for the book titled \"$title\"${subtitle:+: $subtitle}.

The discussion guide should:
1. Include 15-20 thought-provoking questions for readers or book clubs
2. Organize questions by chapter or by theme
3. Include a mix of analytical, reflective, and application-based questions
4. Encourage critical thinking and personal connections to the material
5. Be formatted in markdown with '# Discussion Guide' as the main heading

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to understand the content style:
$(head -n 200 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Generate a complete, well-structured discussion guide in markdown format. Include only the discussion guide content itself, starting with the heading '# Discussion Guide'."
            ;;
        appendices)
            prompt="You are a professional book writer. Create useful appendices for the book titled \"$title\"${subtitle:+: $subtitle}.

The appendices should:
1. Include 3-5 different appendices that supplement the main content of the book
2. Each appendix should have its own heading (e.g., 'Appendix A: Resources for Further Reading')
3. Include relevant resources, tools, templates, additional information, or exercises that readers would find valuable
4. Be formatted in markdown with '# Appendices' as the main heading
5. Be well-organized and easy to navigate

Potential appendix ideas (choose most appropriate for this book):
- Resources for further reading/learning
- Templates or worksheets
- Summary of key concepts
- Timeline of important events
- Step-by-step guides
- Checklists
- Case studies
- Detailed statistical data
- Glossary of technical terms

Here is the book outline for context:
$(cat "$outline_file" 2>/dev/null || echo "Outline not found")

Here is a sample chapter to understand the content:
$(head -n 200 "$sample_chapter" 2>/dev/null || echo "Sample chapter not found")

Generate complete, well-structured appendices in markdown format. Include only the appendices content itself, starting with the heading '# Appendices'."
            ;;
        *)
            log "ERROR: Unknown section type: $section_type"
            return 1
            ;;
    esac
    
    # Call smart_api_call to generate content
    log "Calling smart_api_call for $section_type generation..."
    if ! smart_api_call "$prompt" "" "general" 0.7 $MAX_TOKENS $MAX_RETRIES "" > "$raw_out" 2>/dev/null; then
        log "smart_api_call failed for $section_type; saving raw output"
        cp "$raw_out" "$TEMP_DIR/${section_type}_error_$(date +%s).txt" || true
        return 1
    fi
    
    # Process output and save to final file
    log "Processing output for $section_type..."
    
    # Extract markdown content from the API response
    cat "$raw_out" > "$output_file"
    
    log "Generated $section_type saved to: $output_file"
    
    return 0
}

# Main execution

log "Starting generation of appendices and extras for book in: $BOOK_DIR"

# Extract book metadata
log "Attempting to extract book metadata from $BOOK_DIR..."
metadata_file=$(extract_book_metadata "$BOOK_DIR")
metadata_status=$?

# Validate that extraction succeeded and the file exists
if [ $metadata_status -ne 0 ] || [ -z "${metadata_file:-}" ] || [ ! -f "$metadata_file" ]; then
    log "Failed to extract book metadata (status=$metadata_status, metadata_file='${metadata_file:-}')"
    
    # Try creating a default metadata file as fallback
    log "Creating a default metadata file as fallback..."
    default_metadata_file="$TEMP_DIR/default_metadata.json"
    mkdir -p "$TEMP_DIR"
    
    cat > "$default_metadata_file" << EOF
{
    "title": "Untitled Book",
    "subtitle": "",
    "outline_file": "none",
    "sample_chapter": ""
}
EOF
    
    if [ -f "$default_metadata_file" ]; then
        log "Created default metadata file as fallback"
        metadata_file="$default_metadata_file"
    else
        log "ERROR: Failed to create even a default metadata file. Cannot continue."
        exit 1
    fi
fi

log "Using metadata file: $metadata_file"
# Display metadata content for debugging
if [ -r "$metadata_file" ]; then
    log "Metadata content:"
    cat "$metadata_file" | sed 's/^/  /'
else
    log "Warning: metadata file is not readable: $metadata_file"
fi

# Generate each section
sections=("preface" "introduction" "dedication" "acknowledgments" "prologue" "epilogue" "glossary" "discussion" "endnotes" "further_reading" "reader_thanks" "appendices")
for section in "${sections[@]}"; do
    # Set special filenames for certain sections
    case "$section" in
        further_reading)
            output_file="$BOOK_DIR/further-reading.md"
            ;;
        reader_thanks)
            output_file="$BOOK_DIR/thank-you-to-readers.md"
            ;;
        *)
            output_file="$BOOK_DIR/${section}.md"
            ;;
    esac
    
    # Check if file already exists
    if [ -f "$output_file" ]; then
        log "File already exists for $section: $output_file"
        read -p "Overwrite? (y/n): " -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            log "Skipping $section generation"
            continue
        fi
    fi
    
    # Generate the section
    generate_section "$section" "$metadata_file" "$output_file"
    
    # Cooldown between API calls
    if [ "$section" != "appendices" ]; then  # "appendices" is the last element in the sections array
        random_sleep
    fi
done

log "All appendices and extras generation complete!"
log "Generated files:"
for section in "${sections[@]}"; do
    # Get correct output filename
    case "$section" in
        further_reading)
            output_file="$BOOK_DIR/further-reading.md"
            ;;
        reader_thanks)
            output_file="$BOOK_DIR/thank-you-to-readers.md"
            ;;
        *)
            output_file="$BOOK_DIR/${section}.md"
            ;;
    esac
    
    if [ -f "$output_file" ]; then
        log "  - $(basename "$output_file")"
    fi
done

exit 0
