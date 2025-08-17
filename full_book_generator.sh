#!/bin/bash

# Complete Book Generation Workflow
# Usage: ./generate_full_book.sh "Book Topic" "Genre" "Target Audience" [OPTIONS]

set -e

# Default configuration
API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
TEMPERATURE=0.8
TOP_K=50
TOP_P=0.9
MAX_TOKENS=200000
MIN_WORDS=2000
MAX_WORDS=2500
WRITING_STYLE="detailed"
TONE="professional"
DELAY_BETWEEN_CHAPTERS=15  # Seconds to avoid rate limits
OUTLINE_ONLY=false
CHAPTERS_ONLY=""

# Plagiarism checking configuration
ENABLE_PLAGIARISM_CHECK=true
PLAGIARISM_CHECK_STRICTNESS="medium"  # low, medium, high
AUTO_REWRITE_ON_FAIL=true
ORIGINALITY_THRESHOLD=6  # Minimum score out of 10
PLAGIARISM_RECHECK_LIMIT=2  # Maximum retries for rewritten content

show_help() {
    cat << EOF
Complete Book Generation Workflow

USAGE:
    $0 "Book Topic" "Genre" "Target Audience" [OPTIONS]

REQUIRED ARGUMENTS:
    "Book Topic"        - Main subject of the book
    "Genre"            - Book genre (Self-Help, Fiction, Business, etc.)
    "Target Audience"  - Intended readers (Young Adults 25-35, etc.)

OPTIONS:
    -m, --model MODEL           Gemini model (flash-latest, pro-latest)
    -t, --temperature TEMP      Temperature 0.0-1.0 (default: 0.8)
    --min-words WORDS          Minimum words per chapter (default: 2000)
    --max-words WORDS          Maximum words per chapter (default: 2500)
    --style STYLE              Writing style: detailed|narrative|academic
    --tone TONE                Tone: professional|casual|authoritative
    --preset PRESET            Use preset: creative|technical|fiction|business
    --delay SECONDS            Delay between chapters (default: 30)
    --outline-only             Generate outline only, don't create chapters
    --chapters-only FILE       Generate chapters from existing outline file
    -h, --help                 Show this help

PLAGIARISM CHECKING OPTIONS:
    --no-plagiarism-check      Disable plagiarism checking
    --plagiarism-strict        Use strict plagiarism checking
    --plagiarism-threshold N   Set minimum originality score (1-10, default: 6)
    --no-auto-rewrite         Don't automatically rewrite flagged chapters

EXAMPLES:
    $0 "Personal Finance for Millennials" "Self-Help" "Young Adults 25-35"
    $0 "AI in Healthcare" "Technical" "Medical Professionals" --preset technical
    $0 "The Dragon's Quest" "Fantasy Fiction" "Young Adults" --preset creative --delay 45

PLAGIARISM CHECKING EXAMPLES:
    $0 "Book Topic" "Genre" "Audience" --plagiarism-strict
    $0 "Book Topic" "Genre" "Audience" --plagiarism-threshold 8
    $0 "Book Topic" "Genre" "Audience" --no-plagiarism-check
EOF
}

# Function to check for plagiarism and copyright issues using Gemini LLM
check_plagiarism_and_copyright() {
    local chapter_file="$1"
    local chapter_content=$(cat "$chapter_file")
    local chapter_num=$(basename "$chapter_file" .md | sed 's/chapter_//')
    
    echo "🔍 Checking Chapter $chapter_num for plagiarism and copyright issues..."
    echo "DEBUG: Starting plagiarism check function for chapter $chapter_num" >&2
    
    local check_prompt="You are an expert copyright and plagiarism detection system. Analyze the following text for:

1. PLAGIARISM INDICATORS:
   - Passages that may be copied from existing published works
   - Unusual writing style changes that might indicate copied content
   - Overly specific facts, quotes, or statistics without attribution
   - Content that sounds too polished compared to surrounding text

2. COPYRIGHT CONCERNS:
   - Direct quotes from copyrighted materials
   - Paraphrased content that's too close to original sources
   - Use of proprietary concepts, methodologies, or frameworks
   - References to trademarked terms or branded content

3. ORIGINALITY ASSESSMENT:
   - Rate the overall originality from 1-10 (10 = completely original)
   - Identify any sections that need rewriting
   - Flag potential legal issues

Respond in this EXACT format:
ORIGINALITY_SCORE: [1-10]
PLAGIARISM_RISK: [LOW/MEDIUM/HIGH]
COPYRIGHT_RISK: [LOW/MEDIUM/HIGH]
ISSUES_FOUND: [YES/NO]

DETAILED_ANALYSIS:
[Your detailed analysis here]

FLAGGED_SECTIONS:
[List any specific problematic sections with line numbers or quotes]

RECOMMENDATIONS:
[Specific actions to take]

TEXT TO ANALYZE:
$chapter_content"

    local escaped_prompt=$(escape_json "$check_prompt")
    
    local json_payload=$(jq -n \
        --arg prompt "$check_prompt" \
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
                "maxOutputTokens": 4096
            }
        }')

    local response=$(make_api_request "$json_payload")
    
    if [ $? -ne 0 ]; then
        echo "❌ Plagiarism check failed for Chapter $chapter_num"
        return 1
    fi

    local check_result=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text')
    
    # Save the check result
    local check_report_file="${BOOK_DIR}/chapter_${chapter_num}_plagiarism_report.md"
    echo "$check_result" > "$check_report_file"
    
    # Parse the results
    local originality_score=$(echo "$check_result" | grep "ORIGINALITY_SCORE:" | sed 's/ORIGINALITY_SCORE: //')
    local plagiarism_risk=$(echo "$check_result" | grep "PLAGIARISM_RISK:" | sed 's/PLAGIARISM_RISK: //')
    local copyright_risk=$(echo "$check_result" | grep "COPYRIGHT_RISK:" | sed 's/COPYRIGHT_RISK: //')
    local issues_found=$(echo "$check_result" | grep "ISSUES_FOUND:" | sed 's/ISSUES_FOUND: //')
    
    echo "📊 Plagiarism Check Results for Chapter $chapter_num:"
    echo "   Originality Score: $originality_score/10"
    echo "   Plagiarism Risk: $plagiarism_risk"
    echo "   Copyright Risk: $copyright_risk"
    echo "   Issues Found: $issues_found"
    echo "   Report saved: $(basename "$check_report_file")"
    
    # Return status based on risk levels and score
    local return_code=0
    if [[ "$issues_found" == "YES" ]] || [[ "$plagiarism_risk" == "HIGH" ]] || [[ "$copyright_risk" == "HIGH" ]] || [[ "$originality_score" -lt 6 ]]; then
        return_code=2  # Needs rewriting
    elif [[ "$plagiarism_risk" == "MEDIUM" ]] || [[ "$copyright_risk" == "MEDIUM" ]] || [[ "$originality_score" -lt 8 ]]; then
        return_code=1  # Warning level
    else
        return_code=0  # Passed
    fi
    
    echo "DEBUG: check_plagiarism_and_copyright returning code: $return_code for chapter $chapter_num" >&2
    return $return_code
}

# Function to rewrite chapter to address plagiarism/copyright issues
rewrite_chapter_for_originality() {
    local chapter_file="$1"
    local plagiarism_report="$2"
    local chapter_num=$(basename "$chapter_file" .md | sed 's/chapter_//')
    local attempt="${3:-1}"
    local word_count_ok="${4:-false}"
    
    echo "🔄 Rewriting Chapter $chapter_num to address originality issues (attempt $attempt)..."
    echo "DEBUG: Starting rewrite_chapter_for_originality for chapter $chapter_num" >&2
    
    local original_content=$(cat "$chapter_file")
    local check_analysis=$(cat "$plagiarism_report")
    local current_word_count=$(echo "$original_content" | wc -w)
    
    # Adjust temperature based on attempt number to increase variability
    local temp_adjustment=$(echo "scale=2; 0.1 * ($attempt - 1)" | bc)
    local rewrite_temp=$(echo "scale=2; 0.7 + $temp_adjustment" | bc)
    
    # Build the prompt with appropriate word count instructions
    local word_count_instruction=""
    if [ "$word_count_ok" = "false" ]; then
        word_count_instruction="IMPORTANT WORD COUNT REQUIREMENT:
- Current chapter is only $current_word_count words
- MUST expand to at least 2000 words, preferably 2000-2500 words
- Add more examples, detailed explanations, and practical applications
- Elaborate on each concept with more depth
- Do not use filler or fluff - all content must be valuable and substantive"
    fi
    
    local rewrite_prompt="You are an expert author tasked with rewriting content to ensure complete originality while maintaining quality and value. This is rewrite attempt #$attempt.

ORIGINAL CHAPTER:
$original_content

PLAGIARISM/COPYRIGHT ANALYSIS:
$check_analysis

REWRITING REQUIREMENTS:
1. Completely rewrite any flagged sections
2. Use original examples, analogies, and explanations
3. Maintain the same chapter structure and key points
4. Ensure 100% original content with unique voice
5. Target 2000-2500 words
6. Use different sentence structures and vocabulary
7. Create original case studies, examples, and scenarios
8. Avoid any potentially copyrighted expressions or concepts

$word_count_instruction

WRITING GUIDELINES:
- Use your own unique voice and style
- Create original examples and anecdotes
- Rephrase all concepts in your own words
- Ensure all ideas are expressed originally
- Make content engaging and valuable
- Maintain professional quality

Please rewrite the entire chapter with complete originality:"

    local escaped_prompt=$(escape_json "$rewrite_prompt")
    
    local json_payload=$(jq -n \
        --arg prompt "$rewrite_prompt" \
        --arg maxtokens "$MAX_TOKENS" \
        --arg temperature "$rewrite_temp" \
        '{
            "contents": [{
                "parts": [{
                    "text": $prompt
                }]
            }],
            "generationConfig": {
                "temperature": ($temperature | tonumber),
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": $maxtokens
            }
        }')

    local response=$(make_api_request "$json_payload")
    
    if [ $? -ne 0 ]; then
        echo "❌ Chapter rewrite failed"
        return 1
    fi

    # Save the rewritten chapter
    local backup_file="${chapter_file}.backup_$(date +%s)"
    cp "$chapter_file" "$backup_file"
    echo "📄 Original backed up to: $(basename "$backup_file")"
    
    echo "$response" | jq -r '.candidates[0].content.parts[0].text' > "$chapter_file"
    echo "✅ Chapter $chapter_num rewritten for originality"
    
    return 0
}

# Function to perform multiple plagiarism checks (for extra security)
multi_check_plagiarism() {
    local chapter_file="$1"
    local chapter_num=$(basename "$chapter_file" .md | sed 's/chapter_//')
    
    echo "🔍 Running comprehensive plagiarism check for Chapter $chapter_num..."
    echo "DEBUG: Starting multi_check_plagiarism for chapter $chapter_num" >&2
    
    # Run initial check without allowing it to exit the script
    set +e # Make sure we don't exit on error
    echo "DEBUG: About to run check_plagiarism_and_copyright" >&2
    check_plagiarism_and_copyright "$chapter_file" 2>/tmp/plagiarism_check_$chapter_num.log
    local initial_result=$?
    echo "DEBUG: check_plagiarism_and_copyright returned $initial_result" >&2
    cat /tmp/plagiarism_check_$chapter_num.log >&2
    
    echo "DEBUG: multi_check_plagiarism got result $initial_result from check_plagiarism_and_copyright" >&2
    
    # Always return the result rather than exiting
    if [ $initial_result -eq 2 ]; then
        echo "⚠️  High risk detected. Performing secondary analysis..."
        
        # Run a more detailed check focusing on specific sections
        local chapter_content=$(cat "$chapter_file")
        local detailed_prompt="Perform a detailed line-by-line analysis of this text for potential plagiarism. Focus on:
- Unique phrases that might be copied
- Technical terminology that might be proprietary
- Statistical data that might be from specific sources
- Methodologies that might be copyrighted

Rate each paragraph's originality and flag any concerns:

TEXT TO ANALYZE:
$chapter_content"

        local escaped_detailed=$(escape_json "$detailed_prompt")
        local detailed_payload=$(jq -n \
            --arg prompt "$detailed_prompt" \
            '{
                "contents": [{
                    "parts": [{
                        "text": $prompt
                    }]
                }],
                "generationConfig": {
                    "temperature": 0.2,
                    "topK": 10,
                    "topP": 0.8,
                    "maxOutputTokens": 4096
                }
            }')

        local detailed_response=$(make_api_request "$detailed_payload")
        local detailed_analysis=$(echo "$detailed_response" | jq -r '.candidates[0].content.parts[0].text')
        
        # Save detailed analysis
        echo "$detailed_analysis" > "${BOOK_DIR}/chapter_${chapter_num}_detailed_analysis.md"
        echo "📋 Detailed analysis saved"
    fi
    
    return $initial_result
}

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Function for classic loading dots
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

# Function for showing a colorful snake-like spinner
snake_spinner() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local colors=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$MAGENTA")
    local snake="▮▯▮▯▮▯▮▯▮▯"
    
    while [ $count -lt $((duration * 10)) ]; do
        local color_idx=$((count % ${#colors[@]}))
        local snake_pos=$((count % 10))
        printf "\r\033[K🐍 $message ${colors[$color_idx]}%s${RESET}" "${snake:$snake_pos:10}"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Rainbow text animation
rainbow_text() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local colors=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$MAGENTA")
    
    while [ $count -lt $((duration * 10)) ]; do
        printf "\r\033[K"
        for ((i=0; i<${#message}; i++)); do
            local color_idx=$(( (count+i) % ${#colors[@]} ))
            printf "${colors[$color_idx]}%s${RESET}" "${message:$i:1}"
        done
        
        printf " 🌈"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Bouncing bar animation
bouncing_bar() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local width=20
    local position=0
    local direction=1
    
    while [ $count -lt $((duration * 10)) ]; do
        local bar=""
        for ((i=0; i<width; i++)); do
            if [ $i -eq $position ]; then
                bar+="${GREEN}■${RESET}"
            else
                bar+="□"
            fi
        done
        
        printf "\r\033[K🔄 $message [%s]" "$bar"
        
        # Update position for bouncing effect
        position=$((position + direction))
        if [ $position -eq 0 ] || [ $position -eq $((width-1)) ]; then
            direction=$((direction * -1))
        fi
        
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Typewriter effect
typewriter() {
    local message="${1:-Processing complete!}"
    local speed=${2:-0.05}
    
    printf "\r\033[K"
    for ((i=0; i<${#message}; i++)); do
        printf "%s" "${message:0:$i+1}"
        sleep "$speed"
    done
    echo ""
}

# Radar spinner animation
radar_spinner() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local spinner_frames=('◜' '◠' '◝' '◞' '◡' '◟')
    
    while [ $count -lt $((duration * 10)) ]; do
        local frame_idx=$((count % ${#spinner_frames[@]}))
        printf "\r\033[K${CYAN}%s${RESET} %s " "${spinner_frames[$frame_idx]}" "$message"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Countdown timer animation
countdown_timer() {
    local seconds=${1:-5}
    local message="${2:-Starting in}"
    
    for ((i=seconds; i>=0; i--)); do
        printf "\r\033[K⏱️ $message ${YELLOW}%d${RESET} second%s " "$i" "$([ $i -eq 1 ] || echo 's')"
        sleep 1
    done
    printf "\r\033[K"
}

# Progress bar animation
progress_bar() {
    local duration=${1:-5}
    local message="${2:-Loading}"
    local width=30
    local count=0
    local total=$((duration * 10))
    
    while [ $count -lt $total ]; do
        local progress=$((count * width / total))
        local percent=$((count * 100 / total))
        
        # Create the bar
        local bar="["
        for ((i=0; i<width; i++)); do
            if [ $i -lt $progress ]; then
                bar+="${GREEN}=${RESET}"
            else
                bar+=" "
            fi
        done
        bar+="]"
        
        printf "\r\033[K🔄 $message $bar ${BLUE}%d%%${RESET}" "$percent"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Function for typewriter effect
typewriter() {
    local message="$1"
    local speed=${2:-0.05}
    local prefix=${3:-"📝 "}
    
    printf "$prefix"
    for (( i=0; i<${#message}; i++ )); do
        printf "%c" "${message:$i:1}"
        sleep $speed
    done
    printf "\n"
}

# Function for showing a progress bar
progress_bar() {
    local duration=${1:-5}
    local message="${2:-Processing}"
    local bar_length=30
    local count=0
    local total_steps=$((duration * 10))
    
    while [ $count -lt $total_steps ]; do
        local percent=$((100 * count / total_steps))
        local filled_length=$((bar_length * count / total_steps))
        local empty_length=$((bar_length - filled_length))
        
        # Create progress bar
        local bar=""
        for ((i=0; i<filled_length; i++)); do bar="${bar}█"; done
        for ((i=0; i<empty_length; i++)); do bar="${bar}░"; done
        
        # Print progress bar with percentage
        printf "\r\033[K⏳ $message [${GREEN}$bar${RESET}] ${percent}%%"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K✅ $message [${GREEN}$bar${RESET}] 100%%\n"
}

# Function for a bouncing ball animation
bouncing_ball() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local width=20
    local position=0
    local direction=1
    
    while [ $count -lt $((duration * 10)) ]; do
        local bar=""
        for ((i=0; i<width; i++)); do
            if [ $i -eq $position ]; then
                bar="${bar}${CYAN}⚾${RESET}"
            else
                bar="${bar} "
            fi
        done
        
        printf "\r\033[K🏀 $message [${bar}]"
        
        # Update position for bounce effect
        position=$((position + direction))
        if [ $position -eq $width ] || [ $position -eq 0 ]; then
            direction=$((direction * -1))
        fi
        
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Function for rotating spinner
show_spinner() {
    local pid=$1
    local delay=0.15
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'  # Braille pattern spinner (smoother than basic |/-)
    local message="${2:-Processing}"
    
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r\033[K${BLUE}🔄${RESET} $message ${CYAN}%c${RESET}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K"
}

# Function for a pulsing animation
pulse_animation() {
    local duration=${1:-3}
    local message="${2:-Processing}"
    local count=0
    local symbols=("⬤" "◆" "■" "●" "★")
    local colors=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$MAGENTA")
    
    while [ $count -lt $((duration * 10)) ]; do
        local symbol_idx=$((count % ${#symbols[@]}))
        local color_idx=$((count % ${#colors[@]}))
        printf "\r\033[K✨ $message ${colors[$color_idx]}%s${RESET}" "${symbols[$symbol_idx]}"
        sleep 0.1
        count=$((count + 1))
    done
    printf "\r\033[K"
}

# Set up debug trap to catch errors but continue execution
trap 'echo "DEBUG: Error at line $LINENO: Command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

# Ensure the script doesn't exit on errors
set +e

# Debug, echo all passed parameters
echo "Debug: Arguments passed: $@"

# Store all arguments for processing
ALL_ARGS=("$@")
TOPIC=""
GENRE=""
AUDIENCE=""
ARGS_PROCESSED=0

# First pass - handle all option flags
i=0
while [ $i -lt ${#ALL_ARGS[@]} ]; do
    case ${ALL_ARGS[$i]} in
        -m|--model)
            MODEL="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        -t|--temperature)
            TEMPERATURE="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --min-words)
            MIN_WORDS="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --max-words)
            MAX_WORDS="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --style)
            WRITING_STYLE="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --tone)
            TONE="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --delay)
            DELAY_BETWEEN_CHAPTERS="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --outline-only)
            OUTLINE_ONLY=true
            ALL_ARGS[$i]="__PROCESSED__"
            i=$((i+1))
            ;;
        --chapters-only)
            CHAPTERS_ONLY="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --no-plagiarism-check)
            ENABLE_PLAGIARISM_CHECK=false
            ALL_ARGS[$i]="__PROCESSED__"
            i=$((i+1))
            ;;
        --plagiarism-strict)
            PLAGIARISM_CHECK_STRICTNESS="high"
            ORIGINALITY_THRESHOLD=8
            ALL_ARGS[$i]="__PROCESSED__"
            i=$((i+1))
            ;;
        --plagiarism-threshold)
            ORIGINALITY_THRESHOLD="${ALL_ARGS[$((i+1))]}"
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        --no-auto-rewrite)
            AUTO_REWRITE_ON_FAIL=false
            ALL_ARGS[$i]="__PROCESSED__"
            i=$((i+1))
            ;;
        --preset)
            case ${ALL_ARGS[$((i+1))]} in
                creative)
                    TEMPERATURE=0.9
                    WRITING_STYLE="narrative"
                    TONE="conversational"
                    ;;
                technical)
                    TEMPERATURE=0.6
                    WRITING_STYLE="detailed"
                    TONE="professional"
                    ;;
                fiction)
                    TEMPERATURE=0.8
                    WRITING_STYLE="narrative"
                    TONE="engaging"
                    ;;
                business)
                    TEMPERATURE=0.7
                    WRITING_STYLE="detailed"
                    TONE="authoritative"
                    ;;
            esac
            ALL_ARGS[$i]="__PROCESSED__"
            ALL_ARGS[$((i+1))]="__PROCESSED__"
            i=$((i+2))
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*|--*)
            echo "Unknown option: ${ALL_ARGS[$i]}"
            exit 1
            ;;
        *)
            i=$((i+1))
            ;;
    esac
done

# Second pass - collect positional arguments
for arg in "${ALL_ARGS[@]}"; do
    if [ "$arg" != "__PROCESSED__" ]; then
        if [ -z "$TOPIC" ]; then
            TOPIC="$arg"
        elif [ -z "$GENRE" ]; then
            GENRE="$arg"
        elif [ -z "$AUDIENCE" ]; then
            AUDIENCE="$arg"
        fi
    fi
done

# Debugging output to verify OUTLINE_ONLY
echo "Debug: OUTLINE_ONLY is set to: $OUTLINE_ONLY"
# Validate API key
if [ -z "$API_KEY" ]; then
    echo "❌ Error: GEMINI_API_KEY environment variable not set"
    echo "Set it with: export GEMINI_API_KEY='your-api-key'"
    exit 1
fi

# Handle chapters-only mode
if [ -n "$CHAPTERS_ONLY" ]; then
    if [ ! -f "$CHAPTERS_ONLY" ]; then
        echo "❌ Error: Outline file '$CHAPTERS_ONLY' not found"
        exit 1
    fi
    OUTLINE_FILE="$CHAPTERS_ONLY"
    echo "📚 Generating chapters from existing outline: $OUTLINE_FILE"
else
    # Validate required arguments for full generation
    if [ -z "$TOPIC" ] || [ -z "$GENRE" ] || [ -z "$AUDIENCE" ]; then
        echo "❌ Error: Missing required arguments"
        show_help
        exit 1
    fi
fi
    
echo "🚀 Starting complete book generation workflow"
echo "📖 Topic: $TOPIC"
echo "📚 Genre: $GENRE"
echo "👥 Audience: $AUDIENCE"
echo ""

# API configuration
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Utility function to escape JSON strings properly
escape_json() {
    # Use jq to properly escape JSON strings
    echo -n "$1" | jq -Rs '.'
}

# Alternative escape function for when jq isn't available
escape_json_manual() {
    local input="$1"
    # Replace backslashes first, then quotes, then newlines
    input="${input//\\/\\\\}"  # Replace \ with \\
    input="${input//\"/\\\"}"  # Replace " with \"
    input="${input//$'\n'/\\n}"  # Replace newlines with \n
    input="${input//$'\r'/\\r}"  # Replace carriage returns with \r
    input="${input//$'\t'/\\t}"  # Replace tabs with \t
    echo "$input"
}

# Function to validate JSON payload
validate_json_payload() {
    if ! echo "$1" | jq -e '.' > /dev/null 2>&1; then
        echo "Debug: Invalid JSON payload:"
        echo "$1" | head -n 20  # Show first 20 lines for debugging
        return 1
    fi
    return 0
}

# Update make_api_request to use better JSON handling
# Function removed as it was duplicated later in the file

# Extract chapter information from outline
extract_chapters() {
    local outline_file="$1"
    local temp_file=$(mktemp)
    
    # Look for chapter patterns in the outline
    # This handles various outline formats
    grep -i -E "(chapter|ch\.)\s*[0-9]+.*:" "$outline_file" | \
    sed -E 's/^[^0-9]*([0-9]+)[^:]*:\s*(.*)$/\1|\2/' | \
    head -20 > "$temp_file"
    
    # If no chapters found with that pattern, try different formats
    if [ ! -s "$temp_file" ]; then
        grep -i -E "^#+ *(chapter|ch\.)" "$outline_file" | \
        sed -E 's/^#+\s*(chapter|ch\.?)\s*([0-9]+)[^:]*:?\s*(.*)$/\2|\3/' >> "$temp_file"
    fi
    
    # If still no chapters, try numbered list format
    if [ ! -s "$temp_file" ]; then
        grep -E "^[0-9]+\." "$outline_file" | \
        sed -E 's/^([0-9]+)\.\s*(.*)$/\1|\2/' | \
        head -15 >> "$temp_file"
    fi
    
    cat "$temp_file"
    rm "$temp_file"
}

# Generate outline if needed
if [ -z "$CHAPTERS_ONLY" ]; then
    echo "📋 Step 1: Generating book outline..."
    
    SYSTEM_PROMPT=$(cat << 'EOF'
You are an expert book author and publishing professional tasked with creating high-quality, commercially viable books for publication on KDP and other platforms. Your goal is to produce engaging, well-structured, and professionally written content that readers will find valuable and enjoyable.

Create detailed book outlines that will guide the generation of 30,000-word books with 12-15 chapters of 2,000-2,500 words each.

When creating outlines, always format chapter titles clearly as:
Chapter 1: [Title]
Chapter 2: [Title]
etc.

Include comprehensive chapter summaries that will guide detailed content generation. DO NOT include any markdown characters or formatting other than numbered lists.
EOF
)

echo "Debug: SYSTEM_PROMPT before user prompt:" > debug.log
echo "$SYSTEM_PROMPT" | head -n 10 >> debug.log  # Log first 10 lines for context

    USER_PROMPT="Create a detailed outline for a ${GENRE} book about '${TOPIC}' targeting ${AUDIENCE}.

REQUIRED FORMAT - Use this exact format for chapters:
Chapter 1: [Chapter Title]
Chapter 2: [Chapter Title]
[etc.]

Include:
- Compelling book title and subtitle
- 12-15 chapters with descriptive titles
- 2-3 sentence summary for each chapter explaining what will be covered
- Character profiles (fiction) or key concept definitions (non-fiction)
- 3-5 core themes to weave throughout the book
- Target reading level and tone guidance
- Suggested word count distribution

Make sure chapter titles are specific and promise clear value to readers. DO NOT include any markdown characters or formatting other than numbered lists."

    ESCAPED_SYSTEM=$(escape_json "$SYSTEM_PROMPT")
    ESCAPED_USER=$(escape_json "$USER_PROMPT")

    # Create JSON payload using jq for proper escaping
    JSON_PAYLOAD=$(jq -n \
        --arg system "$SYSTEM_PROMPT" \
        --arg user "$USER_PROMPT" \
        --arg maxtokens "$MAX_TOKENS" \
        '{
            "contents": [{
                "parts": [{
                    "text": ("SYSTEM: " + $system + "\n\nUSER: " + $user)
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": $maxtokens
            }
        }')
    echo "Debug: JSON_PAYLOAD for outline generation:" > debug.log
    echo "$USER_PROMPT" >> debug.log

    typewriter "Preparing to generate your book outline..." 0.03 "🧠 "
    progress_bar 3 "Generating outline structure"
    RESPONSE=$(make_api_request "$JSON_PAYLOAD")

    # Error handling
    if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        echo "${RED}❌ API Error:${RESET}"
        echo "$RESPONSE" | jq '.error'
        return 1
    fi

    if [ $? -ne 0 ]; then
        echo "${RED}❌ API request failed. Exiting.${RESET}"
        exit 1
    fi

    # Create output directory and save outline
    OUTPUT_DIR="./book_outputs"
    mkdir -p "$OUTPUT_DIR"
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTLINE_FILE="${OUTPUT_DIR}/book_outline_${TIMESTAMP}.md"

    echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$OUTLINE_FILE"
    echo "📃 Outline generated and saved to: $OUTLINE_FILE"

    # Review and Proofreading Step
    sleep 2
    REVIEW_PROMPT="Review and proofread the following book outline for grammar, clarity, and structure. Suggest any necessary corrections or improvements."

    # Ensure OUTLINE_CONTENT is populated with the correct outline file content
    if [ -f "$OUTLINE_FILE" ]; then
        OUTLINE_CONTENT=$(cat "$OUTLINE_FILE")
    else
        echo "❌ Error: Outline file not found at $OUTLINE_FILE"
        exit 1
    fi

    # Debugging: Confirm OUTLINE_CONTENT before review step
    echo "Debug: OUTLINE_CONTENT before review step:" > debug.log
    echo "$OUTLINE_CONTENT" | head -n 10 >> debug.log  # Log first 10 lines for context

    REVIEW_JSON_PAYLOAD=$(jq -n \
        --arg system "$SYSTEM_PROMPT" \
        --arg review "$REVIEW_PROMPT" \
        --arg outline "$OUTLINE_CONTENT" \
        --arg maxtokens "$MAX_TOKENS" \
        '{
            "contents": [{
                "parts": [{
                    "text": ("SYSTEM: " + $system + "\n\nUSER: " + $review + "\n\nOUTLINE:\n" + $outline)
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": $maxtokens
            }
        }')

    loading_dots 3 "🔄 Making API request for review and proofreading"
    REVIEW_RESPONSE=$(make_api_request "$REVIEW_JSON_PAYLOAD")

    if [ $? -ne 0 ]; then
        echo "❌ API request for review failed. Exiting."
        exit 1
    fi

    REVIEWED_OUTLINE_FILE="${OUTPUT_DIR}/book_outline_reviewed_${TIMESTAMP}.md"
    echo "$REVIEW_RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$REVIEWED_OUTLINE_FILE"
    echo "✅ Reviewed outline saved to: $REVIEWED_OUTLINE_FILE"

    # Second/Final Draft Step
    sleep 2
    FINAL_DRAFT_PROMPT="Improve the following book outline in any way possible. Focus on enhancing its quality, structure, and content. Ensure it is engaging and well-organized."

    FINAL_DRAFT_JSON_PAYLOAD=$(jq -n \
        --arg system "$SYSTEM_PROMPT" \
        --arg prompt "$FINAL_DRAFT_PROMPT" \
        --arg outline "$(cat "$REVIEWED_OUTLINE_FILE")" \
        --arg maxtokens "$MAX_TOKENS" \
        '{
            "contents": [{
                "parts": [{
                    "text": ("SYSTEM: " + $system + "\n\nUSER: " + $prompt + "\n\nOUTLINE:\n" + $outline)
                }]
            }],
            "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": $maxtokens
            }
        }')
    loading_dots 3 "🔄 Making API request for second/final draft"
    FINAL_DRAFT_RESPONSE=$(make_api_request "$FINAL_DRAFT_JSON_PAYLOAD")

    if [ $? -ne 0 ]; then
        echo "❌ API request for final draft failed. Exiting."
        exit 1
    fi

    FINAL_DRAFT_FILE="${OUTPUT_DIR}/book_outline_final_${TIMESTAMP}.md"
    echo "$FINAL_DRAFT_RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$FINAL_DRAFT_FILE"
    echo "✅ Final draft saved to: $FINAL_DRAFT_FILE"
    
    # Check if outline only mode is enabled
    if [ "$OUTLINE_ONLY" = true ]; then
        echo "📄 Outline generation complete. Exiting as requested."
        exit 0
    fi
fi

# Populate OUTLINE_CONTENT for --chapters-only mode
if [ -n "$CHAPTERS_ONLY" ]; then
    if [ -f "$CHAPTERS_ONLY" ]; then
        OUTLINE_CONTENT=$(cat "$CHAPTERS_ONLY")
    else
        echo "❌ Error: Outline file '$CHAPTERS_ONLY' not found"
        exit 1
    fi
fi

# Debugging: Confirm OUTLINE_CONTENT in --chapters-only mode
echo "Debug: OUTLINE_CONTENT in --chapters-only mode:" >> debug.log
echo "$OUTLINE_CONTENT" | head -n 10 >> debug.log  # Log first 10 lines for context

# Debugging: Add trace for final draft step
echo "Debug: Starting final draft step with OUTLINE_CONTENT:"
echo "$OUTLINE_CONTENT" | head -n 10  # Show first 10 lines for context

# Debugging: Add trace for chapter generation
CHAPTERS_INFO=$(extract_chapters "$OUTLINE_FILE")
if [ -z "$CHAPTERS_INFO" ]; then
    echo "❌ Error: Could not extract chapter information from outline"
    echo "Please check that your outline contains chapters in format:"
    echo "Chapter 1: Title"
    echo "Chapter 2: Title"
    exit 1
fi

# Debugging: Add trace for API request failures
make_api_request() {
    local payload="$1"
    local function_caller=${FUNCNAME[1]}
    local response
    
    echo "DEBUG: make_api_request called from $function_caller" >&2
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$API_URL")

    echo "Debug: Raw API response:" >> debug.log
    echo "$response" >> debug.log

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "❌ API Error:"
        echo "$response" | jq '.error'
        echo "DEBUG: make_api_request error detected, returning 1" >&2
        return 1
    fi
    
    echo "DEBUG: make_api_request returning successfully" >&2
    echo "$response"
}

# Extract chapters from outline
echo ""
echo "📑 Step 2: Parsing chapters from outline..."

CHAPTERS_INFO=$(extract_chapters "$OUTLINE_FILE")

if [ -z "$CHAPTERS_INFO" ]; then
    echo "❌ Error: Could not extract chapter information from outline"
    echo "Please check that your outline contains chapters in format:"
    echo "Chapter 1: Title"
    echo "Chapter 2: Title"
    exit 1
fi

CHAPTER_COUNT=$(echo "$CHAPTERS_INFO" | wc -l)
echo "📚 Found $CHAPTER_COUNT chapters to generate"

# Display chapter list
echo ""
echo "📋 Chapters to generate:"
IFS=$'\n'
DISPLAY_LINES=($(echo "$CHAPTERS_INFO"))
unset IFS

for DISPLAY_LINE in "${DISPLAY_LINES[@]}"; do
    IFS='|' read -r num title <<< "$DISPLAY_LINE"
    title=$(echo "$title" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*[*-]\?[[:space:]]*$//;s/[[:space:]]*$//')
    echo "   Chapter $num: $title"
done

# Generate chapters
echo ""
echo "✍️  Step 3: Generating chapters..."
echo "⏱️  Delay between chapters: ${DELAY_BETWEEN_CHAPTERS}s"
echo ""

BOOK_DIR=$(dirname "$OUTLINE_FILE")
OUTLINE_CONTENT=$(cat "$OUTLINE_FILE")
TOTAL_WORDS=0

# System prompt for chapter generation
CHAPTER_SYSTEM_PROMPT="You are an expert book author creating comprehensive, high-quality chapters for publication. Focus on creating detailed, engaging content that provides genuine value to readers."

# Store chapters in an array to avoid pipe issues
echo "DEBUG: Preparing to process chapters" >&2
IFS=$'\n'
CHAPTER_LINES=($(echo "$CHAPTERS_INFO"))
unset IFS

# Verify we have chapters to process
if [ ${#CHAPTER_LINES[@]} -eq 0 ]; then
    echo "ERROR: No chapters found in outline!" >&2
    exit 1
fi

echo "DEBUG: Found ${#CHAPTER_LINES[@]} chapters to process" >&2

# Make sure we trap errors without exiting script
set +e

for CHAPTER_LINE in "${CHAPTER_LINES[@]}"; do
    # Parse chapter number and title
    IFS='|' read -r CHAPTER_NUM CHAPTER_TITLE <<< "$CHAPTER_LINE"
    echo "DEBUG: Starting processing for chapter $CHAPTER_NUM" >&2
    
    # Clean up title (remove quotes, trim whitespace, remove * and other markdown characters, trailing attached to the last word in a line)
    CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/\*//g;s/[[:space:]]*[*-]\?[[:space:]]*$//;s/[[:space:]]*$//')

    echo "📝 Generating Chapter $CHAPTER_NUM: $CHAPTER_TITLE"
    
    # Collect existing chapters for context
    EXISTING_CHAPTERS=""
    for i in $(seq 1 $((CHAPTER_NUM - 1))); do
        echo "Debug: Collecting existing chapter $i for context"
        CHAPTER_FILE="${BOOK_DIR}/chapter_${i}.md"
        if [ -f "$CHAPTER_FILE" ]; then
            CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
            EXISTING_CHAPTERS="${EXISTING_CHAPTERS}\n\n=== CHAPTER $i ===\n${CHAPTER_CONTENT}"
        fi
    done

    # Style and tone instructions
    get_style_instructions() {
        echo "Debug: Getting style instructions for chapter $CHAPTER_NUM"
        case $WRITING_STYLE in
            detailed)
                echo "Write comprehensive, in-depth content with thorough explanations, multiple examples, and detailed analysis."
                ;;
            narrative)
                echo "Use storytelling elements, anecdotes, and narrative flow. Include scenarios and stories to illustrate points."
                ;;
            academic)
                echo "Use structured, formal writing with systematic analysis and well-organized arguments."
                ;;
        esac
    }

    get_tone_instructions() {
        echo "Debug: Getting tone instructions for chapter $CHAPTER_NUM"
        case $TONE in
            professional)
                echo "Maintain a professional, authoritative voice suitable for business or educational contexts."
                ;;
            casual)
                echo "Use conversational, approachable language that feels friendly and accessible."
                ;;
            authoritative)
                echo "Write with confidence and expertise as a trusted authority on the subject."
                ;;
            conversational)
                echo "Use a warm, engaging tone that draws readers in and makes topics accessible."
                ;;
            engaging)
                echo "Write with energy and enthusiasm to captivate and maintain reader interest."
                ;;
        esac
    }

    echo "Debug: Getting style and tone instructions for chapter $CHAPTER_NUM"
    STYLE_INSTRUCTIONS=$(get_style_instructions)
    TONE_INSTRUCTIONS=$(get_tone_instructions)

    # Clean outline content to remove markdown asterisks
OUTLINE_CONTENT=$(echo "$OUTLINE_CONTENT" | sed 's/\*\*//g')

CHAPTER_USER_PROMPT="Write Chapter ${CHAPTER_NUM}: '${CHAPTER_TITLE}' based on the outline and existing chapters.

CRITICAL LENGTH REQUIREMENT:
- Write EXACTLY ${MIN_WORDS}-${MAX_WORDS} words (this is mandatory)
- Do NOT write less than ${MIN_WORDS} words under any circumstances
- Expand ideas fully to reach the required length naturally

WRITING STYLE: ${WRITING_STYLE}
${STYLE_INSTRUCTIONS}

TONE: ${TONE}
${TONE_INSTRUCTIONS}

STRUCTURE REQUIREMENTS:
- Start with a compelling opening hook
- Use 5-8 clear subheadings to organize content
- Include 2-3 detailed examples or case studies per major section
- Provide step-by-step guidance where applicable
- End with actionable takeaways and transition to next chapter

CONTENT EXPANSION TECHNIQUES:
- Elaborate on every concept with detailed explanations
- Include 'why' and 'how' for every major point
- Add real-world applications and scenarios
- Address common questions or objections
- Provide multiple examples for complex concepts
- Break down processes into detailed steps
- Use analogies and metaphors to clarify concepts

BOOK OUTLINE:
${OUTLINE_CONTENT}

EXISTING CHAPTERS:
${EXISTING_CHAPTERS}

Write Chapter ${CHAPTER_NUM}: ${CHAPTER_TITLE}
TARGET: ${MAX_WORDS} words, MINIMUM: ${MIN_WORDS} words"

    # Prepare JSON payload using jq for proper escaping
    CHAPTER_JSON_PAYLOAD=$(jq -n \
        --arg system "$CHAPTER_SYSTEM_PROMPT" \
        --arg user "$CHAPTER_USER_PROMPT" \
        --argjson temp "$TEMPERATURE" \
        --argjson topk "$TOP_K" \
        --argjson topp "$TOP_P" \
        --argjson maxtokens "$MAX_TOKENS" \
        '{
            "contents": [{
                "parts": [{
                    "text": ("SYSTEM: " + $system + "\n\nUSER: " + $user)
                }]
            }],
            "generationConfig": {
                "temperature": $temp,
                "topK": $topk,
                "topP": $topp,
                "maxOutputTokens": $maxtokens
            }
        }')
    # Debugging: Log JSON payload before sending
    echo "Debug: JSON payload for Chapter $CHAPTER_NUM:" >> debug.log
    echo "$CHAPTER_JSON_PAYLOAD" >> debug.log

    # Validate JSON payload
    if ! echo "$CHAPTER_JSON_PAYLOAD" | jq -e '.' > /dev/null 2>&1; then
        echo "❌ Error: Invalid JSON payload for Chapter $CHAPTER_NUM"
        echo "Debug: Invalid JSON payload:" >> debug.log
        echo "$CHAPTER_JSON_PAYLOAD" >> debug.log
        continue
    fi
    
    # Generate chapter
    CHAPTER_RESPONSE=$(make_api_request "$CHAPTER_JSON_PAYLOAD")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to generate Chapter $CHAPTER_NUM"
        echo "Debug: API response for Chapter $CHAPTER_NUM:" >> debug.log
        echo "$CHAPTER_RESPONSE" >> debug.log
        continue
    fi

    # Validate API response
    if ! echo "$CHAPTER_RESPONSE" | jq -e '.' > /dev/null 2>&1; then
        echo "❌ Error: Invalid JSON response for Chapter $CHAPTER_NUM"
        echo "Debug: Raw API response for Chapter $CHAPTER_NUM:" >> debug.log
        echo "$CHAPTER_RESPONSE" >> debug.log
        continue
    fi

    # Extract chapter content
    CHAPTER_CONTENT=$(echo "$CHAPTER_RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
    if [ -z "$CHAPTER_CONTENT" ] || [ "$CHAPTER_CONTENT" = "null" ]; then
        echo "❌ Error: Empty content for Chapter $CHAPTER_NUM"
        echo "Debug: API response for Chapter $CHAPTER_NUM:" >> debug.log
        echo "$CHAPTER_RESPONSE" >> debug.log
        continue
    fi

    # Save chapter
    CHAPTER_FILE="${BOOK_DIR}/chapter_${CHAPTER_NUM}.md"
    echo "$CHAPTER_CONTENT" > "$CHAPTER_FILE"
    echo "✅ Chapter $CHAPTER_NUM saved to: $(basename "$CHAPTER_FILE")"

    # NEW: Quality check with LanguageTool
    echo "🔍 Running quality check on Chapter $CHAPTER_NUM..."
    if [ -f "./tools/languagetool_check.sh" ]; then
        ./tools/languagetool_check.sh "$CHAPTER_FILE" --output-dir "${BOOK_DIR}/quality_reports"
        
        # Check if quality is acceptable
        QUALITY_REPORT="${BOOK_DIR}/quality_reports/chapter_${CHAPTER_NUM}_quality_report.md"
        if [ -f "$QUALITY_REPORT" ]; then
            QUALITY_SCORE=$(grep "Quality Score" "$QUALITY_REPORT" | grep -o '[0-9]*' | head -1)
            if [ "$QUALITY_SCORE" -lt 70 ]; then
                echo "⚠️  Chapter $CHAPTER_NUM quality score is low ($QUALITY_SCORE%). Consider regenerating."
                read -p "🔄 Regenerate this chapter? (y/N): " regenerate
                if [[ $regenerate =~ ^[Yy]$ ]]; then
                    echo "🔄 Regenerating Chapter $CHAPTER_NUM with improved prompt..."
                    # Add quality feedback to prompt and regenerate
                    QUALITY_ISSUES=$(grep -A 10 "## Issue Breakdown" "$QUALITY_REPORT" | tail -n +2)
                    IMPROVED_PROMPT="${CHAPTER_USER_PROMPT}

QUALITY IMPROVEMENT NEEDED:
Previous version had quality issues: $QUALITY_ISSUES
Please focus on:
- Clear, grammatically correct sentences
- Proper spelling and punctuation  
- Varied sentence structure
- Professional writing style"
                
                ESCAPED_IMPROVED_PROMPT=$(escape_json "$IMPROVED_PROMPT")
                IMPROVED_JSON_PAYLOAD=$(jq -n \
                    --arg system "$CHAPTER_SYSTEM_PROMPT" \
                    --arg user "$IMPROVED_PROMPT" \
                    --argjson temp "$(echo "$TEMPERATURE - 0.1" | bc)" \
                    --argjson topk "$TOP_K" \
                    --argjson topp "$TOP_P" \
                    --argjson maxtokens "$MAX_TOKENS" \
                    '{
                        "contents": [{
                            "parts": [{
                                "text": ("SYSTEM: " + $system + "\n\nUSER: " + $user)
                            }]
                        }],
                        "generationConfig": {
                            "temperature": $temp,
                            "topK": $topk,
                            "topP": $topp,
                            "maxOutputTokens": $maxtokens
                        }
                    }')
                    CHAPTER_RESPONSE=$(make_api_request "$IMPROVED_JSON_PAYLOAD")
                    echo "$CHAPTER_RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$CHAPTER_FILE"
                    ./tools/languagetool_check.sh "$CHAPTER_FILE" --output-dir "${BOOK_DIR}/quality_reports"
                fi
            fi
        fi
    else
        echo "⚠️  LanguageTool checker not found. Skipping quality check."
    fi

    echo ""
    echo "🔍 Running plagiarism and copyright check for Chapter $CHAPTER_NUM..."
    echo "DEBUG: Starting plagiarism check process for chapter $CHAPTER_NUM" >&2
    
    # Run plagiarism checks and auto-rewrite until passing
    MAX_REWRITE_ATTEMPTS=5
    REWRITE_ATTEMPT=0
    PLAGIARISM_PASSED=false
    WORD_COUNT_PASSED=false
    
    # First, check the initial word count
    CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE")
    if [ $CURRENT_WORD_COUNT -ge $MIN_WORDS ]; then
        WORD_COUNT_PASSED=true
    else
        echo "⚠️ Initial word count ($CURRENT_WORD_COUNT) below target ($MIN_WORDS) - will address during rewrite"
    fi
    
    while [ "$(( $PLAGIARISM_PASSED == false || $WORD_COUNT_PASSED == false ))" == "1" ] && [ $REWRITE_ATTEMPT -lt $MAX_REWRITE_ATTEMPTS ]; do
        # Perform plagiarism check - save output to avoid subshell issues
        echo "DEBUG: Running plagiarism check, attempt #$((REWRITE_ATTEMPT+1))" >&2
        multi_check_plagiarism "$CHAPTER_FILE" > /tmp/plagiarism_output_$CHAPTER_NUM.log 2>&1
        PLAGIARISM_RESULT=$?
        
        # Get originality score to make smarter decisions
        ORIGINALITY_SCORE=$(grep "ORIGINALITY_SCORE:" "${BOOK_DIR}/chapter_${CHAPTER_NUM}_plagiarism_report.md" 2>/dev/null | sed 's/ORIGINALITY_SCORE: //')
        
        # Count words in the current chapter
        CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE")
        if [ $CURRENT_WORD_COUNT -ge $MIN_WORDS ]; then
            WORD_COUNT_PASSED=true
        else
            echo "⚠️ Word count ($CURRENT_WORD_COUNT) below target ($MIN_WORDS)"
            WORD_COUNT_PASSED=false
        fi
        
        echo "DEBUG: multi_check_plagiarism returned with code $PLAGIARISM_RESULT for chapter $CHAPTER_NUM (Score: $ORIGINALITY_SCORE, Words: $CURRENT_WORD_COUNT)" >&2
        
        # Accept chapters with a good score after 2-3 attempts
        if [ $PLAGIARISM_RESULT -eq 1 ] && [ $REWRITE_ATTEMPT -ge 2 ] && [ "$ORIGINALITY_SCORE" -ge 7 ]; then
            echo "✅ Chapter $CHAPTER_NUM has acceptable originality score ($ORIGINALITY_SCORE/10) after $REWRITE_ATTEMPT attempts - proceeding"
            PLAGIARISM_PASSED=true
        elif [ $PLAGIARISM_RESULT -eq 0 ]; then
            echo "✅ Chapter $CHAPTER_NUM passed originality check"
            PLAGIARISM_PASSED=true
        fi
        
        # If both checks pass, we're done
        if [ "$PLAGIARISM_PASSED" = true ] && [ "$WORD_COUNT_PASSED" = true ]; then
            echo "✅ Chapter meets all requirements (Originality: $ORIGINALITY_SCORE/10, Words: $CURRENT_WORD_COUNT)"
            break
        fi
        
        # Determine if we need to rewrite
        NEEDS_REWRITE=false
        REWRITE_REASON=""
        
        if [ "$PLAGIARISM_PASSED" = false ]; then
            NEEDS_REWRITE=true
            if [ $PLAGIARISM_RESULT -eq 1 ]; then
                REWRITE_REASON="originality concerns (medium risk)"
            else
                REWRITE_REASON="originality concerns (high risk)"
            fi
        fi
        
        if [ "$WORD_COUNT_PASSED" = false ]; then
            NEEDS_REWRITE=true
            if [ -z "$REWRITE_REASON" ]; then
                REWRITE_REASON="insufficient word count ($CURRENT_WORD_COUNT/$MIN_WORDS)"
            else
                REWRITE_REASON="$REWRITE_REASON and insufficient word count ($CURRENT_WORD_COUNT/$MIN_WORDS)"
            fi
        fi
        
        # Perform rewrite if needed
        if [ "$NEEDS_REWRITE" = true ]; then
            # Both medium/high risk and low word count trigger rewrite
            PLAGIARISM_REPORT="${BOOK_DIR}/chapter_${CHAPTER_NUM}_plagiarism_report.md"
            REWRITE_ATTEMPT=$((REWRITE_ATTEMPT+1))
            echo "🔄 Auto-rewriting chapter to address $REWRITE_REASON (attempt ${REWRITE_ATTEMPT}/$MAX_REWRITE_ATTEMPTS)..."
            
            # Pass the current attempt number and word count issue flag to the rewrite function
            rewrite_chapter_for_originality "$CHAPTER_FILE" "$PLAGIARISM_REPORT" "${REWRITE_ATTEMPT}" "$WORD_COUNT_PASSED"
        fi
        
        # If we've reached max attempts, proceed anyway
        if [ $REWRITE_ATTEMPT -ge $MAX_REWRITE_ATTEMPTS ]; then
            echo "⚠️ Reached maximum rewrite attempts ($MAX_REWRITE_ATTEMPTS) - proceeding with current version"
            PLAGIARISM_PASSED=true
            WORD_COUNT_PASSED=true  # Force proceed
        fi
    done
    
    # Final check result for reporting
    multi_check_plagiarism "$CHAPTER_FILE" > /dev/null 2>&1
    FINAL_PLAGIARISM_RESULT=$?
    
    echo ""
    echo "📊 Chapter Quality Summary:"
    if [ -f "${BOOK_DIR}/chapter_${CHAPTER_NUM}_plagiarism_report.md" ]; then
        echo "   📋 Report: chapter_${CHAPTER_NUM}_plagiarism_report.md"
        
        # Show quick summary
        ORIGINALITY_SCORE=$(grep "ORIGINALITY_SCORE:" "${BOOK_DIR}/chapter_${CHAPTER_NUM}_plagiarism_report.md" | sed 's/ORIGINALITY_SCORE: //')
        if [ -n "$ORIGINALITY_SCORE" ]; then
            echo "   📈 Final Originality Score: $ORIGINALITY_SCORE/10"
        fi
        
        # Get final word count
        FINAL_WORD_COUNT=$(wc -w < "$CHAPTER_FILE")
        echo "   📝 Final Word Count: $FINAL_WORD_COUNT words"
        
        if [ $FINAL_WORD_COUNT -lt $MIN_WORDS ]; then
            echo "   ⚠️  Word count below target ($MIN_WORDS)"
        else
            echo "   ✅ Word count meets or exceeds target"
        fi
        
        # Show rewrite attempt summary if applicable
        if [ $REWRITE_ATTEMPT -gt 0 ]; then
            echo "   🔄 Rewrites performed: $REWRITE_ATTEMPT"
            case $FINAL_PLAGIARISM_RESULT in
                0) echo "   ✅ Final originality: Passed" ;;
                1) echo "   ⚠️  Final originality: Medium risk (acceptable)" ;;
                2) echo "   ⚠️  Final originality: Still has concerns (max attempts reached)" ;;
            esac
        fi
    fi
    
    # Calculate statistics
    WORD_COUNT=$(wc -w < "$CHAPTER_FILE")
    TOTAL_WORDS=$((TOTAL_WORDS + WORD_COUNT))
    
    echo "✅ Chapter $CHAPTER_NUM complete - $WORD_COUNT words"
    
    # Rate limiting delay (except for last chapter)
    # Check if we have more chapters and this isn't the last one
    if [ ${#CHAPTER_LINES[@]} -gt 0 ] && [ -n "${CHAPTER_LINES[-1]}" ] && [ "$CHAPTER_NUM" != "$(echo "${CHAPTER_LINES[-1]}" | cut -d'|' -f1 2>/dev/null || echo "")" ]; then
        echo "⏳ Waiting ${DELAY_BETWEEN_CHAPTERS}s before next chapter..."
        sleep $DELAY_BETWEEN_CHAPTERS
    fi
done

# Final statistics and compilation
echo ""
echo "🎉 Book generation complete!"
echo ""
echo "📊 Final Statistics:"
echo "   Total chapters: $CHAPTER_COUNT"
echo "   Estimated total words: $TOTAL_WORDS"
echo "   Target was: 30,000 words"
echo "   Output directory: $BOOK_DIR"

# Final Plagiarism Check Summary
echo ""
echo "� Final Plagiarism Check Summary:"

if [ "$ENABLE_PLAGIARISM_CHECK" = true ]; then
    TOTAL_REPORTS=$(ls "${BOOK_DIR}"/chapter_*_plagiarism_report.md 2>/dev/null | wc -l)
    TOTAL_REWRITES=$(ls "${BOOK_DIR}"/chapter_*.md.backup_* 2>/dev/null | wc -l)
    
    echo "   📊 Total chapters checked: $TOTAL_REPORTS"
    echo "   🔄 Chapters rewritten: $TOTAL_REWRITES"
    
    # Calculate average originality score
    if [ $TOTAL_REPORTS -gt 0 ]; then
        AVG_ORIGINALITY=0
        SCORE_COUNT=0
        
        for report in "${BOOK_DIR}"/chapter_*_plagiarism_report.md; do
            if [ -f "$report" ]; then
                SCORE=$(grep "ORIGINALITY_SCORE:" "$report" | sed 's/ORIGINALITY_SCORE: //' | grep -o '[0-9]*')
                if [ -n "$SCORE" ] && [ "$SCORE" -gt 0 ]; then
                    AVG_ORIGINALITY=$((AVG_ORIGINALITY + SCORE))
                    SCORE_COUNT=$((SCORE_COUNT + 1))
                fi
            fi
        done
        
        if [ $SCORE_COUNT -gt 0 ]; then
            AVG_ORIGINALITY=$((AVG_ORIGINALITY / SCORE_COUNT))
            echo "   📈 Average originality score: $AVG_ORIGINALITY/10"
            
            if [ $AVG_ORIGINALITY -ge 8 ]; then
                echo "   ✅ Excellent originality achieved"
            elif [ $AVG_ORIGINALITY -ge 6 ]; then
                echo "   ✅ Good originality achieved"
            else
                echo "   ⚠️  Originality could be improved"
            fi
        fi
    fi
    
    echo "   📁 All plagiarism reports saved in: $BOOK_DIR"
else
    echo "   ⚠️  Plagiarism checking was disabled"
fi

echo ""
echo "�📁 Generated files:"
ls -la "$BOOK_DIR"
echo ""
echo "🚀 Next steps:"
echo "   1. Review individual chapters in $BOOK_DIR"
echo "   2. Review plagiarism reports for any flagged content"
echo "   3. Run ./compile_book.sh to create final manuscript"
echo "   4. Edit and format for publishing"