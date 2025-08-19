#!/bin/bash

# Simplified Multi-Provider AI System for testing
# This version focuses on integration with existing book generator

# ============================================================================
# CONFIGURATION
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

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

setup_multi_provider_system() {
    echo "🔧 Initializing Multi-Provider AI System..."
    
    # Create tracking directory
    mkdir -p "./multi_provider_logs"
    
    local available_count=0
    
    # Check Gemini API key and initialize models
    if [ -n "$GEMINI_API_KEY" ]; then
        echo "✅ Gemini API key found"
        echo "   Available models: ${#GEMINI_MODELS[@]}"
        
        # Output model details for reference
        echo "   Models configured:"
        for model_data in "${GEMINI_MODELS[@]}"; do
            local model_name=$(echo "$model_data" | cut -d':' -f1)
            local rpm=$(echo "$model_data" | cut -d':' -f2)
            local rpd=$(echo "$model_data" | cut -d':' -f4)
            echo "     - $model_name (${rpm} req/min, ${rpd} req/day)"
        done
        
        # Initialize tracking directory for model cycling
        mkdir -p "$MODEL_ERROR_DIR"
        # Clear any old error timestamps
        rm -f "$MODEL_ERROR_DIR"/*
        
        ((available_count++))
    else
        echo "⚠️  Gemini API key missing"
    fi
    
    # Check Groq API key
    if [ -n "$GROQ_API_KEY" ]; then
        echo "✅ Groq API key found"
        ((available_count++))
    else
        echo "⚠️  Groq API key missing"
    fi
    
    # Check Ollama
    if command -v ollama >/dev/null 2>&1; then
        echo "✅ Ollama CLI found"
        ((available_count++))
    else
        echo "⚠️  Ollama CLI not found"
    fi
    
    echo "✅ Initialization complete. $available_count provider types available."
    return 0
}

# Smart API call with fallback logic
smart_api_call() {
    local prompt="$1"
    local system_prompt="${2:-You are a helpful AI assistant.}"
    local task_type="${3:-general}"
    local temperature="${4:-0.7}"
    local max_tokens="${5:-8192}"
    local max_retries="${6:-3}"
    
    echo "🤖 Making smart API call..." >&2
    
    # # Try Gemini models with auto-cycling
    # if [ -n "$GEMINI_API_KEY" ]; then
    #     echo "📡 Trying Gemini models (starting with ${GEMINI_MODELS[$GEMINI_MODEL_INDEX]%%:*})..." >&2
    #     if call_gemini_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
    #         return 0
    #     fi
    #     echo "⚠️ All Gemini models failed or hit rate limits, trying alternatives" >&2
    # fi
    
    # # Try Groq as fallback
    # if [ -n "$GROQ_API_KEY" ]; then
    #     echo "📡 Trying Groq..." >&2
    #     if call_groq_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
    #         return 0
    #     fi
    # fi
    
    # Try Ollama as last resort
    if command -v ollama >/dev/null 2>&1; then
        # Check if Ollama server is running
        if curl -s --max-time 2 http://localhost:11434/api/version >/dev/null 2>&1; then
            echo "📡 Trying Ollama local model..." >&2
            if call_ollama_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
                return 0
            fi
        else
            echo "❌ Ollama server is not running. Try starting it with 'ollama serve'" >&2
        fi
    else
        echo "❌ Ollama is not installed. Please install it from https://ollama.com" >&2
    fi
    
    echo "❌ All providers failed" >&2
    return 1
}

# Gemini models with rate limits
# Model array format: "model_name:RPM:TPM:RPD"
GEMINI_MODELS=(
    # Gemini 2.5 models (newest, try these first)
    "gemini-2.5-pro:5:250000:100"
    "gemini-2.5-flash:10:250000:250"
    "gemini-2.5-flash-lite:15:250000:1000"
    # Gemini 2.0 models
    "gemini-2.0-flash:15:1000000:200"
    "gemini-2.0-flash-lite:30:1000000:200"
    # Gemini 1.5 models (fallback)
    "gemini-1.5-pro:5:250000:100" 
    "gemini-1.5-flash:10:250000:250"
    "gemini-1.5-flash-latest:15:250000:1000"
)
# Keep track of model attempts to cycle through them
GEMINI_MODEL_INDEX=0
# Rate limit tracking - Store last error timestamp for each model (file-based for bash 3 compatibility)
# Directory for storing model error timestamps
MODEL_ERROR_DIR="./multi_provider_logs/model_errors"
mkdir -p "$MODEL_ERROR_DIR"
# How long to wait before retrying a rate-limited model (in seconds)
RATE_LIMIT_COOLDOWN=60

# Helper functions for file-based model error tracking
get_model_error_time() {
    local model_name="$1"
    local error_file="$MODEL_ERROR_DIR/${model_name//\//_}"
    if [ -f "$error_file" ]; then
        cat "$error_file"
    else
        echo "0"
    fi
}

set_model_error_time() {
    local model_name="$1"
    local timestamp="${2:-$(date +%s)}"
    local error_file="$MODEL_ERROR_DIR/${model_name//\//_}"
    echo "$timestamp" > "$error_file"
}

# Gemini API call with model cycling
call_gemini_api() {
    local prompt="$1"
    local system_prompt="$2"
    local temperature="$3"
    local max_tokens="$4"
    
    # Try each model until one works or we've tried them all
    local total_models=${#GEMINI_MODELS[@]}
    local models_tried=0
    
    for attempt in {1..8}; do
        # Get current model and its details
        local model_data="${GEMINI_MODELS[$GEMINI_MODEL_INDEX]}"
        local model_name=$(echo "$model_data" | cut -d':' -f1)
        local rpm=$(echo "$model_data" | cut -d':' -f2)
        
        # Check if this model recently had rate limit errors
        local current_time=$(date +%s)
        local last_error_time=$(get_model_error_time "$model_name")
        
        local time_since_error=$((current_time - last_error_time))
        
        if [[ $time_since_error -lt $RATE_LIMIT_COOLDOWN ]]; then
            echo "⏳ Model $model_name is cooling down from rate limit, waiting time: $((RATE_LIMIT_COOLDOWN - time_since_error))s" >&2
            # Move to next model
            GEMINI_MODEL_INDEX=$(( (GEMINI_MODEL_INDEX + 1) % ${#GEMINI_MODELS[@]} ))
            models_tried=$((models_tried + 1))
            
            # If we've tried all models, break out
            if [ $models_tried -ge $total_models ]; then
                echo "⚠️ All Gemini models are currently in cooldown period" >&2
                break
            fi
            continue
        fi
        
        rainbow_text "🔄 Trying Gemini model: $model_name"
        local url="https://generativelanguage.googleapis.com/v1beta/models/${model_name}:generateContent"
        local full_prompt="$system_prompt\n\n$prompt"
        
        local payload=$(jq -n \
            --arg prompt "$full_prompt" \
            --arg temp "$temperature" \
            --arg max "$max_tokens" \
            '{
                "contents": [{
                    "parts": [{"text": $prompt}]
                }],
                "generationConfig": {
                    "temperature": ($temp | tonumber),
                    "maxOutputTokens": ($max | tonumber)
                }
            }')
        
        local response=$(curl -s --max-time 60 \
            -H "Content-Type: application/json" \
            -H "x-goog-api-key: $GEMINI_API_KEY" \
            -d "$payload" \
            "$url")
        
        # Check for successful response
        if echo "$response" | jq -e '.candidates[0].content.parts[0].text' >/dev/null 2>&1; then
            echo "$response" | jq -r '.candidates[0].content.parts[0].text'
            return 0
        else
            # Check if error is rate limit related
            if echo "$response" | grep -q "Resource has been exhausted" || \
               echo "$response" | grep -q "rateLimitExceeded" || \
               echo "$response" | grep -q "quota exceeded"; then
                echo "⚠️ Rate limit hit for $model_name, cycling to next model" >&2
                # Record the error time for this model
                set_model_error_time "$model_name"
            else
                echo "❌ Gemini API error with $model_name: $response" >&2
            fi
            
            # Move to next model for the next attempt
            GEMINI_MODEL_INDEX=$(( (GEMINI_MODEL_INDEX + 1) % ${#GEMINI_MODELS[@]} ))
        fi
    done
    
    echo "❌ All Gemini models failed or hit rate limits" >&2
    return 1
}

# Groq API call
call_groq_api() {
    local prompt="$1"
    local system_prompt="$2"
    local temperature="$3"
    local max_tokens="$4"
    
    local url="https://api.groq.com/openai/v1/chat/completions"
    
    local payload=$(jq -n \
        --arg system "$system_prompt" \
        --arg prompt "$prompt" \
        --arg temp "$temperature" \
        --arg max "$max_tokens" \
        '{
            "messages": [
                {"role": "system", "content": $system},
                {"role": "user", "content": $prompt}
            ],
            "model": "llama-3.1-8b-instant",
            "temperature": ($temp | tonumber),
            "max_tokens": ($max | tonumber)
        }')
    
    local response=$(curl -s --max-time 60 \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")
    
    if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        echo "$response" | jq -r '.choices[0].message.content'
        return 0
    else
        echo "Groq API error: $response" >&2
        return 1
    fi
}

# Ollama API call
call_ollama_api() {
    local prompt="$1"
    local system_prompt="$2"
    local temperature="$3"
    local max_tokens="$4"
    
    # Validate temperature is a number
    if ! [[ "$temperature" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "⚠️ Warning: Invalid temperature value '$temperature', defaulting to 0.7" >&2
        temperature=0.7
    fi
    
    # Choose appropriate model based on availability
    local model_name="llama3.2:1b"
    if ! ollama list 2>/dev/null | grep -q "$model_name"; then
        # Fallback to other models if llama3.2:1b isn't available
        model_name="llama3:8b"
        if ! ollama list 2>/dev/null | grep -q "$model_name"; then
            model_name="llama2:7b"
        fi
    fi
    
    echo "🖥️ Using local Ollama model: $model_name with temperature $temperature" >&2
    
    local url="http://localhost:11434/api/generate"
    local full_prompt="$system_prompt\n\n$prompt"
    
    # Use jq to properly format the JSON payload
    local payload=$(jq -n \
        --arg model "$model_name" \
        --arg prompt "$full_prompt" \
        --argjson temp "$temperature" \
        --argjson max_tokens "$max_tokens" \
        '{
            "model": $model,
            "prompt": $prompt,
            "stream": false,
            "options": {
                "temperature": $temp,
                "max_tokens": $max_tokens
            }
        }')
    
    # Debug output
    # echo "Payload: $payload" >&2
    
    local response=$(curl -s --max-time 120 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")
    
    # Check for successful response
    if echo "$response" | jq -e '.response' >/dev/null 2>&1; then
        echo "$response" | jq -r '.response'
        return 0
    else
        echo "❌ Ollama API error: $response" >&2
        return 1
    fi
}

# ============================================================================
# BOOK GENERATION FUNCTIONS
# ============================================================================

generate_outline_with_smart_api() {
    local topic="$1"
    local genre="$2"
    local audience="$3"
    local style="${4:-detailed}"
    local tone="${5:-professional}"
    
    local system_prompt="You are an expert book author and publishing professional with extensive experience in creating compelling book outlines that sell well and engage readers."
    
    local user_prompt="Create a comprehensive book outline for a ${genre} book about '${topic}' targeting ${audience}.

Requirements:
- Include 12-15 chapters with compelling titles
- Each chapter should have a 2-3 sentence summary
- Focus on ${style} writing style with ${tone} tone
- Ensure logical flow and progression
- Include practical value for the target audience
- Make it commercially appealing

Format the outline clearly with chapter numbers, titles, and summaries."
    
    smart_api_call "$user_prompt" "$system_prompt" "analytical" 0.7 8192
}

generate_chapter_with_smart_api() {
    local chapter_num="$1"
    local chapter_title="$2"
    local existing_chapters="$3"
    local outline="$4"
    local min_words="$5"
    local max_words="$6"
    local style="$7"
    local tone="$8"
    
    local system_prompt="You are a professional author writing a high-quality book. Write in ${style} style with ${tone} tone. Ensure content is original, engaging, and valuable to readers."
    
    local user_prompt="Write Chapter ${chapter_num}: ${chapter_title}

Book Outline Context:
${outline}

Previous Chapters (for continuity):
${existing_chapters}

Requirements:
- Write ${min_words}-${max_words} words
- Make it engaging and informative
- Ensure smooth transitions and flow
- Include practical examples where appropriate
- Maintain consistency with previous chapters
- Write in ${style} style with ${tone} tone

Begin writing the chapter now:"
    
    smart_api_call "$user_prompt" "$system_prompt" "creative" 0.8 8192
}

check_plagiarism_with_smart_api() {
    local chapter_file="$1"
    local content=$(cat "$chapter_file")
    
    local system_prompt="You are an expert plagiarism checker and originality assessor. Analyze content for originality and potential copyright issues."
    
    local user_prompt="Analyze this chapter content for originality and plagiarism concerns:

${content}

Provide:
1. Originality score (1-10, where 10 is completely original)
2. Any potential copyright concerns
3. Recommendations for improvement if needed

Be thorough but fair in your assessment."
    
    local result=$(smart_api_call "$user_prompt" "$system_prompt" "analytical" 0.3 4096)
    
    # Extract score and determine return code
    if echo "$result" | grep -q -E "(score|rating).*[8-9]|10"; then
        return 0  # High originality
    elif echo "$result" | grep -q -E "(score|rating).*[6-7]"; then
        return 1  # Medium risk
    else
        return 2  # Low originality/high risk
    fi
}

rewrite_chapter_with_smart_api() {
    local chapter_file="$1"
    local plagiarism_report="$2"
    local content=$(cat "$chapter_file")
    local report_content=""
    
    if [ -f "$plagiarism_report" ]; then
        report_content=$(cat "$plagiarism_report")
    fi
    
    local system_prompt="You are an expert editor tasked with rewriting content to improve originality while maintaining quality and message."
    
    local user_prompt="Rewrite this chapter to improve originality and address plagiarism concerns:

Original Chapter:
${content}

Plagiarism Analysis:
${report_content}

Requirements:
- Maintain the same core message and structure
- Improve originality and uniqueness
- Keep the same word count approximately
- Ensure high quality and readability
- Address any specific concerns mentioned in the analysis

Rewrite the chapter now:"
    
    local result=$(smart_api_call "$user_prompt" "$system_prompt" "creative" 0.8 8192)
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result" > "$chapter_file"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# STATUS AND MONITORING
# ============================================================================

display_gemini_models_status() {
    echo "  ${CYAN}Gemini Models:${RESET}"
    
    local current_time=$(date +%s)
    local current_model="${GEMINI_MODELS[$GEMINI_MODEL_INDEX]%%:*}"
    
    # Display models by generation for better organization
    echo "    ${CYAN}📌 Gemini 2.5 Models:${RESET}"
    for model_data in "${GEMINI_MODELS[@]}"; do
        local model_name=$(echo "$model_data" | cut -d':' -f1)
        [[ "$model_name" == *"2.5"* ]] || continue
        
        _display_model_status "$model_name" "$model_data" "$current_model" "$current_time"
    done
    
    echo "    ${CYAN}📌 Gemini 2.0 Models:${RESET}"
    for model_data in "${GEMINI_MODELS[@]}"; do
        local model_name=$(echo "$model_data" | cut -d':' -f1)
        [[ "$model_name" == *"2.0"* ]] || continue
        
        _display_model_status "$model_name" "$model_data" "$current_model" "$current_time"
    done
    
    echo "    ${CYAN}📌 Gemini 1.5 Models:${RESET}"
    for model_data in "${GEMINI_MODELS[@]}"; do
        local model_name=$(echo "$model_data" | cut -d':' -f1)
        [[ "$model_name" == *"1.5"* ]] || continue
        
        _display_model_status "$model_name" "$model_data" "$current_model" "$current_time"
    done
    
    echo ""
}

# Helper function to display individual model status
_display_model_status() {
    local model_name="$1"
    local model_data="$2"
    local current_model="$3" 
    local current_time="$4"
    
    local rpm=$(echo "$model_data" | cut -d':' -f2)
    local rpd=$(echo "$model_data" | cut -d':' -f4)
    
    # Get last error time from file
    local last_error_time=$(get_model_error_time "$model_name")
    local time_since_error=$((current_time - last_error_time))
    
    # Indicator for current model
    local indicator=""
    if [[ "$model_name" == "$current_model" ]]; then
        indicator=" ${YELLOW}(active)${RESET}"
    fi
    
    if [[ $time_since_error -lt $RATE_LIMIT_COOLDOWN ]]; then
        local cooldown_remaining=$((RATE_LIMIT_COOLDOWN - time_since_error))
        echo -e "      ${YELLOW}⏳${RESET} $model_name - Cooling down (${cooldown_remaining}s remaining)$indicator"
    else
        echo -e "      ${GREEN}✅${RESET} $model_name - Ready (${rpm} req/min, ${rpd} req/day)$indicator"
    fi
}

show_provider_status() {
    echo -e "\n${CYAN}📊 Multi-Provider Status:${RESET}"
    echo "────────────────────────────────────────"
    
    if [ -n "$GEMINI_API_KEY" ]; then
        echo -e "${GREEN}✅${RESET} Gemini API - Available"
        display_gemini_models_status
    else
        echo -e "${RED}❌${RESET} Gemini API - Missing key"
    fi
    
    if [ -n "$GROQ_API_KEY" ]; then
        echo -e "${GREEN}✅${RESET} Groq API - Available"
    else
        echo -e "${RED}❌${RESET} Groq API - Missing key"
    fi
    
    if command -v ollama >/dev/null 2>&1; then
        echo -e "${GREEN}✅${RESET} Ollama - Available"
    else
        echo -e "${RED}❌${RESET} Ollama - Not installed"
    fi
    
    echo "────────────────────────────────────────"
}

test_all_providers() {
    echo "🧪 Testing all configured providers..."
    
    local test_prompt="Write a brief hello message."
    local test_system="You are a helpful assistant."
    
    # Test Gemini
    if [ -n "$GEMINI_API_KEY" ]; then
        echo -n "Testing Gemini: "
        if call_gemini_api "$test_prompt" "$test_system" 0.7 50 >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Working${RESET}"
        else
            echo -e "${RED}❌ Failed${RESET}"
        fi
    fi
    
    # Test Groq
    if [ -n "$GROQ_API_KEY" ]; then
        echo -n "Testing Groq: "
        if call_groq_api "$test_prompt" "$test_system" 0.7 50 >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Working${RESET}"
        else
            echo -e "${RED}❌ Failed${RESET}"
        fi
    fi
    
    # Test Ollama
    if command -v ollama >/dev/null 2>&1; then
        echo -n "Testing Ollama: "
        if call_ollama_api "$test_prompt" "$test_system" 0.7 50 >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Working${RESET}"
        else
            echo -e "${RED}❌ Failed${RESET}"
        fi
    fi
}

estimate_book_cost() {
    local num_chapters="${1:-12}"
    local words_per_chapter="${2:-2500}"
    
    echo "💰 Estimated Book Generation Cost:"
    echo "   Chapters: $num_chapters"
    echo "   Words per chapter: $words_per_chapter"
    echo "   Total words: $((num_chapters * words_per_chapter))"
    echo ""
    echo "   Using free tiers: $0.00"
    echo "   Using paid tiers: $0.50 - $2.00"
    echo ""
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    case "${1:-}" in
        "test")
            setup_multi_provider_system
            test_all_providers
            show_provider_status
            ;;
        "status")
            setup_multi_provider_system
            show_provider_status
            ;;
        "estimate")
            estimate_book_cost "${2:-12}" "${3:-2500}"
            ;;
        *)
            echo "Multi-Provider AI System for Book Generation"
            echo ""
            echo "Usage:"
            echo "  $0 test      - Test all providers"
            echo "  $0 status    - Show provider status"
            echo "  $0 estimate [chapters] [words] - Estimate costs"
            echo ""
            echo "This script is meant to be sourced by other scripts."
            ;;
    esac
}

# Only run main if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
