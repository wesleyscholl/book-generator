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
MAX_TOKENS=32768
MIN_WORDS=2000
MAX_WORDS=2500
WRITING_STYLE="detailed"
TONE="professional"
DELAY_BETWEEN_CHAPTERS=30  # Seconds to avoid rate limits
OUTLINE_ONLY=false
CHAPTERS_ONLY=""

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

EXAMPLES:
    $0 "Personal Finance for Millennials" "Self-Help" "Young Adults 25-35"
    $0 "AI in Healthcare" "Technical" "Medical Professionals" --preset technical
    $0 "The Dragon's Quest" "Fantasy Fiction" "Young Adults" --preset creative --delay 45
EOF
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

# Utility function to escape JSON strings
escape_json() {
    echo "$1" | sed -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' -e 's/\r/\\r/g'
}

# Utility functions
make_api_request() {
    local payload="$1"
    local response

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$API_URL")

    echo "Debug: Raw API response:" > debug.log
    echo "$response" >> debug.log

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "❌ API Error:"
        echo "$response" | jq '.error'
        return 1
    fi

    echo "$response"
}

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

Include comprehensive chapter summaries that will guide detailed content generation.
EOF
)

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

Make sure chapter titles are specific and promise clear value to readers."

    ESCAPED_SYSTEM=$(escape_json "$SYSTEM_PROMPT")
    ESCAPED_USER=$(escape_json "$USER_PROMPT")

    JSON_PAYLOAD=$(cat << EOF
{
  "contents": [{
    "parts": [{
      "text": "SYSTEM: ${ESCAPED_SYSTEM}\n\nUSER: ${ESCAPED_USER}"
    }]
  }],
  "generationConfig": {
    "temperature": 0.7,
    "topK": 40,
    "topP": 0.95,
    "maxOutputTokens": 100000
  }
}
EOF
)

    loading_dots 3 "🔄 Making API request for outline"
    RESPONSE=$(make_api_request "$JSON_PAYLOAD")
    
    if [ $? -ne 0 ]; then
        echo "❌ API request failed. Exiting."
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
    ESCAPED_REVIEW_PROMPT=$(escape_json "$REVIEW_PROMPT")

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

    REVIEW_JSON_PAYLOAD=$(cat << EOF
{
"contents": [{
    "parts": [{
    "text": "SYSTEM: ${ESCAPED_SYSTEM}\n\nUSER: ${ESCAPED_REVIEW_PROMPT}\n\nOUTLINE:\n${OUTLINE_CONTENT}"
    }]
}],
"generationConfig": {
    "temperature": 0.7,
    "topK": 40,
    "topP": 0.95,
    "maxOutputTokens": 100000
}
}
EOF
)

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
    ESCAPED_FINAL_DRAFT_PROMPT=$(escape_json "$FINAL_DRAFT_PROMPT")

    FINAL_DRAFT_JSON_PAYLOAD=$(cat << EOF
{
"contents": [{
    "parts": [{
    "text": "SYSTEM: ${ESCAPED_SYSTEM}\n\nUSER: ${ESCAPED_FINAL_DRAFT_PROMPT}\n\nOUTLINE:\n$(cat "$REVIEWED_OUTLINE_FILE")"
    }]
}],
"generationConfig": {
    "temperature": 0.7,
    "topK": 40,
    "topP": 0.95,
    "maxOutputTokens": 100000
}
}
EOF
)
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

# Debugging: Ensure OUTLINE_CONTENT is populated before final draft step
if [ -z "$OUTLINE_CONTENT" ]; then
    echo "❌ Error: OUTLINE_CONTENT is empty. Ensure the outline was generated successfully."
    exit 1
fi

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
    local response

    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$API_URL")

    echo "Debug: Raw API response:" > debug.log
    echo "$response" >> debug.log

    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo "❌ API Error:"
        echo "$response" | jq '.error'
        return 1
    fi

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
echo "$CHAPTERS_INFO" | while IFS='|' read -r num title; do
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

echo "$CHAPTERS_INFO" | while IFS='|' read -r CHAPTER_NUM CHAPTER_TITLE; do
    # Clean up title (remove quotes, trim whitespace)
    CHAPTER_TITLE=$(echo "$CHAPTER_TITLE" | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//;s/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "📝 Generating Chapter $CHAPTER_NUM: $CHAPTER_TITLE"
    
    # Collect existing chapters for context
    EXISTING_CHAPTERS=""
    for i in $(seq 1 $((CHAPTER_NUM - 1))); do
        CHAPTER_FILE="${BOOK_DIR}/chapter_${i}.md"
        if [ -f "$CHAPTER_FILE" ]; then
            CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
            EXISTING_CHAPTERS="${EXISTING_CHAPTERS}\n\n=== CHAPTER $i ===\n${CHAPTER_CONTENT}"
        fi
    done

    # Style and tone instructions
    get_style_instructions() {
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

    STYLE_INSTRUCTIONS=$(get_style_instructions)
    TONE_INSTRUCTIONS=$(get_tone_instructions)

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

    ESCAPED_CHAPTER_SYSTEM=$(escape_json "$CHAPTER_SYSTEM_PROMPT")
    ESCAPED_CHAPTER_USER=$(escape_json "$CHAPTER_USER_PROMPT")

    CHAPTER_JSON_PAYLOAD=$(cat << EOF
{
  "contents": [{
    "parts": [{
      "text": "SYSTEM: ${ESCAPED_CHAPTER_SYSTEM}\n\nUSER: ${ESCAPED_CHAPTER_USER}"
    }]
  }],
  "generationConfig": {
    "temperature": ${TEMPERATURE},
    "topK": ${TOP_K},
    "topP": ${TOP_P},
    "maxOutputTokens": ${MAX_TOKENS}
  }
}
EOF
)

    # Generate chapter
    CHAPTER_RESPONSE=$(make_api_request "$CHAPTER_JSON_PAYLOAD")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to generate Chapter $CHAPTER_NUM"
        continue
    fi

    # Save chapter
    CHAPTER_FILE="${BOOK_DIR}/chapter_${CHAPTER_NUM}.md"
    echo "$CHAPTER_RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$CHAPTER_FILE"
    
    # Calculate statistics
    WORD_COUNT=$(wc -w < "$CHAPTER_FILE")
    TOTAL_WORDS=$((TOTAL_WORDS + WORD_COUNT))
    
    echo "✅ Chapter $CHAPTER_NUM complete - $WORD_COUNT words"
    
    if [ $WORD_COUNT -lt $MIN_WORDS ]; then
        echo "⚠️  WARNING: Word count below target ($MIN_WORDS)"
    fi
    
    # Rate limiting delay (except for last chapter)
    if [ "$CHAPTER_NUM" != "$(echo "$CHAPTERS_INFO" | tail -n1 | cut -d'|' -f1)" ]; then
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
echo ""
echo "📁 Generated files:"
ls -la "$BOOK_DIR"
echo ""
echo "🚀 Next steps:"
echo "   1. Review individual chapters in $BOOK_DIR"
echo "   2. Run ./compile_book.sh to create final manuscript"
echo "   3. Edit and format for publishing"