#!/bin/bash

# Easy Book Generator - One command to rule them all
# Usage: ./easy_book.sh

set -e

show_interactive_menu() {
    clear
    cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                   📚 AI Book Generator                   ║
║              Complete Workflow Automation                ║
╚══════════════════════════════════════════════════════════╝

Choose your workflow:

1) 🚀 Generate Complete Book (Outline + All Chapters)
2) 📋 Generate Outline Only  
3) ✍️  Generate Chapters from Existing Outline
4) 📖 Compile Existing Chapters into Manuscript
5) ⚙️  Configure Settings
6) ❓ Help & Examples
7) 🚪 Exit

EOF
    echo -n "Select option (1-7): "
}

configure_settings() {
    echo ""
    echo "⚙️ Current Settings:"
    echo "   API Key: ${GEMINI_API_KEY:+Set}${GEMINI_API_KEY:-Not Set}"
    echo "   Model: ${BOOK_MODEL:-gemini-1.5-flash-latest}"
    echo "   Temperature: ${BOOK_TEMPERATURE:-0.8}"
    echo "   Words per chapter: ${BOOK_MIN_WORDS:-2000}-${BOOK_MAX_WORDS:-2500}"
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
    
    echo "✅ Settings updated"
    read -p "Press Enter to continue..."
}

show_help() {
    cat << 'EOF'
📚 AI Book Generator Help

WHAT IT DOES:
This tool generates complete 30,000-word books using AI, formatted for KDP publishing.

WORKFLOW:
1. Creates detailed book outline (12-15 chapters)
2. Generates each chapter (2,000-2,500 words)
3. Compiles everything into publication-ready manuscript

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
- Each book takes 30-60 minutes to generate completely
- Generated books are 25,000-35,000 words typically

FILE OUTPUTS:
- book_outline_[timestamp].md - The book structure
- chapter_1.md through chapter_N.md - Individual chapters  
- manuscript_[timestamp].md - Complete book ready for publishing
- Optional: HTML and PDF versions

EOF
    read -p "Press Enter to continue..."
}

get_book_details() {
    echo ""
    echo "📝 Enter Book Details:"
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
    # echo "   4) Analytical     - Breaks down complex ideas logically"
    # echo "   5) Descriptive    - Rich imagery and sensory details"
    # echo "   6) Persuasive     - Aims to convince or influence"
    # echo "   7) Expository     - Explains facts and processes clearly"
    # echo "   8) Technical      - Precision-focused, for technical audiences"
    read -p "Choose style (1-3) or press Enter for Detailed: " style_choice

    case $style_choice in
        2) STYLE="narrative" ;;
        3) STYLE="academic" ;;
        # 4) STYLE="analytical" ;;
        # 5) STYLE="descriptive" ;;
        # 6) STYLE="persuasive" ;;
        # 7) STYLE="expository" ;;
        # 8) STYLE="technical" ;;
        1|"") STYLE="detailed" ;;  # Default
        *) STYLE="detailed" ;;
    esac
    
    echo ""
    echo "🗣️ Choose a Writing Tone:"
    echo "   1) Professional     - Formal, clear, and businesslike"
    echo "   2) Conversational   - Friendly and relaxed, like talking to a friend"
    echo "   3) Authoritative    - Confident and credible, like an expert"
    # echo "   4) Casual           - Informal and laid-back"
    # echo "   5) Persuasive       - Influential and convincing"
    # echo "   6) Humorous         - Light-hearted and witty"
    # echo "   7) Inspirational    - Uplifting and motivational"
    # echo "   8) Empathetic       - Compassionate and understanding"
    # echo "   9) Bold             - Direct, edgy, and unapologetic"
    read -p "Choose tone (1-3) or press Enter for Professional: " tone_choice

    
    case "$tone_choice" in
        2) tone="Conversational" ;;
        3) tone="Authoritative" ;;
        # 4) tone="Casual" ;;
        # 5) tone="Persuasive" ;;
        # 6) tone="Humorous" ;;
        # 7) tone="Inspirational" ;;
        # 8) tone="Empathetic" ;;
        # 9) tone="Bold" ;;
        *) tone="Professional" ;;
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
    
    read -p "🚀 Generate this book? This will take 30-60 minutes. (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "❌ Generation cancelled"
        return 1
    fi
    
    echo ""
    echo "🚀 Starting complete book generation..."
    echo "⏰ Started at: $(date)"

    # Check if full_book_generator.sh exists
    if [ ! -f "./full_book_generator.sh" ]; then
        echo "❌ Error: full_book_generator.sh not found"
        echo "Make sure all scripts are in the current directory"
        return 1
    fi
    
    # Run the full book generator
    ./full_book_generator.sh $TOPIC $GENRE $AUDIENCE \
        --style $STYLE \
        --tone $TONE \
        --delay 30
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 Book generation completed at: $(date)"
        echo ""
        read -p "📖 Compile into final manuscript now? (Y/n): " compile_now
        if [[ ! $compile_now =~ ^[Nn]$ ]]; then
            # Find the most recent book directory
            LATEST_DIR=$(ls -td ./book_outputs/book_outline_* 2>/dev/null | head -1)
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
    if ! get_book_details; then
        return 1
    fi
    
    echo ""
    echo "📋 Generating outline only..."

    ./full_book_generator.sh $TOPIC $GENRE $AUDIENCE \
        --style $STYLE \
        --tone $TONE \
        --outline-only
        
    if [ $? -eq 0 ]; then
        echo "✅ Outline generated successfully"
        echo "Use option 3 to generate chapters from this outline"
    fi
}

generate_chapters_from_outline() {
    echo ""
    echo "📁 Available outline files:"
    
    OUTLINE_FILES=($(ls ./book_outputs/book_outline_*.md 2>/dev/null))
    
    if [ ${#OUTLINE_FILES[@]} -eq 0 ]; then
        echo "❌ No outline files found in ./book_outputs/"
        echo "Generate an outline first using option 2"
        return 1
    fi
    
    for i in "${!OUTLINE_FILES[@]}"; do
        BASENAME=$(basename "${OUTLINE_FILES[$i]}")
        TIMESTAMP=$(echo "$BASENAME" | grep -o '[0-9]\{8\}_[0-9]\{6\}')
        FORMATTED_DATE=$(date -d "${TIMESTAMP:0:8} ${TIMESTAMP:9:2}:${TIMESTAMP:11:2}:${TIMESTAMP:13:2}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$TIMESTAMP")
        echo "   $((i+1))) $BASENAME (Created: $FORMATTED_DATE)"
    done
    
    echo ""
    read -p "Select outline file (1-${#OUTLINE_FILES[@]}): " file_choice
    
    if [[ ! "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 1 ] || [ "$file_choice" -gt "${#OUTLINE_FILES[@]}" ]; then
        echo "❌ Invalid selection"
        return 1
    fi
    
    SELECTED_OUTLINE="${OUTLINE_FILES[$((file_choice-1))]}"
    
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
    echo "✍️ Starting chapter generation..."

    ./full_book_generator.sh "" "" "" --chapters-only $SELECTED_OUTLINE

    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ All chapters generated!"
        read -p "📖 Compile into final manuscript? (Y/n): " compile_now
        if [[ ! $compile_now =~ ^[Nn]$ ]]; then
            BOOK_DIR=$(dirname "$SELECTED_OUTLINE")
            ./compile_book.sh "$BOOK_DIR"
        fi
    fi
}

compile_manuscript() {
    echo ""
    echo "📁 Available book directories:"
    
    BOOK_DIRS=($(ls -d ./book_outputs/book_outline_* 2>/dev/null))
    
    if [ ${#BOOK_DIRS[@]} -eq 0 ]; then
        echo "❌ No book directories found"
        return 1
    fi
    
    for i in "${!BOOK_DIRS[@]}"; do
        DIR_NAME=$(basename "${BOOK_DIRS[$i]}")
        CHAPTER_COUNT=$(ls "${BOOK_DIRS[$i]}"/chapter_*.md 2>/dev/null | wc -l)
        echo "   $((i+1))) $DIR_NAME ($CHAPTER_COUNT chapters)"
    done
    
    echo ""
    read -p "Select directory (1-${#BOOK_DIRS[@]}): " dir_choice
    
    if [[ ! "$dir_choice" =~ ^[0-9]+$ ]] || [ "$dir_choice" -lt 1 ] || [ "$dir_choice" -gt "${#BOOK_DIRS[@]}" ]; then
        echo "❌ Invalid selection"
        return 1
    fi
    
    SELECTED_DIR="${BOOK_DIRS[$((dir_choice-1))]}"
    
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
    
    ./compile_book.sh "$SELECTED_DIR" "$FORMAT"
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
                generate_complete_book
                read -p "Press Enter to continue..."
                ;;
            2)
                generate_outline_only
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
                configure_settings
                ;;
            6)
                show_help
                ;;
            7)
                echo "👋 Goodbye! Happy writing!"
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Please choose 1-7."
                sleep 2
                ;;
        esac
    done
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi