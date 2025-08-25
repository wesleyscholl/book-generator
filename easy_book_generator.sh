#!/bin/bash

# Easy Book Generator - One command to rule them all
# Usage: ./easy_book.sh

set -e

# Start timer for job duration tracking
START_TIME=$(date +%s)
echo "⏱️ Job started at $(date '+%Y-%m-%d %H:%M:%S')"

API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Function to escape JSON strings
escape_json() {
    # Use jq to properly escape JSON strings
    echo -n "$1" | jq -Rs '.'
}

# Function to make API requests
make_api_request() {
    local payload="$1"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$API_URL"
}

# CLI Animation Functions
show_spinner() {
    local pid=$1
    local delay=0.15
    local spinstr='|/-\'
    local message="${2:-Processing}"
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r\033[K🔄 $message %c" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K"
}

typewriter() {
    local text="$1"
    local delay="${2:-0.05}"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%c" "${text:$i:1}"
        sleep $delay
    done
    echo
}

loading_dots() {
    local duration=${1:-3}
    local message="${2:-Loading}"
    local count=0
    local max_dots=3
    
    while [ $count -lt $((duration * 10)) ]; do
        local dots=$((count % (max_dots + 1)))
        printf "\r\033[K⏳ $message"
        for ((i=0; i<dots; i++)); do
            printf "."
        done
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

pulse_text() {
    local text="$1"
    local cycles=${2:-3}
    
    for ((i=0; i<cycles; i++)); do
        printf "\r\033[1;37m$text\033[0m"
        sleep 0.5
        printf "\r\033[2;37m$text\033[0m"
        sleep 0.5
    done
    printf "\r\033[K$text\n"
}

countdown() {
    local seconds=$1
    local message="${2:-Starting in}"
    
    for ((i=seconds; i>0; i--)); do
        printf "\r\033[K⏰ $message $i..."
        sleep 1
    done
    printf "\r\033[K"
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

clear_with_fade() {
    local lines=$(tput lines 2>/dev/null || echo 24)
    
    for ((i=lines; i>0; i--)); do
        printf "\033[2K\033[1A"
        sleep 0.02
    done
    clear
}

show_interactive_menu() {
    clear_with_fade
    
    cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                   📚 AI Book Generator                   ║
╚══════════════════════════════════════════════════════════╝
EOF
    
    typewriter "Complete Workflow Automation" 0.03
    echo
    
    cat << 'EOF'
Choose your workflow:

1) 📘 Generate Complete Book (Outline + All Chapters)
2) 📋 Generate Outline Only  
3) ✍️  Generate Chapters from Existing Outline
4) 📖 Compile Existing Chapters into Manuscript
5) ✨ Review & Edit Existing Book
6) ⚙️  Configure Settings
7) ❓ Help & Examples
8) 🚪 Exit

EOF
    echo -n "Select option (1-8): "
}

configure_settings() {
    echo ""
    echo "⚙️ Current Settings:"
    echo "   API Key: ${GEMINI_API_KEY:+Set}${GEMINI_API_KEY:-Not Set}"
    echo "   Model: ${BOOK_MODEL:-gemini-1.5-flash-latest}"
    echo "   Temperature: ${BOOK_TEMPERATURE:-0.8}"
    echo "   Words per chapter: ${BOOK_MIN_WORDS:-1000}-${BOOK_MAX_WORDS:-2000}"
    echo "   Style: ${BOOK_STYLE:-detailed}"
    echo "   Tone: ${BOOK_TONE:-professional}"
    echo ""
    
    read -p "Update API key? (y/N): " update_key
    if [[ $update_key =~ ^[Yy]$ ]]; then
        read -p "Enter Gemini API key: " api_key
        export GEMINI_API_KEY="$api_key"
        echo "export GEMINI_API_KEY='$api_key'" >> ~/.bashrc
    fi
    
    read -p "Change model? Current: ${BOOK_MODEL:-gemini-1.5-flash-latest} (y/N): " update_model
    if [[ $update_model =~ ^[Yy]$ ]]; then
        echo "Available models:"
        echo "  1) gemini-1.5-flash-latest (faster, cheaper)"
        echo "  2) gemini-1.5-pro-latest (higher quality)"
        read -p "Choose (1-2): " model_choice
        case $model_choice in
            1) export BOOK_MODEL="gemini-1.5-flash-latest" ;;
            2) export BOOK_MODEL="gemini-1.5-pro-latest" ;;
        esac
    fi
    
    loading_dots 1 "Saving settings"
    echo "✅ Settings updated"
    read -p "Press Enter to continue..."
}

show_help() {
    clear_with_fade
    typewriter "📚 AI Book Generator Help" 0.03
    
    cat << 'EOF'

WHAT IT DOES:
This tool generates complete 30,000-word books using AI, formatted for KDP publishing.

WORKFLOW:
1. Creates detailed book outline (12-15 chapters)
2. Generates each chapter (2,000-3,000 words)
3. Reviews and edits content for quality
4. Compiles everything into publication-ready manuscript

REQUIREMENTS:
- Gemini API key (free from ai.google.dev)
- jq (sudo apt install jq)
- curl
- Optional: pandoc for HTML/PDF output

EXAMPLES:

Complete Book Generation:
  Topic: "Personal Finance for Millennials"  
  Genre: "Self-Help"
  Audience: "Young Adults 25-35"

Fiction Example:
  Topic: "A Dragon's Quest for Identity"
  Genre: "Fantasy Fiction" 
  Audience: "Young Adults"

Business Example:
  Topic: "Remote Team Leadership"
  Genre: "Business Management"
  Audience: "Managers and Team Leaders"

TIPS:
- Be specific with your topic (not just "fitness" but "Home Workouts for Busy Parents")
- Choose clear target audience (age, profession, interests)
- Review outline before generating chapters
- Each book takes 30-90 minutes to generate completely (including editing)
- Generated books are 25,000-35,000 words typically

FILE OUTPUTS:
- book_outline_[timestamp].md - The book structure
- chapter_1.md through chapter_N.md - Individual chapters  
- chapter_N_reviewed.md - AI-reviewed versions
- chapter_N_edited.md - AI-edited versions  
- manuscript_[timestamp].md - Complete book ready for publishing
- Optional: HTML and PDF versions

EOF
    read -p "Press Enter to continue..."
}

get_book_details() {
    echo ""
    typewriter "📝 Enter Book Details:" 0.03
    echo ""
    
    read -p "📖 Book Topic (be specific): " TOPIC
    if [ -z "$TOPIC" ]; then
        echo "❌ Topic cannot be empty"
        return 1
    fi
    
    echo ""
    echo "📚 Popular Genres:"
    echo "   Self-Help, Business, Fiction, Romance, Mystery, Fantasy"
    echo "   Health & Fitness, Personal Finance, Technology, History"
    read -p "📚 Genre: " GENRE
    if [ -z "$GENRE" ]; then
        echo "❌ Genre cannot be empty"  
        return 1
    fi
    
    echo ""
    echo "👥 Example Audiences:"
    echo "   Young Adults 18-25, Working Professionals, Parents"
    echo "   Small Business Owners, Students, Retirees"
    read -p "👥 Target Audience: " AUDIENCE
    if [ -z "$AUDIENCE" ]; then
        echo "❌ Audience cannot be empty"
        return 1
    fi
    
    echo ""
    echo "🎨 Writing Style:"
    echo "   1) Detailed       - Comprehensive explanations, thorough coverage"
    echo "   2) Narrative      - Story-driven, personal or fictional storytelling"
    echo "   3) Academic       - Formal, structured, and evidence-based"
    echo "   4) Analytical     - Breaks down complex ideas logically"
    echo "   5) Descriptive    - Rich imagery and sensory details"
    echo "   6) Persuasive     - Aims to convince or influence"
    echo "   7) Expository     - Explains facts and processes clearly"
    echo "   8) Technical      - Precision-focused, for technical audiences"
    read -p "Choose style (1-8) or press Enter for Detailed: " style_choice

    case $style_choice in
        2) STYLE="narrative" ;;
        3) STYLE="academic" ;;
        4) STYLE="analytical" ;;
        5) STYLE="descriptive" ;;
        6) STYLE="persuasive" ;;
        7) STYLE="expository" ;;
        8) STYLE="technical" ;;
        1|"") STYLE="detailed" ;;
        *) STYLE="detailed" ;;
    esac
    
    echo ""
    echo "🗣️ Choose a Writing Tone:"
    echo "   1) Professional     - Formal, clear, and businesslike"
    echo "   2) Conversational   - Friendly and relaxed, like talking to a friend"
    echo "   3) Authoritative    - Confident and credible, like an expert"
    echo "   4) Casual           - Informal and laid-back"
    echo "   5) Persuasive       - Influential and convincing"
    echo "   6) Humorous         - Light-hearted and witty"
    echo "   7) Inspirational    - Uplifting and motivational"
    echo "   8) Empathetic       - Compassionate and understanding"
    echo "   9) Bold             - Direct, edgy, and unapologetic"
    read -p "Choose tone (1-9) or press Enter for Professional: " tone_choice
    
    case $tone_choice in
        2) TONE="conversational" ;;
        3) TONE="authoritative" ;;
        4) TONE="casual" ;;
        5) TONE="persuasive" ;;
        6) TONE="humorous" ;;
        7) TONE="inspirational" ;;
        8) TONE="empathetic" ;;
        9) TONE="bold" ;;
        1|"") TONE="professional" ;;
        *) TONE="professional" ;;
    esac
    
    return 0
}

generate_complete_book() {
    if ! get_book_details; then
        return 1
    fi
    
    echo ""
    echo "🎯 Book Configuration:"
    echo "   📖 Topic: $TOPIC"
    echo "   📚 Genre: $GENRE"  
    echo "   👥 Audience: $AUDIENCE"
    echo "   🎨 Style: $STYLE"
    echo "   🗣️ Tone: $TONE"
    echo ""
    
    read -p "🚀 Generate this book? This will take 30-90 minutes. (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "❌ Generation cancelled"
        return 1
    fi
    
    echo ""
    pulse_text "🚀 Starting complete book generation..."
    echo "⏰ Started at: $(date)"

    # Check if full_book_generator.sh exists
    if [ ! -f "./full_book_generator.sh" ]; then
        echo "❌ Error: full_book_generator.sh not found"
        echo "Make sure all scripts are in the current directory"
        return 1
    fi
    
    # Run the full book generator with proper quoting
    ./full_book_generator.sh "$TOPIC" "$GENRE" "$AUDIENCE" \
        --style "$STYLE" \
        --tone "$TONE" \
        --delay 15
    
    if [ $? -eq 0 ]; then
        echo ""
        celebration "Book generation completed!"
        echo "⏰ Finished at: $(date)"
        echo ""
        
        # Ask about editing
        read -p "✨ Run AI review and editing? (Y/n): " run_editing
        if [[ ! $run_editing =~ ^[Nn]$ ]]; then
            LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
            if [ -n "$LATEST_DIR" ]; then
                review_and_edit_book "$LATEST_DIR"
            fi
        fi
        
        read -p "📖 Compile into final manuscript now? (Y/n): " compile_now
        if [[ ! $compile_now =~ ^[Nn]$ ]]; then
            LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
            if [ -n "$LATEST_DIR" ]; then
                ./compile_book.sh "$LATEST_DIR"
            fi
        fi
    else
        echo "❌ Book generation failed"
        return 1
    fi
}

# Function to generate complete book from suggestion (variables already set by suggest_topics)
generate_complete_book_from_suggestion() {
    echo ""
    echo "🎯 Book Configuration:"
    echo "   📖 Topic: $TOPIC"
    echo "   📚 Genre: $GENRE"  
    echo "   👥 Audience: $AUDIENCE"
    echo "   🎨 Style: $STYLE"
    echo "   🗣️ Tone: $TONE"
    echo ""
    
    read -p "🚀 Generate this book? This will take 30-90 minutes. (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "❌ Generation cancelled"
        return 1
    fi
    
    echo ""
    pulse_text "🚀 Starting complete book generation..."
    countdown 3 "Beginning in"
    echo "⏰ Started at: $(date)"

    # Check if full_book_generator.sh exists
    if [ ! -f "./full_book_generator.sh" ]; then
        echo "❌ Error: full_book_generator.sh not found"
        echo "Make sure all scripts are in the current directory"
        return 1
    fi
    
    # Run the full book generator with proper quoting
    ./full_book_generator.sh "$TOPIC" "$GENRE" "$AUDIENCE" \
        --style "$STYLE" \
        --tone "$TONE" \
        --delay 15
    
    if [ $? -eq 0 ]; then
        echo ""
        celebration "Book generation completed!"
        echo "⏰ Finished at: $(date)"
        echo ""
        
        # Ask about editing
        read -p "✨ Run AI review and editing? (Y/n): " run_editing
        if [[ ! $run_editing =~ ^[Nn]$ ]]; then
            LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
            if [ -n "$LATEST_DIR" ]; then
                review_and_edit_book "$LATEST_DIR"
            fi
        fi
        
        read -p "📖 Compile into final manuscript now? (Y/n): " compile_now
        if [[ ! $compile_now =~ ^[Nn]$ ]]; then
            LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
            if [ -n "$LATEST_DIR" ]; then
                ./compile_book.sh "$LATEST_DIR"
            fi
        fi
    else
        echo "❌ Book generation failed"
        return 1
    fi
}

generate_outline_only() {
    # Automatically generate 5 topics and skip manual input
    if ! suggest_topics; then
        return 1
    fi

    echo ""
    loading_dots 1 "Preparing outline generation"

    # Run with proper quoting
    ./full_book_generator.sh "$TOPIC" "$GENRE" "$AUDIENCE" \
        --style "$STYLE" \
        --tone "$TONE" \
        --outline-only

    if [ $? -eq 0 ]; then
        echo "✅ Outline generated successfully"
        echo "Use option 3 to generate chapters from this outline"
        
        # Show the created directory
        LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
        if [ -n "$LATEST_DIR" ]; then
            echo -e "📁 Book directory:\n   $(basename "$LATEST_DIR")"
        fi
    fi
}

# Function to generate outline from suggestion (variables already set by suggest_topics)
generate_outline_only_from_suggestion() {
    echo ""
    loading_dots 1 "Preparing outline generation"

    # Run with proper quoting
    ./full_book_generator.sh "$TOPIC" "$GENRE" "$AUDIENCE" \
        --style "$STYLE" \
        --tone "$TONE" \
        --outline-only
        
    if [ $? -eq 0 ]; then
        echo "✅ Outline generated successfully"
        echo "Use option 3 to generate chapters from this outline"
        
        # Show the created directory
        LATEST_DIR=$(ls -td ./book_outputs/*-* 2>/dev/null | head -1)
        if [ -n "$LATEST_DIR" ]; then
            echo -e "📁 Book directory:\n   $(basename "$LATEST_DIR")"
        fi
    fi
}

generate_chapters_from_outline() {
    echo ""
    echo "📁 Available book directories:"
    
    # Make sure the output directory exists
    if [ ! -d "./book_outputs" ]; then
        mkdir -p ./book_outputs
    fi
    
    # Create arrays to hold found files and directories
    declare -a OLD_OUTLINE_FILES
    declare -a BOOK_DIRS
    declare -a ALL_OUTLINES
    
    # Look for old format individual outline files (direct in book_outputs)
    if compgen -G "./book_outputs/book_outline_*.md" > /dev/null; then
        OLD_OUTLINE_FILES=(./book_outputs/book_outline_*.md)
    fi
    
    # Find all directories in book_outputs folder
    if [ -d "./book_outputs" ]; then
        for dir in ./book_outputs/*/; do
            if [ -d "$dir" ]; then
                BOOK_DIRS+=("$dir")
            fi
        done
    fi
    
    declare -a ALL_OUTLINES
    
    # Add old format outline files
    for outline in "${OLD_OUTLINE_FILES[@]}"; do
        if [ -f "$outline" ]; then
            ALL_OUTLINES+=("$outline")
        fi
    done
    
    # Process all book directories to find outlines
    for dir in "${BOOK_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            # Try to find any outline files (multiple patterns)
            outline_file=""
            
            # First try to find any outline file in the directory
            outline_file=$(find "$dir" -name "*outline*.md" 2>/dev/null | head -1)
            
            # If that doesn't work, try a more specific pattern
            if [ -z "$outline_file" ]; then
                outline_file=$(find "$dir" -name "book_outline*.md" 2>/dev/null | head -1)
            fi
            
            # If that fails, try a simpler approach
            if [ -z "$outline_file" ]; then
                outline_file=$(find "$dir" -name "*.md" | grep -i outline | head -1)
            fi
            
            # If still nothing, just find any markdown file
            if [ -z "$outline_file" ]; then
                outline_file=$(find "$dir" -name "*.md" | head -1)
            fi
            
            # If we found an outline file, add it to our list
            if [ -n "$outline_file" ] && [ -f "$outline_file" ]; then
                ALL_OUTLINES+=("$outline_file")
            fi
        fi
    done
    
    if [ ${#ALL_OUTLINES[@]} -eq 0 ]; then
        echo "❌ No book outlines found"
        echo ""
        echo "Generate an outline first using option 2"
        return 1
    fi
    
    # Display all found outlines/directories
    for i in "${!ALL_OUTLINES[@]}"; do
        OUTLINE_PATH="${ALL_OUTLINES[$i]}"
        
        # Make sure the outline path exists
        if [ ! -f "$OUTLINE_PATH" ]; then
            echo "   $((i+1))) Missing outline: $OUTLINE_PATH"
            continue
        fi
        
        # Get directory path if it's in a directory
        if [[ "$OUTLINE_PATH" == *"/"* ]]; then
            DIR_PATH=$(dirname "$OUTLINE_PATH")
            DIR_NAME=$(basename "$DIR_PATH")
            CHAPTER_COUNT=$(find "$DIR_PATH" -name "chapter_*.md" 2>/dev/null | wc -l)
            
            # Handle different directory naming conventions
            if [[ "$DIR_NAME" == *"-"*"_"*"_"* || "$DIR_NAME" == *"-"*"-"*"-"* ]]; then
                # This is likely a topic-based directory with timestamp
                # Extract topic name by removing timestamp portion
                TOPIC=$(echo "$DIR_NAME" | sed -E 's/-[0-9]{8}_[0-9]{6}$//' | sed 's/-/ /g')
                TOPIC=$(echo "$TOPIC" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')
                
                # Get timestamp for date display
                TIMESTAMP=$(echo "$DIR_NAME" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
                if [ -n "$TIMESTAMP" ]; then
                    YEAR="${TIMESTAMP:0:4}"
                    MONTH="${TIMESTAMP:4:2}"
                    DAY="${TIMESTAMP:6:2}"
                    HOUR="${TIMESTAMP:9:2}"
                    MINUTE="${TIMESTAMP:11:2}"
                    FORMATTED_DATE="${YEAR}-${MONTH}-${DAY} ${HOUR}:${MINUTE}"
                    
                    # Show chapter info and creation date
                    if [ "$CHAPTER_COUNT" -eq 0 ]; then
                        echo "   $((i+1))) 📑 $TOPIC (Outline only, Created: $FORMATTED_DATE)"
                    elif [ "$CHAPTER_COUNT" -eq 1 ]; then
                        echo "   $((i+1))) 📚 $TOPIC ($CHAPTER_COUNT chapter, Created: $FORMATTED_DATE)"
                    else
                        echo "   $((i+1))) 📚 $TOPIC ($CHAPTER_COUNT chapters, Created: $FORMATTED_DATE)" 
                    fi
                else
                    echo "   $((i+1))) 📚 $DIR_NAME ($CHAPTER_COUNT chapters)"
                fi
            else
                # Other directory format
                echo "   $((i+1))) $DIR_NAME ($CHAPTER_COUNT chapters)"
            fi
        else
            # Old format: standalone outline file
            BASENAME=$(basename "$OUTLINE_PATH")
            TIMESTAMP=$(echo "$BASENAME" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
            if [ -n "$TIMESTAMP" ]; then
                FORMATTED_DATE=$(date -r "$OUTLINE_PATH" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$TIMESTAMP")
                echo "   $((i+1))) $BASENAME (Created: $FORMATTED_DATE)"
            else
                echo "   $((i+1))) $BASENAME"
            fi
        fi
    done
    
    echo ""
    read -p "Select outline file (1-${#ALL_OUTLINES[@]}): " file_choice
    
    if [[ ! "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "${#ALL_OUTLINES[@]}" ]; then
        echo "❌ Invalid selection"
        return 1
    fi
    
    SELECTED_OUTLINE="${ALL_OUTLINES[$((file_choice-1))]}"
    
    echo ""
    echo "📖 Selected: $(basename "$SELECTED_OUTLINE")"
    echo "⏰ This will take 30-60 minutes depending on chapter count"
    echo ""
    
    read -p "🚀 Generate all chapters? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "❌ Generation cancelled"
        return 1
    fi
    
    echo ""
    pulse_text "✍️  Starting chapter generation..."

    ./full_book_generator.sh "" "" "" --chapters-only "$SELECTED_OUTLINE"

    if [ $? -eq 0 ]; then
        echo ""
        celebration "All chapters generated!"
        
        read -p "✨ Run AI review and editing? (Y/n): " run_editing
        if [[ ! $run_editing =~ ^[Nn]$ ]]; then
            BOOK_DIR=$(dirname "$SELECTED_OUTLINE")
            review_and_edit_book "$BOOK_DIR"
        fi
        
        read -p "📖 Compile into final manuscript? (Y/n): " compile_now
        if [[ ! $compile_now =~ ^[Nn]$ ]]; then
            BOOK_DIR=$(dirname "$SELECTED_OUTLINE")
            ./compile_book.sh "$BOOK_DIR"
        fi
    fi
}

review_and_edit_book() {
    local BOOK_DIR="$1"
    
    if [ -z "$BOOK_DIR" ]; then
        echo ""
        echo "📁 Available book directories:"
        
        # Look for all types of book directories
        OLD_BOOK_DIRS=($(ls -d ./book_outputs/book_outline_* 2>/dev/null))
        NEW_BOOK_DIRS=($(ls -d ./book_outputs/*-[0-9]*_[0-9]* 2>/dev/null))
        # Dynamic directories with sanitized topic names (format: topic-YYYYMMDD_HHMMSS)
        TOPIC_DIRS=($(ls -d ./book_outputs/*-2*_*_* 2>/dev/null))
        
        declare -a ALL_BOOK_DIRS
        
        # Add old format directories
        for dir in "${OLD_BOOK_DIRS[@]}"; do
            ALL_BOOK_DIRS+=("$dir")
        done
        
        # Add new format directories
        for dir in "${NEW_BOOK_DIRS[@]}"; do
            ALL_BOOK_DIRS+=("$dir")
        done
        
        # Add topic-based dynamic directories
        for dir in "${TOPIC_DIRS[@]}"; do
            if [[ ! " ${ALL_BOOK_DIRS[*]} " =~ " ${dir} " ]]; then
                ALL_BOOK_DIRS+=("$dir")
            fi
        done
        
        if [ ${#ALL_BOOK_DIRS[@]} -eq 0 ]; then
            echo "❌ No book directories found"
            return 1
        fi
        
        for i in "${!ALL_BOOK_DIRS[@]}"; do
            DIR_NAME=$(basename "${ALL_BOOK_DIRS[$i]}")
            CHAPTER_COUNT=$(ls "${ALL_BOOK_DIRS[$i]}"/chapter_*.md 2>/dev/null | wc -l)
            echo "   $((i+1))) $DIR_NAME ($CHAPTER_COUNT chapters)"
        done
        
        echo ""
        read -p "Select directory (1-${#ALL_BOOK_DIRS[@]}): " dir_choice
        
        if [[ ! "$dir_choice" =~ ^[0-9]+$ ]] || [ "$dir_choice" -lt 1 ] || [ "$dir_choice" -gt "${#ALL_BOOK_DIRS[@]}" ]; then
            echo "❌ Invalid selection"
            return 1
        fi
        
        BOOK_DIR="${ALL_BOOK_DIRS[$((dir_choice-1))]}"
    fi
    
    echo ""
    echo "✨ AI Review & Editing Options:"
    echo "   1) Quick Review (grammar, flow, consistency)"
    echo "   2) Deep Edit (rewrite for better quality)"
    echo "   3) Professional Proofread (final polish)"
    echo "   4) Full Pipeline (review → edit → proofread)"
    read -p "Choose editing level (1-4): " edit_choice
    
    case $edit_choice in
        1) edit_type="review" ;;
        2) edit_type="edit" ;;
        3) edit_type="proofread" ;;
        4) edit_type="full" ;;
        *) edit_type="review" ;;
    esac
    
    # Check if editing script exists, create if not
    if [ ! -f "./edit_book.sh" ]; then
        create_editing_script
    fi
    
    ./edit_book.sh "$BOOK_DIR" "$edit_type"
}

create_editing_script() {
    cat << 'EOF' > ./edit_book.sh
#!/bin/bash

# AI Book Editing Script
# Usage: ./edit_book.sh book_directory edit_type

set -e

BOOK_DIR="$1"
EDIT_TYPE="${2:-review}"
API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

if [ -z "$API_KEY" ]; then
    echo "❌ Error: GEMINI_API_KEY not set"
    exit 1
fi

# Function to escape JSON strings
escape_json() {
    echo -n "$1" | jq -Rs '.'
}

make_api_request() {
    local payload="$1"
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$API_URL"
}

review_chapter() {
    local chapter_file="$1"
    local chapter_content=$(cat "$chapter_file")
    
    local review_prompt="You are a professional book editor. Review this chapter for:
- Plot holes, pacing issues, and narrative flow
- Character consistency and development  
- Clarity and engagement
- Grammar and style issues
- Overall quality and readability

Provide specific, actionable feedback. Be constructive but thorough.

CHAPTER TO REVIEW:
$chapter_content"
    
    local escaped_prompt=$(escape_json "$review_prompt")
    
    local json_payload=$(jq -n \
        --arg prompt "$review_prompt" \
        '{
            "contents": [{
                "parts": [{
                    "text": $prompt
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192
            }
        }')
    
    local response=$(make_api_request "$json_payload")
    echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null || echo "Error in review"
}

edit_chapter() {
    local chapter_file="$1"
    local chapter_content=$(cat "$chapter_file")
    
    local edit_prompt="You are a professional book editor. Improve this chapter by:
- Enhancing flow and readability
- Improving sentence variety and structure
- Strengthening character development and dialogue
- Adding more vivid descriptions where appropriate
- Maintaining the original story and voice
- Ensuring 1000-2000 word length

Rewrite the chapter with these improvements:

CHAPTER TO EDIT:
$chapter_content"
    
    local escaped_prompt=$(escape_json "$edit_prompt")
    
    local json_payload=$(jq -n \
        --arg prompt "$edit_prompt" \
        '{
            "contents": [{
                "parts": [{
                    "text": $prompt
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 32768
            }
        }')
    
    local response=$(make_api_request "$json_payload")
    echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null || echo "Error in editing"
}

proofread_chapter() {
    local chapter_file="$1"
    local chapter_content=$(cat "$chapter_file")
    
    local proofread_prompt="You are a professional proofreader. Correct this chapter for:
- Grammar and punctuation errors
- Spelling mistakes
- Sentence structure issues
- Consistency in formatting
- Typos and word choice

Make only necessary corrections. Do not change the style, voice, or content significantly.

CHAPTER TO PROOFREAD:
$chapter_content"
    
    local escaped_prompt=$(escape_json "$proofread_prompt")
    
    local json_payload=$(jq -n \
        --arg prompt "$proofread_prompt" \
        '{
            "contents": [{
                "parts": [{
                    "text": $prompt
                }]
            }],
            "generationConfig": {
                "temperature": 0.3,
                "topK": 20,
                "topP": 0.9,
                "maxOutputTokens": 32768
            }
        }')
    
    local response=$(make_api_request "$json_payload")
    echo "$response" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null || echo "Error in proofreading"
}

# Main editing logic
CHAPTER_FILES=($(ls "$BOOK_DIR"/chapter_*.md 2>/dev/null | sort -V))

if [ ${#CHAPTER_FILES[@]} -eq 0 ]; then
    echo "❌ No chapter files found in $BOOK_DIR"
    exit 1
fi

echo "✨ Starting AI editing process..."
echo "📂 Book directory: $BOOK_DIR"
echo "🔧 Edit type: $EDIT_TYPE"
echo "📚 Chapters found: ${#CHAPTER_FILES[@]}"
echo ""

for CHAPTER_FILE in "${CHAPTER_FILES[@]}"; do
    CHAPTER_NUM=$(basename "$CHAPTER_FILE" .md | sed 's/chapter_//')
    
    case $EDIT_TYPE in
        "review")
            echo "📝 Reviewing Chapter $CHAPTER_NUM..."
            REVIEW_OUTPUT=$(review_chapter "$CHAPTER_FILE")
            echo "$REVIEW_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_review.md"
            echo "✅ Review complete: chapter_${CHAPTER_NUM}_review.md"
            ;;
        "edit")
            echo "✏️ Editing Chapter $CHAPTER_NUM..."
            EDIT_OUTPUT=$(edit_chapter "$CHAPTER_FILE")
            echo "$EDIT_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_edited.md"
            echo "✅ Edit complete: chapter_${CHAPTER_NUM}_edited.md"
            ;;
        "proofread")
            echo "🔍 Proofreading Chapter $CHAPTER_NUM..."
            PROOF_OUTPUT=$(proofread_chapter "$CHAPTER_FILE")
            echo "$PROOF_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_proofed.md"
            echo "✅ Proofread complete: chapter_${CHAPTER_NUM}_proofed.md"
            ;;
        "full")
            echo "🔄 Full editing pipeline for Chapter $CHAPTER_NUM..."
            
            echo "  📝 Step 1: Review..."
            REVIEW_OUTPUT=$(review_chapter "$CHAPTER_FILE")
            echo "$REVIEW_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_review.md"
            
            echo "  ✏️ Step 2: Edit..."
            EDIT_OUTPUT=$(edit_chapter "$CHAPTER_FILE")
            echo "$EDIT_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_edited.md"
            
            echo "  🔍 Step 3: Proofread..."
            PROOF_OUTPUT=$(proofread_chapter "${BOOK_DIR}/chapter_${CHAPTER_NUM}_edited.md")
            echo "$PROOF_OUTPUT" > "${BOOK_DIR}/chapter_${CHAPTER_NUM}_final.md"
            
            echo "✅ Full pipeline complete: chapter_${CHAPTER_NUM}_final.md"
            ;;
    esac
    
    sleep 2  # Rate limiting
done

echo ""
echo "🎉 Editing process complete!"
echo "📁 All edited files saved in: $BOOK_DIR"

EOF

    chmod +x ./edit_book.sh
    echo "📝 Created editing script: edit_book.sh"
}

compile_manuscript() {
    echo ""
    echo "📁 Available book directories:"
    
    # Look for all types of book directories
    OLD_BOOK_DIRS=($(ls -d ./book_outputs/book_outline_* 2>/dev/null))
    NEW_BOOK_DIRS=($(ls -d ./book_outputs/*-[0-9]*_[0-9]* 2>/dev/null))
    # Dynamic directories with sanitized topic names (format: topic-YYYYMMDD_HHMMSS)
    TOPIC_DIRS=($(ls -d ./book_outputs/*-2*_*_* 2>/dev/null))
    
    declare -a ALL_BOOK_DIRS
    
    # Add old format directories
    for dir in "${OLD_BOOK_DIRS[@]}"; do
        ALL_BOOK_DIRS+=("$dir")
    done
    
    # Add new format directories
    for dir in "${NEW_BOOK_DIRS[@]}"; do
        ALL_BOOK_DIRS+=("$dir")
    done
    
    # Add topic-based dynamic directories
    for dir in "${TOPIC_DIRS[@]}"; do
        if [[ ! " ${ALL_BOOK_DIRS[*]} " =~ " ${dir} " ]]; then
            ALL_BOOK_DIRS+=("$dir")
        fi
    done
    
    if [ ${#ALL_BOOK_DIRS[@]} -eq 0 ]; then
        echo "❌ No book directories found"
        return 1
    fi
    
    for i in "${!ALL_BOOK_DIRS[@]}"; do
        DIR_NAME=$(basename "${ALL_BOOK_DIRS[$i]}")
        CHAPTER_COUNT=$(ls "${ALL_BOOK_DIRS[$i]}"/chapter_*.md 2>/dev/null | wc -l)
        echo "   $((i+1))) $DIR_NAME ($CHAPTER_COUNT chapters)"
    done
    
    echo ""
    read -p "Select directory (1-${#ALL_BOOK_DIRS[@]}): " dir_choice
    
    if [[ ! "$dir_choice" =~ ^[0-9]+$ ]] || [ "$dir_choice" -lt 1 ] || [ "$dir_choice" -gt "${#ALL_BOOK_DIRS[@]}" ]; then
        echo "❌ Invalid selection"
        return 1
    fi
    
    SELECTED_DIR="${ALL_BOOK_DIRS[$((dir_choice-1))]}"
    
    echo ""
    echo "📄 Choose chapter version:"
    echo "   1) Original chapters"
    echo "   2) Edited chapters (if available)"
    echo "   3) Final/Proofread chapters (if available)"
    read -p "Choose version (1-3): " version_choice
    
    echo ""
    echo "📄 Output format:"
    echo "   1) Markdown (for KDP)"
    echo "   2) HTML (for web)"
    echo "   3) PDF (requires pandoc)"
    read -p "Choose format (1-3): " format_choice
    
    case $format_choice in
        1) FORMAT="markdown" ;;
        2) FORMAT="html" ;;
        3) FORMAT="pdf" ;;
        *) FORMAT="markdown" ;;
    esac
    
    loading_dots 2 "Preparing compilation"
    ./compile_book.sh "$SELECTED_DIR" "$FORMAT" "$version_choice"
}

# Enhanced suggest_topics function that returns parameters for book generation
suggest_topics() {
    # Variable to keep track of previous suggestions for exclusion
    local PREVIOUS_SUGGESTIONS=""
    local ATTEMPT=1
    
    generate_topic_suggestions() {
        loading_dots 8 "➡️  📚 Generating 5 book topic suggestions (Attempt ${ATTEMPT})"
        CURRENT_DATE=$(date +"%B %Y")
        
        local exclusion_clause=""
        if [ -n "$PREVIOUS_SUGGESTIONS" ]; then
            exclusion_clause="IMPORTANT: Do NOT suggest any of these previous topics again: $PREVIOUS_SUGGESTIONS. Generate completely new topics that are different from previous suggestions."
        fi
        
        SUGGESTION_PROMPT="Search the internet, research and collect 20 potential book topics, then randomly select 5 to provide detailed book suggestions based on the following criteria:
- Topics and genres with demand and less saturation (e.g., from Kindle Direct Publishing trends).
- Topics that solve narrowly defined reader problems, pain points, or frustrations.
- Current ($CURRENT_DATE) in-demand topics with a high probability of success and low risk of failure.
- Topics with potential for creating additional books (series, bundles, etc.).
- Topics that are easier to create (less research required) and have low competition in the (sub) genre.
- Include at least one fiction topic.
- Ensure there are a wide variety of topics covered, including different genres and themes.

Each suggestion MUST include these details in a structured format for EACH book:
1. Topic/Title
2. Genre
3. Target Audience
4. Writing Style (one of: detailed, narrative, academic, analytical, descriptive, persuasive, expository, technical)
5. Tone (one of: professional, conversational, authoritative, casual, persuasive, humorous, inspirational, empathetic, bold)

$exclusion_clause

Important: Format your response as a numbered list 1-5, with each book having clear Title, Genre, Target Audience, Style and Tone. Do NOT include any text before or after the list."
        
        ESCAPED_SUGGESTION_PROMPT=$(escape_json "$SUGGESTION_PROMPT")
        SUGGESTION_JSON_PAYLOAD=$(jq -n \
            --arg prompt "$SUGGESTION_PROMPT" \
            '{
                "contents": [{
                    "parts": [{
                        "text": $prompt
                    }]
                }],
                "generationConfig": {
                    "temperature": 1.0,
                    "topK": 40,
                    "topP": 0.95,
                    "maxOutputTokens": 1500
                }
            }')
        RESPONSE=$(make_api_request "$SUGGESTION_JSON_PAYLOAD")

        if [ $? -ne 0 ]; then
            echo "❌ Failed to fetch suggestions. Please try again."
            return 1
        fi

        # Clean the response, only show the text from first numbered option through the end of the 5th suggestion
        RES=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
        
        # Strip all markdown formatting - including all asterisks (*)
        SUGGESTIONS=$(echo "$RES" | sed 's/^[-*] //g; s/\*//g; s/^# //g; s/^## //g; s/^### //g;')
        
        # Append current suggestions to previous ones for exclusion in future generations
        for i in {1..5}; do
            local this_topic=$(echo "$SUGGESTIONS" | grep -i "^$i\." | sed 's/^[0-9]\.//' | sed 's/^[[:space:]]*//')
            if [ -n "$this_topic" ]; then
                if [ -z "$PREVIOUS_SUGGESTIONS" ]; then
                    PREVIOUS_SUGGESTIONS="$this_topic"
                else
                    PREVIOUS_SUGGESTIONS="$PREVIOUS_SUGGESTIONS, $this_topic"
                fi
            fi
        done
        
        return 0
    }
    
    # Generate initial suggestions
    if ! generate_topic_suggestions; then
        return 1
    fi
    
    while true; do
        # Clear the terminal and show suggestions
        clear
        echo "✅ Suggestions received:"
        echo ""
        echo ""
        echo "$SUGGESTIONS"
        echo ""
        echo "6. Generate more topics"
        echo ""
        echo "Please select one of the options above by entering the corresponding number (1-6):"
        read -p "Your choice: " selected_option

        if [[ "$selected_option" = "6" ]]; then
            # User wants more suggestions
            ATTEMPT=$((ATTEMPT + 1))
            if ! generate_topic_suggestions; then
                return 1
            fi
            continue
        elif [[ ! "$selected_option" =~ ^[1-5]$ ]]; then
            echo "❌ Invalid selection. Please choose a number between 1-6."
            sleep 2
            continue
        else
            # Valid selection (1-5), proceed with the book generation
            break
        fi
    done
    
    # Extract the selected suggestion robustly: capture from the selected numbered line
    # up to (but not including) the next numbered suggestion. Use awk for reliable parsing.
    SELECTED_SUGGESTION=$(echo "$SUGGESTIONS" | awk -v n="$selected_option" '
    BEGIN {printing=0; pattern = "^" n "\\."}
    {
        if ($0 ~ pattern) { printing=1 }
        else if (printing && $0 ~ /^[0-9]+\./) { exit }
        if (printing) print
    }')

    # Trim leading/trailing whitespace from the extracted block
    SELECTED_SUGGESTION=$(echo "$SELECTED_SUGGESTION" | sed -e 's/^\s\+//' -e 's/\s\+$//')
    
    # Parse the suggestion to extract parameters
    # Extract fields from the selected suggestion block safely (only first matching lines)
    TOPIC=$(echo "$SELECTED_SUGGESTION" | awk 'BEGIN{IGNORECASE=1} /Title|Topic/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}')
    GENRE=$(echo "$SELECTED_SUGGESTION" | awk 'BEGIN{IGNORECASE=1} /Genre/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}')
    AUDIENCE=$(echo "$SELECTED_SUGGESTION" | awk 'BEGIN{IGNORECASE=1} /Audience/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}')
    STYLE=$(echo "$SELECTED_SUGGESTION" | awk 'BEGIN{IGNORECASE=1} /Style/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' | tr '[:upper:]' '[:lower:]')
    TONE=$(echo "$SELECTED_SUGGESTION" | awk 'BEGIN{IGNORECASE=1} /Tone/ {sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' | tr '[:upper:]' '[:lower:]')

    # Fallback: if TOPIC seems empty, try to extract the first non-empty line of the block
    if [ -z "$TOPIC" ]; then
        TOPIC=$(echo "$SELECTED_SUGGESTION" | sed -n '1,3p' | sed '/^\s*$/d' | head -1)
    fi
    
    # Set default style if not found or invalid
    if ! [[ "$STYLE" =~ ^(detailed|narrative|academic|analytical|descriptive|persuasive|expository|technical)$ ]]; then
        STYLE="detailed"
    fi
    
    # Set default tone if not found or invalid
    if ! [[ "$TONE" =~ ^(professional|conversational|authoritative|casual|persuasive|humorous|inspirational|empathetic|bold)$ ]]; then
        TONE="professional"
    fi
    
    # Export variables for use in the main script
    export TOPIC="$TOPIC"
    export GENRE="$GENRE"
    export AUDIENCE="$AUDIENCE"
    export STYLE="$STYLE"
    export TONE="$TONE"
    
    echo ""
    echo "📖 Selected Book Details:"
    echo "   Topic: $TOPIC"
    echo "   Genre: $GENRE"
    echo "   Audience: $AUDIENCE"
    echo "   Style: $STYLE"
    echo "   Tone: $TONE"
    echo ""
    
    # Return success
    return 0
}

# Main execution
main() {
    # Check dependencies
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required but not installed"
        echo "Install with: sudo apt install jq"
        exit 1
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "❌ Error: curl is required but not installed"
        echo "Install with: sudo apt install curl"
        exit 1
    fi

    # Create output directory
    mkdir -p ./book_outputs

    while true; do
        show_interactive_menu
        read choice

        case $choice in
            1)
                if suggest_topics; then
                    generate_complete_book_from_suggestion
                else
                    echo "❌ Failed to fetch suggestions. Exiting."
                    exit 1
                fi
                read -p "Press Enter to continue..."
                ;;
            2)
                if suggest_topics; then
                    generate_outline_only_from_suggestion
                else
                    echo "❌ Failed to fetch suggestions. Exiting."
                    exit 1
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                generate_chapters_from_outline
                read -p "Press Enter to continue..."
                ;;
            4)
                compile_manuscript
                read -p "Press Enter to continue..."
                ;;
            5)
                review_and_edit_book
                read -p "Press Enter to continue..."
                ;;
            6)
                configure_settings
                ;;
            7)
                show_help
                ;;
            8)
                # Calculate and display elapsed time before exiting
                END_TIME=$(date +%s)
                ELAPSED_TIME=$((END_TIME - START_TIME))
                HOURS=$((ELAPSED_TIME / 3600))
                MINUTES=$(( (ELAPSED_TIME % 3600) / 60 ))
                SECONDS=$((ELAPSED_TIME % 60))
                
                echo ""
                echo "⏱️ Session duration: ${HOURS}h ${MINUTES}m ${SECONDS}s (started: $(date -r $START_TIME '+%Y-%m-%d %H:%M:%S'), finished: $(date -r $END_TIME '+%Y-%m-%d %H:%M:%S'))"
                echo "👋 Goodbye! Happy writing!"
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Please choose 1-8."
                sleep 2
                ;;
        esac
    done
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi