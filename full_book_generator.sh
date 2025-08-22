#!/bin/bash

# Complete Book Generation Workflow with Multi-Provider AI Support
# Usage: ./generate_full_book.sh "Book Topic" "Genre" "Target Audience" [OPTIONS]

set -e

# Start timer for job duration tracking
START_TIME=$(date +%s)
echo "⏱️ Job started at $(date '+%Y-%m-%d %H:%M:%S')"

# Source multi-provider system
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/multi_provider_ai_simple.sh" ]; then
    source "$SCRIPT_DIR/multi_provider_ai_simple.sh"
    echo "✅ Multi-provider AI system loaded"
    MULTI_PROVIDER_ENABLED=true
else
    echo "⚠️  Multi-provider system not found, using single provider mode"
    MULTI_PROVIDER_ENABLED=false
fi

# Function to select the optimal model for specific tasks
select_task_model() {
    local task_type="$1"
    local default_model="$2"
    local length_preference="${3:-medium}"  # small, medium, large
    
    case "$task_type" in
        "chapter_generation")
            # Use larger models for initial chapter generation
            if [ "$length_preference" = "large" ]; then
                echo "llama3.1:8b"  # Largest model for highest quality chapters
            elif [ "$length_preference" = "medium" ]; then
                echo "phi4-mini:3.8b"  # Better quality with comparable size to llama3.2:3b
            else
                echo "llama3.2:1b"  # Fast generation, decent quality
            fi
            ;;
        "continuation")
            # Models optimized for continuing existing text - prioritizing speed
            if [ "$length_preference" = "large" ]; then
                echo "llama3.2:1b"  # Good balance of speed and quality
            else
                echo "phi2:2.7b"  # Fastest model for continuations
            fi
            ;;
        "plagiarism_check")
            # Analytical models good at comparison/detection
            echo "gemma3:4b"  # Strong analytical capabilities
            ;;
        "quality_check")
            # Focused on grammar and style
            echo "phi3:3.8b"  # Better grammar and style understanding
            ;;
        "rewrite")
            # Creative models for rewriting content
            if [ "$length_preference" = "large" ]; then
                echo "phi3:3.8b"  # Creative rewriting with strong coherence
            else
                echo "granite3-moe:3b"  # Good balance for rewriting
            fi
            ;;
        "section_rewrite")
            # Models optimized for section-level rewriting
            echo "phi3:3.8b"  # Excellent for creative rewriting
            ;;
        "summary")
            # Models good at condensing information
            echo "qwen3:1.7b"  # Efficient summarization
            ;;
        "outline")
            # Strong planning and organizing models
            echo "gemma2:2b"  # Good for structured content
            ;;
        "analytical")
            # Models good at analytical reasoning
            echo "phi4-mini-reasoning:3.8b"  # Strong reasoning capabilities
            ;;
        "creative")
            # Models good at creative writing
            echo "granite3.3:2b"  # Good creative capabilities with fast inference
            ;;
        *)
            # Default to the provided model
            echo "$default_model"
            ;;
    esac
}

# Default configuration
API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
TEMPERATURE=0.95
TOP_K=40
TOP_P=0.9
MAX_TOKENS=8192
MAX_RETRIES=1
MIN_WORDS=2000
MAX_WORDS=2500
WRITING_STYLE="detailed"
TONE="professional"
DELAY_BETWEEN_CHAPTERS=1  # Seconds to avoid rate limits
OUTLINE_ONLY=false
CHAPTERS_ONLY=""

# Plagiarism checking configuration
ENABLE_PLAGIARISM_CHECK=true
PLAGIARISM_CHECK_STRICTNESS="low"  # low, medium, high
AUTO_REWRITE_ON_FAIL=true
ORIGINALITY_THRESHOLD=4  # Minimum score out of 10
PLAGIARISM_RECHECK_LIMIT=1  # Maximum retries for rewritten content

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

API RATE LIMITING:
    --reset-api-tracking        Reset API call counters to zero
    
    Rate limits: 15 requests per minute, 1,500 requests per day
EOF
}

# Function to check for plagiarism and copyright issues using Gemini LLM
check_plagiarism_and_copyright() {
    local chapter_file="$1"
    local chapter_content=$(cat "$chapter_file")
    local chapter_num=$(basename "$chapter_file" .md | sed 's/chapter_//')
    
    echo "🔍 Checking Chapter $chapter_num for plagiarism and copyright issues..."
    echo "DEBUG: Starting plagiarism check function for chapter $chapter_num" >> debug.log

    local check_system_prompt="You are an expert copyright and plagiarism detection system."
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

    # Make API request using smart multi-provider system
    local response=""
    pulse_animation
    response=$(smart_api_call "$check_prompt" "$check_system_prompt" "plagiarism_check" "$TEMPERATURE" "$MAX_TOKENS" "$MAX_RETRIES" "gemma3:1b")
    local api_result=$?
    
    if [ $api_result -ne 0 ] || [ -z "$response" ]; then
        echo "❌ Plagiarism check failed for Chapter $chapter_num"
        return 1
    fi

    # Extract text content with error handling
    local check_result=""
    if echo "$response" | jq -e '.candidates[0].content.parts[0].text' > /dev/null 2>&1; then
        check_result=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text')
    else
        echo "❌ Failed to extract content from API response"
        return 1
    fi
    
    # Make sure we have valid content
    if [ -z "$check_result" ] || [ "$check_result" = "null" ]; then
        echo "❌ Empty plagiarism check result for Chapter $chapter_num"
        return 1
    fi
    
    # Save the check result
    local check_report_file="${BOOK_DIR}/chapter_${chapter_num}_plagiarism_report.md"
    echo "$check_result" > "$check_report_file"
    
    # Parse the results with better error handling
    # First check if jq is available to parse this more reliably
    if command -v jq &> /dev/null && echo "$check_result" | jq -e '.' > /dev/null 2>&1; then
        # Try to extract data using jq if response happens to be JSON format
        local originality_score=$(echo "$check_result" | jq -r '.originality_score // .ORIGINALITY_SCORE // empty' 2>/dev/null)
        local plagiarism_risk=$(echo "$check_result" | jq -r '.plagiarism_risk // .PLAGIARISM_RISK // empty' 2>/dev/null)
        local copyright_risk=$(echo "$check_result" | jq -r '.copyright_risk // .COPYRIGHT_RISK // empty' 2>/dev/null)
        local issues_found=$(echo "$check_result" | jq -r '.issues_found // .ISSUES_FOUND // empty' 2>/dev/null)
    fi
    
    # Fallback to grep extraction if jq didn't work or values are empty
    if [ -z "$originality_score" ]; then
        originality_score=$(echo "$check_result" | grep -i "ORIGINALITY_SCORE:" | sed 's/ORIGINALITY_SCORE: //' | grep -o '[0-9]*' | head -1)
    fi
    if [ -z "$plagiarism_risk" ]; then
        plagiarism_risk=$(echo "$check_result" | grep -i "PLAGIARISM_RISK:" | sed 's/PLAGIARISM_RISK: //')
    fi
    if [ -z "$copyright_risk" ]; then
        copyright_risk=$(echo "$check_result" | grep -i "COPYRIGHT_RISK:" | sed 's/COPYRIGHT_RISK: //')
    fi
    if [ -z "$issues_found" ]; then
        issues_found=$(echo "$check_result" | grep -i "ISSUES_FOUND:" | sed 's/ISSUES_FOUND: //')
    fi
    
    # Default values if parsing fails
    if [ -z "$originality_score" ]; then originality_score=5; fi
    if [ -z "$plagiarism_risk" ]; then plagiarism_risk="MEDIUM"; fi
    if [ -z "$copyright_risk" ]; then copyright_risk="MEDIUM"; fi
    if [ -z "$issues_found" ]; then issues_found="YES"; fi
    
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
    
    echo "DEBUG: check_plagiarism_and_copyright returning code: $return_code for chapter $chapter_num" >> debug.log
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
    echo "DEBUG: Starting rewrite_chapter_for_originality for chapter $chapter_num" >> debug.log
    
    # Make sure the files exist
    if [ ! -f "$chapter_file" ]; then
        echo "❌ Error: Chapter file not found: $chapter_file"
        return 1
    fi
    
    if [ ! -f "$plagiarism_report" ]; then
        echo "⚠️ Plagiarism report not found: $plagiarism_report (creating default)"
        # Create a default report to avoid failure
        echo "ORIGINALITY_SCORE: 5
PLAGIARISM_RISK: MEDIUM
COPYRIGHT_RISK: MEDIUM
ISSUES_FOUND: YES

DETAILED_ANALYSIS:
The content needs to be rewritten to improve originality.

FLAGGED_SECTIONS:
General structure and examples need rework.

RECOMMENDATIONS:
Rewrite with more unique examples and phrasing." > "$plagiarism_report"
    fi
    
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
    local rewrite_system_prompt="You are an expert author tasked with rewriting content to ensure complete originality while maintaining quality and value."
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
9. Ensure all content is properly cited and attributed

$word_count_instruction

WRITING GUIDELINES:
- Use your own unique voice and style
- Create original examples and anecdotes
- Rephrase all concepts in your own words
- Ensure all ideas are expressed originally
- Make content engaging and valuable
- Maintain professional quality
- Avoid using filler or fluff words or phrases
- Ensure all content is concise and to the point
- Eliminate any redundant or repetitive information
- Use varied sentence structures and lengths

Please rewrite the entire chapter with complete originality:"

    # Make API request using smart multi-provider system
    local response=""
    pulse_animation
    response=$(smart_api_call "$rewrite_prompt" "$rewrite_system_prompt" "chapter_rewrite" "$TEMPERATURE" "$MAX_TOKENS" "$MAX_RETRIES" "granite3.3:2b")
    local api_result=$?
    
    if [ $api_result -ne 0 ] || [ -z "$response" ]; then
        echo "❌ Chapter rewrite failed after multiple attempts"
        return 1
    fi

    # Extract text content (response is already plain text from smart_api_call)
    local rewritten_content="$response"
    
    # Make sure we have valid content
    if [ -z "$rewritten_content" ] || [ "$rewritten_content" = "null" ]; then
        echo "❌ Empty rewrite result for Chapter $chapter_num"
        return 1
    fi

    # Check if the rewritten content is significantly different
    original_hash=$(echo "$original_content" | md5sum | cut -d ' ' -f1)
    rewritten_hash=$(echo "$rewritten_content" | md5sum | cut -d ' ' -f1)
    
    if [ "$original_hash" = "$rewritten_hash" ]; then
        echo "⚠️ Warning: Rewritten content appears to be identical to original"
    fi
    
    # Check the word count of rewritten content
    local rewritten_word_count=$(echo "$rewritten_content" | wc -w)
    if [ "$word_count_ok" = "false" ] && [ $rewritten_word_count -lt 1300 ]; then
        echo "⚠️ Warning: Rewritten content is still below target word count ($rewritten_word_count words)"
    else
        echo "✅ Rewritten word count: $rewritten_word_count words"
    fi

    # Save the rewritten chapter
    local backup_file="${chapter_file}.backup_$(date +%s)"
    cp "$chapter_file" "$backup_file"
    echo "📄 Original backed up to: $(basename "$backup_file")"

    # ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Rate limiting variables
API_CALLS_FILE="/tmp/book_generator_api_calls.txt"
API_CALLS_TODAY_FILE="/tmp/book_generator_api_calls_today.txt"
MAX_CALLS_PER_MINUTE=15
MAX_CALLS_PER_DAY=1500
MINUTE_INTERVAL=60  # Seconds in a minute
DAY_INTERVAL=86400  # Seconds in a day
CURRENT_DAY=$(date +%Y-%m-%d)

# Initialize API call tracking files if they don't exist
initialize_api_tracking() {
    # Initialize or validate the minute tracking file
    if [ ! -f "$API_CALLS_FILE" ]; then
        # Create the file with initial timestamp and counter
        echo "$(date +%s) 0" > "$API_CALLS_FILE"
    fi
    
    # Initialize or validate the daily tracking file
    if [ ! -f "$API_CALLS_TODAY_FILE" ]; then
        echo "$CURRENT_DAY 0" > "$API_CALLS_TODAY_FILE"
    else
        # Check if the day has changed
        local stored_day=$(cat "$API_CALLS_TODAY_FILE" | cut -d' ' -f1)
        if [ "$stored_day" != "$CURRENT_DAY" ]; then
            # Reset for a new day
            echo "$CURRENT_DAY 0" > "$API_CALLS_TODAY_FILE"
        fi
    fi
}

# Reset API call tracking counters to zero
reset_api_tracking() {
    local current_timestamp=$(date +%s)
    
    # Reset minute counter
    echo "$current_timestamp 0" > "$API_CALLS_FILE"
    
    # Reset daily counter
    echo "$CURRENT_DAY 0" > "$API_CALLS_TODAY_FILE"
    
    echo -e "${GREEN}✓${RESET} API tracking counters have been reset to zero."
    show_api_usage
}

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

# ASCII progress bar drawer (reusable)
draw_progress_bar() {
    local percent=${1:-0}
    local width=${2:-20}
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    if [ $filled -gt 0 ]; then
        printf "%0.s=" $(seq 1 $filled)
    fi
    if [ $empty -gt 0 ]; then
        printf "%0.s " $(seq 1 $empty)
    fi
    printf "] %d%%" "$percent"
}

# Function to sanitize book topic for use as folder name
sanitize_book_title() {
    local topic="$1"
    
    # Convert to lowercase, remove apostrophes, then replace non-alphanumeric with dashes
    echo "$topic" \
    | tr '[:upper:]' '[:lower:]' \
    | sed "s/'//g" \
    | sed -E 's/[^a-z0-9 ]//g' \
    | tr -s ' ' '-' \
    | sed -E 's/^-+//; s/-+$//' 
}

# Function to show API usage dashboard
show_api_usage() {
    initialize_api_tracking
    
    local current_timestamp=$(date +%s)
    local minute_ago=$((current_timestamp - MINUTE_INTERVAL))
    
    # Read the minute tracking file
    local timestamp_and_count=$(cat "$API_CALLS_FILE")
    local last_timestamp=$(echo "$timestamp_and_count" | cut -d' ' -f1)
    local minute_count=$(echo "$timestamp_and_count" | cut -d' ' -f2)
    
    # Read the day tracking file
    local day_and_count=$(cat "$API_CALLS_TODAY_FILE")
    local day_count=$(echo "$day_and_count" | cut -d' ' -f2)
    
    # Calculate time since first call in this minute window
    local time_since_first_call=$((current_timestamp - last_timestamp))
    local minute_reset_in=$((MINUTE_INTERVAL - time_since_first_call))
    
    # Calculate percentages
    local minute_percent=$((minute_count * 100 / MAX_CALLS_PER_MINUTE))
    local day_percent=$((day_count * 100 / MAX_CALLS_PER_DAY))
    
    # Draw ASCII progress bars (uses top-level draw_progress_bar)
    
    echo -e "\n${CYAN}════════════════ API USAGE DASHBOARD ════════════════${RESET}"
    
    # Per-minute usage
    echo -e "${YELLOW}Per-Minute Usage:${RESET} $minute_count/$MAX_CALLS_PER_MINUTE calls"
    echo -n "  "
    draw_progress_bar $minute_percent
    echo -e " (resets in ${minute_reset_in}s)"
    
    # Daily usage
    echo -e "${YELLOW}Daily Usage:${RESET} $day_count/$MAX_CALLS_PER_DAY calls"
    echo -n "  "
    draw_progress_bar $day_percent
    echo -e " (resets at midnight)"
    
    echo -e "${CYAN}════════════════════════════════════════════════${RESET}\n"
}

# Check rate limits and calculate necessary delay
check_rate_limits() {
    initialize_api_tracking
    
    local current_timestamp=$(date +%s)
    local minute_ago=$((current_timestamp - MINUTE_INTERVAL))
    
    # Read the minute tracking file
    local timestamp_and_count=$(cat "$API_CALLS_FILE")
    local last_timestamp=$(echo "$timestamp_and_count" | cut -d' ' -f1)
    local minute_count=$(echo "$timestamp_and_count" | cut -d' ' -f2)
    
    # Read the day tracking file
    local day_and_count=$(cat "$API_CALLS_TODAY_FILE")
    local day_count=$(echo "$day_and_count" | cut -d' ' -f2)
    
    # Check if minute interval has passed
    if [ "$last_timestamp" -lt "$minute_ago" ]; then
        # More than a minute has passed, reset minute counter
        echo "$current_timestamp 1" > "$API_CALLS_FILE"
        minute_count=1
    else
        # Increment the minute counter
        minute_count=$((minute_count + 1))
        echo "$last_timestamp $minute_count" > "$API_CALLS_FILE"
    fi
    
    # Increment the day counter
    day_count=$((day_count + 1))
    echo "$CURRENT_DAY $day_count" > "$API_CALLS_TODAY_FILE"
    
    # Calculate delay if we're over the per-minute limit
    local minute_delay=0
    if [ "$minute_count" -gt "$MAX_CALLS_PER_MINUTE" ]; then
        # Calculate time to wait until the minute rolls over
        local time_since_first_call=$((current_timestamp - last_timestamp))
        minute_delay=$((MINUTE_INTERVAL - time_since_first_call + 1))
        
        if [ "$minute_delay" -lt 1 ]; then
            minute_delay=1
        fi
        
        echo "⚠️ Per-minute rate limit reached ($minute_count/$MAX_CALLS_PER_MINUTE calls)"
        # Show usage stats when we hit limits
        show_api_usage
    fi
    
    # Check if we're over the daily limit
    if [ "$day_count" -gt "$MAX_CALLS_PER_DAY" ]; then
        echo "❌ Daily rate limit exceeded! ($day_count/$MAX_CALLS_PER_DAY calls)"
        echo "Daily API call limit has been reached. Please try again tomorrow."
        return 1
    fi
    
    # Return the delay needed
    echo "$minute_delay"
    return 0
}

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
    
    # Removed section-splitting and section-specific quality checks per user request.
    # Instead we provide a helper that appends continuation text until min words are reached.

    append_until_min_words() {
        local chapter_file="$1"
        local min_words="$2"
        local attempt=1
        local max_attempts=5
        local current_words=$(wc -w < "$chapter_file" | tr -d ' ')

        while [ "$current_words" -lt "$min_words" ] && [ $attempt -le $max_attempts ]; do
            echo "🔁 Auto-append attempt $attempt for $chapter_file (current: $current_words, target: $min_words)"
            local continue_prompt="The chapter below currently has ${current_words} words and must be expanded to at least ${min_words} words. Continue the chapter in the same voice and style, expanding ideas and adding examples without repeating text verbatim. Provide ONLY the continuation text to append.\n\n$(cat "$chapter_file")"
            local cont_result
            cont_result=$(smart_api_call "$continue_prompt" "$CHAPTER_SYSTEM_PROMPT" "continuation" 0.6 2048 1 "phi4-mini:3.8b")
            if [ $? -ne 0 ] || [ -z "$cont_result" ]; then
                echo "⚠️ Auto-append attempt $attempt failed or returned empty"
                attempt=$((attempt + 1))
                continue
            fi

            # Clean and append
            cont_result=$(echo "$cont_result" | sed 's/^---$//g' | sed '/^Note:/d' | sed '/^This content could be appended/d' | sed '/^I will now continue/d')
            echo -e "\n\n$cont_result" >> "$chapter_file"

            current_words=$(wc -w < "$chapter_file" | tr -d ' ')
            echo "ℹ️ New word count for $(basename "$chapter_file"): $current_words words"
            attempt=$((attempt + 1))
        done

        if [ "$current_words" -lt "$min_words" ]; then
            echo "⚠️ After auto-append attempts, $(basename "$chapter_file") remains below minimum ($current_words/$min_words)."
        else
            echo "✅ $(basename "$chapter_file") reached target: $current_words words"
        fi
    }

    # Call the helper to ensure chapter reaches minimum length
    append_until_min_words "$CHAPTER_FILE" "$MIN_WORDS"

    # Final word count
    FINAL_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    echo "📊 Chapter $CHAPTER_NUM final word count: $FINAL_WORD_COUNT words"
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
# progress_bar() {
#     local duration=${1:-5}
#     local message="${2:-Loading}"
#     local width=30
#     local count=0
#     local total=$((duration * 10))
    
#     while [ $count -lt $total ]; do
#         local progress=$((count * width / total))
#         local percent=$((count * 100 / total))
        
#         # Create the bar
#         local bar="["
#         for ((i=0; i<width; i++)); do
#             if [ $i -lt $progress ]; then
#                 bar+="${GREEN}=${RESET}"
#             else
#                 bar+=" "
#             fi
#         done
#         bar+="]"
        
#         printf "\r\033[K🔄 $message $bar ${BLUE}%d%%${RESET}" "$percent"
#         sleep 0.1
#         count=$((count + 1))
#     done
#     printf "\r\033[K"
# }

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
trap 'echo "DEBUG: Error at line $LINENO: Command \"$BASH_COMMAND\" exited with status $?" >> debug.log' ERR

# Ensure the script doesn't exit on errors
set +e

# Debug, echo all passed parameters
echo "Debug: Arguments passed: $@" >> debug.log

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
        --reset-api-tracking)
            reset_api_tracking
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
echo "Debug: OUTLINE_ONLY is set to: $OUTLINE_ONLY" >> debug.log
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

# Initialize multi-provider system
if setup_multi_provider_system; then
    echo "✅ Multi-provider system initialized successfully"
    echo ""
else
    echo "❌ Failed to initialize multi-provider system"
    exit 1
fi

# API configuration (legacy - now using Ollama only)
# API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Note: API tracking now handled by smart_api_call in multi_provider_ai_simple.sh
# Initialize API tracking and show dashboard (commenting out for Ollama-only mode)
# initialize_api_tracking
# show_api_usage

echo "🔧 Configuration: Using Ollama-only mode via smart_api_call"

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
        echo "Debug: Invalid JSON payload:" >> debug.log
        echo "$1" | head -n 20 >> debug.log
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

When creating book outlines, you must always follow these strict formatting rules:
- Chapters must be listed in the format: "Chapter X: Title"
- Use consecutive numbers (1, 2, 3, …), no Roman numerals or bullets
- Each chapter must include a 2-3 sentence summary immediately after the title
- Do not include any Markdown (#, *, -, etc.)
- Do not use quotation marks around titles
- Do not include extra formatting or decorations
- The number of chapters should be a minimum of 14 and a maximum of 20.
EOF
)

echo "Debug: SYSTEM_PROMPT before user prompt:" > debug.log
echo "$SYSTEM_PROMPT" | head -n 10 >> debug.log  # Log first 10 lines for context

    USER_PROMPT="Create a detailed outline for a ${GENRE} book about '${TOPIC}' targeting ${AUDIENCE}.

REQUIRED FORMAT:
Chapter 1: [Chapter Title]
[2-3 sentence summary]
Chapter 2: [Chapter Title]
[2-3 sentence summary]
(continue for 14-20 chapters)

Also include, at the end:
1. A compelling book title and subtitle
2. 3-5 core themes to weave throughout the book
3. Character profiles (for fiction) or key concept definitions (for non-fiction)
4. Target reading level and tone guidance
5. Suggested word count distribution

STRICT REQUIREMENTS:
- Chapters must always use the exact format: 'Chapter N: Title'
- No Markdown, bullets, asterisks, or extra symbols
- No indentation or numbering other than 'Chapter N'
- All text must be plain text, easy to parse"

    echo "Debug: USER_PROMPT for outline generation:" > debug.log
    echo "$USER_PROMPT" >> debug.log
    typewriter "Preparing to generate your book outline..." 0.05 "🧠 "
    
    
    # Use smart_api_call directly instead of complex JSON payload construction
    loading_dots 8 "🔄 Making API request for book outline generation" &
    OUTLINE_RESPONSE=$(smart_api_call "$USER_PROMPT" "$SYSTEM_PROMPT" "analytical" "$TEMPERATURE" "$MAX_TOKENS" "$MAX_RETRIES" "gemma3:1b")
    smart_api_result=$?

    # Error handling
    if [ $smart_api_result -ne 0 ]; then
        echo "${RED}❌ API request failed. Exiting.${RESET}"
        exit 1
    fi

    # Create book-specific output directory
    BOOK_TITLE_SANITIZED=$(sanitize_book_title "$TOPIC")
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    OUTPUT_DIR="./book_outputs/${BOOK_TITLE_SANITIZED}-${TIMESTAMP}"
    mkdir -p "$OUTPUT_DIR"
    
    OUTLINE_FILE="${OUTPUT_DIR}/book_outline.md"

    echo "$OUTLINE_RESPONSE" > "$OUTLINE_FILE"
    # Sanitize outline to extract only chapter headers and their summaries,
    # then renumber chapters starting at 1 to avoid stray high-numbered entries
    sanitize_outline_file() {
        local infile="$1"
        local tmpf
        tmpf=$(mktemp)

        awk '
        BEGIN {
            IGNORECASE=1;
            chap_re = "^Chapter[[:space:]]*[0-9]+[[:space:]]*:";
            in_chapter = 0;
            summary_lines = 0;
        }
        {
            if ($0 ~ chap_re) {
                # Start a new chapter block
                in_chapter = 1;
                summary_lines = 0;
                print $0;
                next;
            }
            if (in_chapter) {
                # Stop chapter block if next chapter header starts (handled above) or if we hit a metadata header
                if ($0 ~ /^[[:space:]]*$/) {
                    # blank line counts as part of separation; allow one blank line
                    print "";
                    summary_lines++;
                    if (summary_lines >= 3) { in_chapter = 0 }
                    next;
                }
                # Stop if we encounter obvious metadata headings
                if ($0 ~ /^(\*\*Subtitle|\*\*Themes|Themes:|Character Profiles|Key Concept|Key Concept Definitions|Target Reading Level|Suggested Word Count|Suggested Word Count Distribution|Suggested Word Count:|\-\-|\*\*|## )/i) {
                    in_chapter = 0;
                    next;
                }
                # Otherwise treat as summary line and print, but limit to 4 lines
                if (summary_lines < 4) {
                    print $0;
                    summary_lines++;
                } else {
                    in_chapter = 0;
                }
            }
        }
        ' "$infile" > "$tmpf"

        # Renumber chapters sequentially starting at 1
        if [ -s "$tmpf" ]; then
            awk '
            BEGIN { count = 0 }
            /^Chapter[[:space:]]*[0-9]+[[:space:]]*:/ {
                count++;
                # extract everything after the colon
                split($0, parts, ":");
                title = parts[2];
                # Trim leading spaces
                sub(/^[[:space:]]+/, "", title);
                print "Chapter " count ": " title;
                next;
            }
            { print }
            ' "$tmpf" > "${tmpf}.renumbered"

            mv "${tmpf}.renumbered" "$infile"
            rm -f "$tmpf"
            echo "DEBUG: Sanitized outline (chapters only) saved to $infile" >> debug.log
        else
            rm -f "$tmpf"
            echo "DEBUG: Sanitization produced empty result for $infile; leaving original" >> debug.log
        fi
    }

    # Run sanitization on the generated outline to remove appended metadata
    sanitize_outline_file "$OUTLINE_FILE"
    # Display path more cleanly to avoid terminal wrap issues
    echo -e "📃 Outline generated and saved to:\n   $OUTLINE_FILE"

    # Ensure OUTLINE_CONTENT is populated with the correct outline file content
    if [ -f "$OUTLINE_FILE" ]; then
        OUTLINE_CONTENT=$(cat "$OUTLINE_FILE")
    else
        echo "❌ Error: Outline file not found at $OUTLINE_FILE"
        exit 1
    fi

    # Review and Proofreading Step
    rainbow_text 2 "Preparing review step"
    REVIEW_PROMPT="Review and proofread the following book outline for grammar, clarity, and structure. Suggest any necessary corrections or improvements. Ensure to keep the chapter titles and numbers intact. These chapters and numbers are required for the next steps in the book generation process. Also keep the book title at the top of the response.

OUTLINE:
$OUTLINE_CONTENT"

    # Debugging: Confirm OUTLINE_CONTENT before review step
    echo "Debug: OUTLINE_CONTENT before review step:" > debug.log
    echo "$OUTLINE_CONTENT" | head -n 10 >> debug.log  # Log first 10 lines for context

    loading_dots 10 "🔄 Making API request for review and proofreading" &
    REVIEW_RESPONSE=$(smart_api_call "$REVIEW_PROMPT" "$SYSTEM_PROMPT" "analytical" 0.5 "$MAX_TOKENS" "$MAX_RETRIES" "qwen2:7b-instruct-q4_K_M")

    if [ $? -ne 0 ]; then
        echo "❌ API request for review failed. Exiting."
        exit 1
    fi

    REVIEWED_OUTLINE_FILE="${OUTPUT_DIR}/book_outline_reviewed.md"
    echo "$REVIEW_RESPONSE" > "$REVIEWED_OUTLINE_FILE"
    # Sanitize reviewed outline as well
    sanitize_outline_file "$REVIEWED_OUTLINE_FILE"
    # Display path more cleanly to avoid terminal wrap issues
    echo -e "✅ Reviewed outline saved to:\n   $REVIEWED_OUTLINE_FILE"

    # Second/Final Draft Step
    echo "DEBUG: Starting final draft step" >> debug.log
    echo "DEBUG: REVIEWED_OUTLINE_FILE = $REVIEWED_OUTLINE_FILE" >> debug.log
    echo "DEBUG: File exists check: $([ -f "$REVIEWED_OUTLINE_FILE" ] && echo "YES" || echo "NO")" >> debug.log
    
    loading_dots 2 "Preparing final draft"
    
    # Check if reviewed outline file exists and has content
    if [ ! -f "$REVIEWED_OUTLINE_FILE" ]; then
        echo "❌ Error: Reviewed outline file not found at $REVIEWED_OUTLINE_FILE"
        echo "DEBUG: Reviewed outline file not found, exiting" >> debug.log
        exit 1
    fi
    
    if [ ! -s "$REVIEWED_OUTLINE_FILE" ]; then
        echo "❌ Error: Reviewed outline file is empty"
        echo "DEBUG: Reviewed outline file is empty, exiting" >> debug.log
        exit 1
    fi
    
    echo "DEBUG: Reviewed outline file size: $(wc -c < "$REVIEWED_OUTLINE_FILE") bytes" >> debug.log
    echo "DEBUG: First few lines of reviewed outline:" >> debug.log
    head -n 5 "$REVIEWED_OUTLINE_FILE" >> debug.log

    FINAL_DRAFT_PROMPT="Improve the following book outline in any way possible. Focus on enhancing its quality, structure, and content. Ensure it is engaging and well-organized. Ensure to keep the chapter titles and numbers intact. These chapters and numbers are required for the next steps in the book generation process. Also keep the book title at the top of the response.

OUTLINE:
$(cat "$REVIEWED_OUTLINE_FILE")"

    echo "DEBUG: Final draft prompt length: ${#FINAL_DRAFT_PROMPT} characters" >> debug.log
    echo "DEBUG: About to call smart_api_call for final draft" >> debug.log

    loading_dots 10 "🔄 Making API request for second/final draft" &
    FINAL_DRAFT_RESPONSE=$(smart_api_call "$FINAL_DRAFT_PROMPT" "$SYSTEM_PROMPT" "creative" 0.4 "$MAX_TOKENS" "$MAX_RETRIES" "gemma3:1b")
    final_draft_exit_code=$?
    
    echo "DEBUG: smart_api_call returned with exit code: $final_draft_exit_code" >> debug.log
    echo "DEBUG: Final draft response length: ${#FINAL_DRAFT_RESPONSE} characters" >> debug.log
    
    if [ $final_draft_exit_code -ne 0 ]; then
        echo "❌ API request for final draft failed. Exit code: $final_draft_exit_code"
        echo "DEBUG: Final draft API call failed with exit code $final_draft_exit_code" >> debug.log
        exit 1
    fi

    echo "DEBUG: Final draft response received successfully" >> debug.log
    
    # Validate that we have a non-empty response
    if [ -z "$FINAL_DRAFT_RESPONSE" ]; then
        echo "❌ Error: Final draft response is empty"
        echo "DEBUG: Final draft response is empty" >> debug.log
        exit 1
    fi

    FINAL_DRAFT_FILE="${OUTPUT_DIR}/book_outline_final.md"
    echo "DEBUG: About to save final draft to: $FINAL_DRAFT_FILE" >> debug.log
    
    echo "$FINAL_DRAFT_RESPONSE" > "$FINAL_DRAFT_FILE"
    # Sanitize final draft outline
    sanitize_outline_file "$FINAL_DRAFT_FILE"
    save_result=$?
    
    echo "DEBUG: File save operation returned: $save_result" >> debug.log
    echo "DEBUG: Final draft file size after save: $(wc -c < "$FINAL_DRAFT_FILE" 2>/dev/null || echo "ERROR") bytes" >> debug.log
    
    if [ $save_result -eq 0 ] && [ -f "$FINAL_DRAFT_FILE" ] && [ -s "$FINAL_DRAFT_FILE" ]; then
        # Display path more cleanly to avoid terminal wrap issues
        echo -e "✅ Final draft saved to:\n   $FINAL_DRAFT_FILE"
        echo "DEBUG: Final draft saved successfully" >> debug.log
    else
        echo "❌ Error: Failed to save final draft to file"
        echo "DEBUG: Failed to save final draft - save_result=$save_result, file_exists=$([ -f "$FINAL_DRAFT_FILE" ] && echo "YES" || echo "NO"), file_size=$(wc -c < "$FINAL_DRAFT_FILE" 2>/dev/null || echo "ERROR")" >> debug.log
        exit 1
    fi
    
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
echo "Debug: Starting final draft step with OUTLINE_CONTENT:" >> debug.log
echo "$OUTLINE_CONTENT" | head -n 10 >> debug.log  # Show first 10 lines for context

# Debugging: Add trace for chapter generation
CHAPTERS_INFO=$(extract_chapters "$OUTLINE_FILE")
if [ -z "$CHAPTERS_INFO" ]; then
    echo "❌ Error: Could not extract chapter information from outline"
    echo "Please check that your outline contains chapters in format:"
    echo "Chapter 1: Title"
    echo "Chapter 2: Title"
    exit 1
fi

# Legacy API function replaced with smart_api_call wrapper
# This maintains backward compatibility while using the improved multi-provider system
make_api_request() {
    local payload="$1"
    local function_caller=${FUNCNAME[1]}
    
    echo "DEBUG: make_api_request (legacy) called from $function_caller, converting to smart_api_call" >> debug.log
    
    # Validate that payload is valid JSON before processing
    if ! echo "$payload" | jq -e '.' > /dev/null 2>&1; then
        echo "❌ Invalid JSON payload"
        echo "DEBUG: make_api_request invalid payload, returning 1" >> debug.log
        return 1
    fi
    
    # Extract prompt from Gemini-format JSON payload
    local user_prompt=""
    local system_prompt="You are a helpful AI assistant specializing in book writing and content creation."
    
    # Try to extract the prompt from the JSON structure
    if echo "$payload" | jq -e '.contents[0].parts[0].text' > /dev/null 2>&1; then
        local full_text=$(echo "$payload" | jq -r '.contents[0].parts[0].text')
        
        # Check if it's in SYSTEM/USER format
        if echo "$full_text" | grep -q "^SYSTEM:"; then
            system_prompt=$(echo "$full_text" | sed -n 's/^SYSTEM: \(.*\)$/\1/p' | head -1)
            user_prompt=$(echo "$full_text" | sed 's/^SYSTEM: .*$//' | sed 's/^USER: //' | sed 's/^[[:space:]]*//')
        else
            user_prompt="$full_text"
        fi
    else
        echo "❌ Could not extract prompt from payload"
        echo "DEBUG: make_api_request could not parse payload, returning 1" >> debug.log
        return 1
    fi
    
    # Extract temperature if available
    local temperature="0.8"
    if echo "$payload" | jq -e '.generationConfig.temperature' > /dev/null 2>&1; then
        temperature=$(echo "$payload" | jq -r '.generationConfig.temperature')
    fi
    
    # Extract max tokens if available
    local max_tokens="50000"
    if echo "$payload" | jq -e '.generationConfig.maxOutputTokens' > /dev/null 2>&1; then
        max_tokens=$(echo "$payload" | jq -r '.generationConfig.maxOutputTokens')
    fi
    
    echo "DEBUG: Converted to smart_api_call with temp=$temperature, max_tokens=$max_tokens" >> debug.log
    
    # Call smart_api_call and format response to match expected JSON structure
    loading_dots 6 "🔄 Making API request via smart_api_call" &
    local response=$(smart_api_call "$user_prompt" "$system_prompt" "creative" "$TEMPERATURE" "$MAX_TOKENS" "$MAX_RETRIES" "gemma3:1b")
    local smart_api_result=$?
    
    if [ $smart_api_result -eq 0 ]; then
        # Format response to match Gemini JSON structure expected by existing code
        local formatted_response=$(jq -n \
            --arg content "$response" \
            '{
                "candidates": [{
                    "content": {
                        "parts": [{
                            "text": $content
                        }]
                    }
                }]
            }')
        
        echo "DEBUG: make_api_request returning successfully via smart_api_call" >> debug.log
        echo "$formatted_response"
        return 0
    else
        echo "❌ Smart API call failed"
        echo "DEBUG: make_api_request smart_api_call failed, returning 1" >> debug.log
        return 1
    fi
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
CHAPTER_SYSTEM_PROMPT="You are a professional book author specializing in creating immersive, narrative-driven chapters for publication. You excel at long-form storytelling with flowing paragraphs rather than lists or bullet points. Focus on creating rich, descriptive content that pulls readers into the subject through vivid language and emotional connection. Your writing style favors continuous narrative text over fragmented sections, creates memorable mental images, and maintains consistent pacing throughout each chapter. You produce only final, publication-ready text without meta-commentary, separators, or annotations. Do not include the book outline, notes, or any other extraneous information in the response."

# Store chapters in an array to avoid pipe issues
echo "DEBUG: Preparing to process chapters" >> debug.log

# Create array from chapters info more safely
# First, ensure we have proper data
if [ -z "$CHAPTERS_INFO" ]; then
    echo "ERROR: No chapter info available!" >> debug.log
    exit 1
fi

# Store each line in the array
IFS=$'\n'
CHAPTER_LINES=()
while read -r line; do
    CHAPTER_LINES+=("$line")
done <<< "$CHAPTERS_INFO"
unset IFS

# Verify we have chapters to process
if [ ${#CHAPTER_LINES[@]} -eq 0 ]; then
    echo "ERROR: No chapters found in outline!" >> debug.log
    exit 1
fi

echo "DEBUG: Found ${#CHAPTER_LINES[@]} chapters to process" >> debug.log

# Make sure we trap errors without exiting script
set +e

for CHAPTER_LINE in "${CHAPTER_LINES[@]}"; do
    # Start timer for this chapter
    CHAPTER_START_TIME=$(date +%s)
    
    # Parse chapter number and title
    IFS='|' read -r CHAPTER_NUM CHAPTER_TITLE <<< "$CHAPTER_LINE"
    echo "DEBUG: Starting processing for chapter $CHAPTER_NUM" >> debug.log
    
    # Clean up title (remove quotes, trim whitespace, remove * and other markdown characters, trailing attached to the last word in a line)
    CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//;s/^[[:space:]]*//;s/[[:space:]]*$//;s/\*//g;s/[[:space:]]*[*-]\?[[:space:]]*$//;s/[[:space:]]*$//')

    echo "📝 Generating Chapter $CHAPTER_NUM: $CHAPTER_TITLE"

    # Ideally, if generate chapters from outline is selected, it should start from the last completed chapter

    # Collect existing chapters for context
    EXISTING_CHAPTERS=""
    for i in $(seq 1 $((CHAPTER_NUM - 1))); do
        echo "Debug: Collecting existing chapter $i for context" >> debug.log
        CHAPTER_FILE="${BOOK_DIR}/chapter_${i}.md"
        if [ -f "$CHAPTER_FILE" ]; then
            CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
            EXISTING_CHAPTERS="${EXISTING_CHAPTERS}\n\n=== CHAPTER $i ===\n${CHAPTER_CONTENT}"
        fi
    done

    # Style and tone instructions
    get_style_instructions() {
        echo "Debug: Getting style instructions for chapter $CHAPTER_NUM" >> debug.log
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

    echo "Debug: Getting style and tone instructions for chapter $CHAPTER_NUM" >> debug.log
    STYLE_INSTRUCTIONS=$(get_style_instructions)
    TONE_INSTRUCTIONS=$(get_tone_instructions)

    # Clean outline content to remove markdown asterisks
OUTLINE_CONTENT=$(echo "$OUTLINE_CONTENT" | sed 's/\*\*//g')

# Create new loop, to extend generate more to the chapter file and join both to meet the minimum word count

CHAPTER_USER_PROMPT="Write Chapter ${CHAPTER_NUM}: '${CHAPTER_TITLE}' based on the outline and existing chapters.

CRITICAL LENGTH REQUIREMENT:
- Write EXACTLY ${MIN_WORDS}-${MAX_WORDS} words (this is mandatory)
- Do NOT write less than ${MIN_WORDS} words under any circumstances
- Expand ideas fully to reach the required length naturally

CRITICAL OUTPUT FORMAT REQUIREMENTS:
- ONLY produce FINAL chapter content - NO comments, notes, placeholders, or separators (---)
- NEVER include meta text like 'Here is the chapter' or 'This content could be appended'
- NEVER acknowledge these instructions in your response
- DO NOT use the word 'Conclusion' as a subheading - use creative alternatives instead
- NEVER include text that suggests the content is a draft or sample
- NEVER explain what you're doing or what you've written
- NEVER include the book outline or any other chapters in your response
- NEVER include any meta-text or commentary in your response
- NEVER include any instructions or explanations in your response

PARAGRAPH AND FORMATTING REQUIREMENTS:
- At least 90% of content MUST be narrative paragraphs (this is mandatory)
- Use no more than 1-2 bulleted or numbered lists in the entire chapter
- Limit use of bold formatting to no more than 5 instances
- Use subheadings sparingly (maximum 4-5 in total)
- Write long form paragraphs and avoid fragmented sentences
- If ending with a summary, use creative titles like 'Looking Ahead' or 'The Path Forward'
- For the final paragraph, consider a seamless transition without a subheading

PLAGIARISM AND ORIGINALITY:
- Ensure all content is completely original, do not use any copyrighted material whatsoever
- DO NOT plagiarize other authors' works
- Always provide proper attribution for any sources used
- Include citations and references for any quoted or paraphrased material
- Use your own original words and ideas to express concepts
- Avoid using generic phrases or clichés

WRITING STYLE: ${WRITING_STYLE}
${STYLE_INSTRUCTIONS}

TONE: ${TONE}
${TONE_INSTRUCTIONS}

STRUCTURE REQUIREMENTS:
- Start with a compelling opening hook
- Focus on storytelling and narrative flow throughout
- Present concepts as a cohesive journey rather than disconnected sections
- Use descriptive language that creates vivid mental images
- End with reflective thoughts that lead naturally to the next chapter

CONTENT EXPANSION TECHNIQUES:
- Elaborate on every concept with detailed explanations and rich descriptions
- Develop flowing narrative with seamless transitions between paragraphs
- Include personal perspectives and reflections that feel authentic
- Build an emotional connection with readers through relatable scenarios
- Use metaphors and imagery to make abstract concepts tangible
- Create a sense of continuity and progression through the chapter

BOOK OUTLINE:
${OUTLINE_CONTENT}

EXISTING CHAPTERS:
${EXISTING_CHAPTERS}

Write Chapter ${CHAPTER_NUM}: ${CHAPTER_TITLE}
TARGET: ${MAX_WORDS} words, MINIMUM: ${MIN_WORDS} words"
    
    # Generate chapter with smart_api_call directly 
    CHAPTER_RESPONSE=""
    GENERATION_SUCCESS=false
    
    # Create enhanced prompt for smart_api_call
    system_prompt="You are a professional author writing a high-quality book. Write in $WRITING_STYLE style with $TONE tone. Ensure content is original, engaging, and valuable to readers."
    
    user_prompt="Write Chapter $CHAPTER_NUM: $CHAPTER_TITLE

Book Outline Context:
$(cat "$OUTLINE_FILE" 2>/dev/null || echo "No outline available")

Previous Chapters (for continuity):
$EXISTING_CHAPTERS

REQUIREMENTS:
- Write $MIN_WORDS-$MAX_WORDS words of engaging narrative content
- Ensure smooth transitions and flow between paragraphs
- Include practical examples and vivid descriptions
- Maintain consistency with previous chapters
- Write in $WRITING_STYLE style with $TONE tone

CRITICAL FORMATTING REQUIREMENTS:
- ONLY return the final chapter content - nothing else
- DO NOT include any outline, notes, section numbers, or requirements in your output
- DO NOT include phrases like 'Chapter X begins:' or 'Here is Chapter X'
- DO NOT include any meta-text explaining what you're doing
- DO NOT include any markdown separators (---)
- DO NOT include any outline, chapter structure, or section labels
- NEVER start with 'Chapter $CHAPTER_NUM: $CHAPTER_TITLE' (I'll add this myself)
- NEVER include text saying this is a draft or sample
- DO NOT include any comments or notes at the beginning or end

STRUCTURE AND CONTENT:
- Start with a compelling opening hook
- Use at least 90% narrative paragraphs (mandatory)
- Limit bullet lists to a maximum of 1-2 in the entire chapter
- If ending with a summary, use creative titles (not 'Conclusion')
- Create clear transitions between major concepts
- Avoid using subheadings that repeat the chapter title

Begin writing the chapter content now:"
    
    # Use smart_api_call directly
    echo "🤖 Generating chapter content with Ollama..." >&2
    
    # Improve handling by saving output to a file to avoid grep issues
    loading_dots 10 "🔄 Generating Chapter $CHAPTER_NUM" &
    MULTI_PROVIDER_RESULT=$(smart_api_call "$user_prompt" "$system_prompt" "creative" "$TEMPERATURE" 32000 "$MAX_RETRIES" "gemma3:1b")
    API_STATUS=$?
    
    if [ $API_STATUS -eq 0 ] && [ -n "$MULTI_PROVIDER_RESULT" ]; then
        # Convert to expected JSON format for compatibility with existing code
        CHAPTER_RESPONSE=$(jq -n --arg content "$MULTI_PROVIDER_RESULT" '{
            "candidates": [{
                "content": {
                    "parts": [{"text": $content}]
                }
            }]
        }')
        GENERATION_SUCCESS=true
        echo "✅ Chapter generation succeeded for Chapter $CHAPTER_NUM"
    else
        echo "❌ Chapter generation failed for Chapter $CHAPTER_NUM"
    fi
    
    # Check if generation was successful
    if [ "$GENERATION_SUCCESS" = "false" ]; then
        echo ""
        echo "❌ CRITICAL ERROR: Failed to generate Chapter $CHAPTER_NUM"
        echo "   Ollama API: Failed"
        echo ""
        echo "🛑 Stopping book generation. Please check:"
        echo "   1. Ollama is running (ollama serve)"
        echo "   2. Required model is installed (llama3.2:1b or similar)"
        echo "   3. Network connectivity to Ollama"
        echo "   4. System resources available"
        echo ""
        echo "📄 Debug information has been logged to debug.log"
        echo ""
        exit 1
    fi

    # Validate API response
    if ! echo "$CHAPTER_RESPONSE" | jq -e '.' > /dev/null 2>&1; then
        echo ""
        echo "❌ CRITICAL ERROR: Invalid JSON response for Chapter $CHAPTER_NUM"
        echo "🛑 Stopping book generation due to malformed API response"
        echo ""
        echo "Debug: Raw API response for Chapter $CHAPTER_NUM:" >> debug.log
        echo "$CHAPTER_RESPONSE" >> debug.log
        echo ""
        exit 1
    fi

    # Extract chapter content
    CHAPTER_CONTENT=$(echo "$CHAPTER_RESPONSE" | jq -r '.candidates[0].content.parts[0].text')
    if [ -z "$CHAPTER_CONTENT" ] || [ "$CHAPTER_CONTENT" = "null" ]; then
        echo ""
        echo "❌ CRITICAL ERROR: Empty content for Chapter $CHAPTER_NUM"
        echo "🛑 Stopping book generation due to empty chapter content"
        echo ""
        echo "Debug: API response for Chapter $CHAPTER_NUM:" >> debug.log
        echo "$CHAPTER_RESPONSE" >> debug.log
        echo ""
        exit 1
    fi
    
    # IMPORTANT FIX: Check if the prompt got included in the response and extract only the actual content
    if [[ "$CHAPTER_CONTENT" == *"Write Chapter $CHAPTER_NUM: $CHAPTER_TITLE"* ]]; then
        echo "⚠️ Detected prompt in chapter content, extracting actual content only..."
        # Find the last occurrence of "Begin writing the chapter content now:" and keep everything after it
        FIXED_CONTENT=$(echo "$CHAPTER_CONTENT" | awk -v RS='Begin writing the chapter content now:' 'END{print $0}')
        
        # Only use the fixed content if it's not empty
        if [ -n "$FIXED_CONTENT" ]; then
            CHAPTER_CONTENT="$FIXED_CONTENT"
            echo "✅ Successfully extracted actual chapter content"
        else
            echo "⚠️ Extraction failed, will apply regex filtering instead"
        fi
    fi
    
    # Enhanced cleanup - more comprehensive removal of meta-text, separators, notes, etc.
    CHAPTER_CONTENT=$(echo "$CHAPTER_CONTENT" | 
        # Check if the user prompt was included in the response and remove it
        # This is a critical fix for the issue where the prompt is included in the chapter
        sed "s/^Write Chapter $CHAPTER_NUM: $CHAPTER_TITLE.*Begin writing the chapter content now://s" |
        
        # Remove markdown separators
        sed 's/^---$//g' |
        # Remove content markers and metadata
        sed 's/^Here is Chapter [0-9]*:$//gi' |
        sed 's/^Chapter [0-9]* begins:$//gi' |
        sed 's/^Chapter [0-9]*: .*$//gi' |
        # Remove any lines that look like notes, instructions or AI responses
        sed '/^Note:/d' |
        sed '/^Certainly! Here is/d' |
        sed '/^Here is the chapter/d' |
        sed '/^Here is the content/d' |
        sed '/^I hope this chapter/d' |
        sed '/^I have written/d' |
        sed '/^As requested/d' |
        sed '/^This chapter follows/d' |
        # Remove requirements or outline text
        sed '/^REQUIREMENTS:/d' |
        sed '/^OUTLINE:/d' |
        sed '/^CHAPTER OUTLINE:/d' |
        sed '/^Word count:/d' |
        sed '/^Book Outline Context:/d' |
        sed '/^Previous Chapters/d' |
        sed '/^CRITICAL FORMATTING REQUIREMENTS:/d' |
        sed '/^STRUCTURE AND CONTENT:/d' |
        sed '/creative 0.95/d' |
        
        # Remove unnecessary whitespace at beginning/end
        sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}'
    )

    # Save chapter
    CHAPTER_FILE="${BOOK_DIR}/chapter_${CHAPTER_NUM}.md"
    echo "$CHAPTER_CONTENT" > "$CHAPTER_FILE"
    echo "✅ Chapter $CHAPTER_NUM saved to: $(basename "$CHAPTER_FILE")"
    
    # Show word count immediately after generation
    CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    echo "📊 Initial Chapter $CHAPTER_NUM word count: $CURRENT_WORD_COUNT words"

    # Secondary generation: If the chapter is below MIN_WORDS, ask the model to continue/expand and append
    CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    if [ -n "$CURRENT_WORD_COUNT" ] && [ "$CURRENT_WORD_COUNT" -lt "$MIN_WORDS" ]; then
        echo "ℹ️ Chapter $CHAPTER_NUM below minimum words ($CURRENT_WORD_COUNT/$MIN_WORDS). Requesting continuation..."

        # Build a continuation prompt that re-uses the chapter content and asks for expansion without repeating
        CONTINUE_PROMPT="The chapter below is currently ${CURRENT_WORD_COUNT} words and must be expanded to at least ${MIN_WORDS} words. Do NOT repeat material verbatim. Continue the chapter in the same voice and style, expanding ideas, adding examples, and improving transitions until the whole chapter reaches at least ${MIN_WORDS} words. 

CRITICAL OUTPUT FORMAT REQUIREMENTS:
- ONLY provide the continuation text that will be appended - NO separators, comments, or notes
- Do NOT include phrases like 'here is the continuation' or 'this content could be appended'
- NEVER include separator lines (---) or any other meta-content
- Ensure all content flows naturally from the existing chapter
- Maintain at least 75% narrative paragraph format (avoid lists and bullet points)
- DO NOT use 'Conclusion' as a subheading - use creative alternatives if needed

CURRENT CHAPTER:\n$CHAPTER_CONTENT\n\nProvide ONLY the additional content to be appended:"

        # Try up to two continuation attempts to reach the minimum
        CONT_ATTEMPT=1
        MAX_CONT_ATTEMPTS=2
        while [ "$CURRENT_WORD_COUNT" -lt "$MIN_WORDS" ] && [ $CONT_ATTEMPT -le $MAX_CONT_ATTEMPTS ]; do
            echo "🔁 Continuation attempt $CONT_ATTEMPT for Chapter $CHAPTER_NUM..."
            loading_dots 8 "🔄 Requesting continuation (attempt $CONT_ATTEMPT)" &
            # Use phi4-mini model for more creative completions with better context handling
            CONT_RESULT=$(smart_api_call "$CONTINUE_PROMPT" "$CHAPTER_SYSTEM_PROMPT" "creative" "$TEMPERATURE" "$MAX_TOKENS" "$MAX_RETRIES" "$(select_task_model "continuation" "phi4-mini:3.8b" "medium")")
            wait # ensure loading dots finish

            if [ $? -ne 0 ] || [ -z "$CONT_RESULT" ]; then
                echo "⚠️ Continuation request failed (attempt $CONT_ATTEMPT)."
                CONT_ATTEMPT=$((CONT_ATTEMPT + 1))
                continue
            fi

            # If the provider returned a Gemini-style JSON, extract text, otherwise use raw
            if echo "$CONT_RESULT" | jq -e '.candidates[0].content.parts[0].text' >/dev/null 2>&1; then
                ADDITIONAL_TEXT=$(echo "$CONT_RESULT" | jq -r '.candidates[0].content.parts[0].text')
            else
                ADDITIONAL_TEXT="$CONT_RESULT"
            fi

            # Clean up the content - remove meta-text, separators, notes, etc.
            ADDITIONAL_TEXT=$(echo "$ADDITIONAL_TEXT" | 
                # Remove leading/trailing whitespace
                sed 's/^\s\+//;s/\s\+$//' |
                # Remove markdown separators
                sed 's/^---$//g' |
                # Remove content continuation markers
                sed 's/^Here is the continuation:$//gi' |
                sed 's/^Here is the additional content:$//gi' |
                sed 's/^Content to be appended:$//gi' |
                sed 's/^Additional text:$//gi' |
                # Remove any lines that look like notes or instructions
                sed '/^Note:/d' |
                sed '/^This content could be appended/d' |
                sed '/^I will now continue/d'
            )

            if [ -n "$ADDITIONAL_TEXT" ]; then
                # Check if the additional text starts with heading markup
                if [[ "$ADDITIONAL_TEXT" =~ ^#+ ]]; then
                    # If it starts with headings, make sure to add a newline before
                    echo -e "\n\n$ADDITIONAL_TEXT" >> "$CHAPTER_FILE"
                else
                    # Otherwise just append with paragraph break
                    echo -e "\n\n$ADDITIONAL_TEXT" >> "$CHAPTER_FILE"
                fi
                echo "✅ Appended continuation to Chapter $CHAPTER_NUM (attempt $CONT_ATTEMPT)"
            else
                echo "⚠️ Continuation produced no additional text (attempt $CONT_ATTEMPT)"
            fi

            # Recompute word count
            CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
            echo "ℹ️ New word count for Chapter $CHAPTER_NUM: $CURRENT_WORD_COUNT words"
            CONT_ATTEMPT=$((CONT_ATTEMPT + 1))
        done

        if [ "$CURRENT_WORD_COUNT" -lt "$MIN_WORDS" ]; then
            echo "⚠️ After continuation attempts, Chapter $CHAPTER_NUM is still below the minimum words ($CURRENT_WORD_COUNT/$MIN_WORDS). It will be handled by the rewrite/autofill step later."
        fi

        # Reload CHAPTER_CONTENT for downstream checks
        CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
    fi
    
    # Word count check (moved up to immediately follow chapter generation)
    CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    echo "📊 Chapter $CHAPTER_NUM word count: $CURRENT_WORD_COUNT words"
    
    # Enhanced clean-up of the chapter content to remove any remaining meta-text or separators
    echo "🧹 Performing content cleanup..."
    cat "$CHAPTER_FILE" | 
        # Remove any markdown separators
        sed '/^---$/d' |
        # Remove lines that look like meta-text
        sed '/^Certainly! Here is/d' |
        sed '/^This new content builds/d' |
        sed '/^Here is some new content/d' |
        sed '/^Here is Chapter [0-9]*/d' |
        sed '/^I will now continue/d' |
        sed '/^Chapter [0-9]* begins:/d' |
        sed '/^Here is the content for Chapter/d' |
        sed '/^Note:/d' |
        sed '/^This chapter/d' |
        # Fix double blank lines (more than 2 consecutive newlines)
        sed '/^$/N;/^\n$/D' > "${CHAPTER_FILE}.clean"
    
    # Replace original with cleaned version
    mv "${CHAPTER_FILE}.clean" "$CHAPTER_FILE"
    
    # Final word count check
    FINAL_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    echo "📊 Chapter $CHAPTER_NUM final word count: $FINAL_WORD_COUNT words"

    # Section splitting logic removed per user request
    # IMPORTANT: This logic was intentionally removed to avoid word count issues
    
    # Re-check word count after cleanup
    CURRENT_WORD_COUNT=$(wc -w < "$CHAPTER_FILE" | tr -d ' ')
    echo "📊 Chapter $CHAPTER_NUM cleaned word count: $CURRENT_WORD_COUNT words"

    # NEW: Quality check with LanguageTool
    echo "🔍 Running quality check on Chapter $CHAPTER_NUM..."
    bouncing_ball
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
    draw_progress_bar
    echo "DEBUG: Starting plagiarism check process for chapter $CHAPTER_NUM" >> debug.log
    
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
        echo "DEBUG: Running plagiarism check, attempt #$((REWRITE_ATTEMPT+1))" >> debug.log
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
        
        echo "DEBUG: multi_check_plagiarism returned with code $PLAGIARISM_RESULT for chapter $CHAPTER_NUM (Score: $ORIGINALITY_SCORE, Words: $CURRENT_WORD_COUNT)" >> debug.log
        
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
    
    # Calculate and display chapter completion time
    CHAPTER_END_TIME=$(date +%s)
    CHAPTER_ELAPSED_TIME=$((CHAPTER_END_TIME - CHAPTER_START_TIME))
    CHAPTER_MINUTES=$((CHAPTER_ELAPSED_TIME / 60))
    CHAPTER_SECONDS=$((CHAPTER_ELAPSED_TIME % 60))
    
    echo "✅ Chapter $CHAPTER_NUM complete - $WORD_COUNT words (took ${CHAPTER_MINUTES}m ${CHAPTER_SECONDS}s)"
    
    # Rate limiting delay (except for last chapter)
    # Check if we have more chapters and this isn't the last one
    LAST_CHAPTER_NUM=""
    if [ ${#CHAPTER_LINES[@]} -gt 0 ]; then
        LAST_LINE="${CHAPTER_LINES[${#CHAPTER_LINES[@]}-1]}"
        LAST_CHAPTER_NUM=$(echo "$LAST_LINE" | cut -d'|' -f1 2>/dev/null || echo "")
    fi
    
    if [ -n "$LAST_CHAPTER_NUM" ] && [ "$CHAPTER_NUM" != "$LAST_CHAPTER_NUM" ]; then
        echo "⏳ Waiting between chapters to avoid API rate limits..."
        show_wait_animation "$DELAY_BETWEEN_CHAPTERS" "Chapter cooldown"
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
echo "📁 Generated files:"
ls -la "$BOOK_DIR"
echo ""
echo "🚀 Next steps:"
echo "   1. Review individual chapters in $BOOK_DIR"
echo "   2. Review plagiarism reports for any flagged content"
echo "   3. Run ./compile_book.sh to create final manuscript"
echo "   4. Edit and format for publishing"

# Calculate and display elapsed time
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))
HOURS=$((ELAPSED_TIME / 3600))
MINUTES=$(( (ELAPSED_TIME % 3600) / 60 ))
SECONDS=$((ELAPSED_TIME % 60))

echo ""
echo "⏱️ Job completed in ${HOURS}h ${MINUTES}m ${SECONDS}s (started: $(date -r $START_TIME '+%Y-%m-%d %H:%M:%S'), finished: $(date -r $END_TIME '+%Y-%m-%d %H:%M:%S'))"