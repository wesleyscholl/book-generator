#!/bin/bash

# Multi-Provider AI System for Book Generation
# Supports Gemini, Groq, and Ollama with intelligent rate limiting

# ============================================================================
# CONFIGURATION AND GLOBALS
# ============================================================================

# Provider configuration stored in files for compatibility
PROVIDER_CONFIG_FILE="/tmp/provider_config.txt"
PROVIDER_USAGE_FILE="/tmp/provider_usage.txt"
PROVIDER_SUCCESS_FILE="/tmp/provider_success.txt"
PROVIDER_LAST_REQUEST_FILE="/tmp/provider_last_request.txt"
PROVIDER_DELAYS_FILE="/tmp/provider_delays.txt"
PROVIDER_STATUS_FILE="/tmp/provider_status.txt"

# Global settings
PREFERRED_TASK_TYPE="general"
ENABLE_COST_TRACKING=true
TOTAL_ESTIMATED_COST=0.0
FALLBACK_TO_GEMINI=true
MAX_RETRIES_PER_REQUEST=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ============================================================================
# HELPER FUNCTIONS FOR KEY-VALUE STORAGE
# ============================================================================

# Set a key-value pair in a file
set_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # Remove existing key and add new value
    grep -v "^${key}=" "$file" 2>/dev/null > "${file}.tmp" || touch "${file}.tmp"
    echo "${key}=${value}" >> "${file}.tmp"
    mv "${file}.tmp" "$file"
}

# Get a value by key from a file
get_config() {
    local file="$1"
    local key="$2"
    local default="$3"
    
    if [ -f "$file" ]; then
        local value=$(grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2-)
        echo "${value:-$default}"
    else
        echo "$default"
    fi
}

# Increment a counter in a file
increment_counter() {
    local file="$1"
    local key="$2"
    local current=$(get_config "$file" "$key" "0")
    local new_value=$((current + 1))
    set_config "$file" "$key" "$new_value"
    echo "$new_value"
}

# ============================================================================
# SYSTEM INITIALIZATION
# ============================================================================

setup_multi_provider_system() {
    
    # Create tracking directory
    mkdir -p "./multi_provider_logs"
    
    # Initialize provider configuration
    cat > "$PROVIDER_CONFIG_FILE" << EOF
gemini:gemini-1.5-flash-latest=model:0.000075:0.0003:15:1500
gemini:gemini-1.5-pro-latest=model:0.00125:0.005:2:50
groq:llama-3.1-70b-versatile=model:0.00059:0.00079:30:14400
groq:llama-3.1-8b-instant=model:0.00005:0.00008:30:14400
groq:mixtral-8x7b-32768=model:0.00024:0.00024:30:14400
ollama:llama3.2:3b=model:0:0:999:999999
ollama:llama3.2:1b=model:0:0:999:999999
ollama:qwen2.5:3b=model:0:0:999:999999
ollama:qwen2.5:1.5b=model:0:0:999:999999
ollama:phi3.5:3.8b=model:0:0:999:999999
ollama:gemma2:2b=model:0:0:999:999999
ollama:llama3.1:8b=model:0:0:500:999999
ollama:llama3.1:70b=model:0:0:20:999999
EOF
    
    # Initialize provider delays (seconds)
    cat > "$PROVIDER_DELAYS_FILE" << EOF
gemini:gemini-1.5-flash-latest=4
gemini:gemini-1.5-pro-latest=30
groq:llama-3.1-70b-versatile=2
groq:llama-3.1-8b-instant=2
groq:mixtral-8x7b-32768=2
ollama:llama3.2:3b=0.5
ollama:llama3.2:1b=0.3
ollama:qwen2.5:3b=0.5
ollama:qwen2.5:1.5b=0.3
ollama:phi3.5:3.8b=0.8
ollama:gemma2:2b=0.3
ollama:llama3.1:8b=1
ollama:llama3.1:70b=5
EOF
    
    # Initialize empty tracking files
    touch "$PROVIDER_USAGE_FILE"
    touch "$PROVIDER_SUCCESS_FILE"
    touch "$PROVIDER_LAST_REQUEST_FILE"
    touch "$PROVIDER_STATUS_FILE"
    
    # Test and initialize providers
    local available_count=0
    
    # Test Gemini providers
    for i in {1..5}; do
        local key_var="GEMINI_API_KEY"
        if [ $i -gt 1 ]; then
            key_var="GEMINI_API_KEY_$i"
        fi
        
        local api_key=$(eval echo \$$key_var)
        if [ -n "$api_key" ]; then
            if test_gemini_provider "$api_key"; then
                set_config "$PROVIDER_STATUS_FILE" "gemini:gemini-1.5-flash-latest:$i" "available"
                ((available_count++))
            else
                set_config "$PROVIDER_STATUS_FILE" "gemini:gemini-1.5-flash-latest:$i" "error"
            fi
        else
            set_config "$PROVIDER_STATUS_FILE" "gemini:gemini-1.5-flash-latest:$i" "missing_key"
        fi
    done
    
    # Test Groq
    if [ -n "$GROQ_API_KEY" ]; then
        if test_groq_provider; then
            set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-8b-instant" "available"
            set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-70b-versatile" "available"
            ((available_count++))
        else
            set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-8b-instant" "error"
            set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-70b-versatile" "error"
        fi
    else
        set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-8b-instant" "missing_key"
        set_config "$PROVIDER_STATUS_FILE" "groq:llama-3.1-70b-versatile" "missing_key"
    fi
    
    # Test Ollama
    if test_ollama_provider; then
        # Check for fast lightweight models (prioritized for M3 MacBook Air)
        if ollama list 2>/dev/null | grep -q "llama3.2:1b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:1b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:1b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "llama3.2:3b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:3b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:3b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "qwen2.5:1.5b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:1.5b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:1.5b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "qwen2.5:3b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:3b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:3b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "phi3.5:3.8b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:phi3.5:3.8b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:phi3.5:3.8b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "gemma2:2b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:gemma2:2b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:gemma2:2b" "not_installed"
        fi
        
        # Check for standard models
        if ollama list 2>/dev/null | grep -q "llama3.1:8b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:8b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:8b" "not_installed"
        fi
        
        if ollama list 2>/dev/null | grep -q "llama3.1:70b"; then
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:70b" "available"
        else
            set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:70b" "not_installed"
        fi
        
        ((available_count++))
    else
        # Set all Ollama models as offline if service is not running
        set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:1b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.2:3b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:1.5b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:qwen2.5:3b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:phi3.5:3.8b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:gemma2:2b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:8b" "offline"
        set_config "$PROVIDER_STATUS_FILE" "ollama:llama3.1:70b" "offline"
    fi
    
    echo "✅ Initialization complete. $available_count provider groups available."
    
    if [ $available_count -eq 0 ]; then
        echo "❌ No providers available! Check your configuration."
        return 1
    fi
    
    return 0
}

# ============================================================================
# PROVIDER TESTING FUNCTIONS
# ============================================================================

test_gemini_provider() {
    local api_key="$1"
    local test_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent"
    
    local payload=$(cat << EOF
{
    "contents": [{
        "parts": [{"text": "Hello"}]
    }],
    "generationConfig": {
        "maxOutputTokens": 10
    }
}
EOF
)
    
    local response=$(curl -s -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $api_key" \
        -d "$payload" \
        "$test_url" 2>/dev/null | tail -n1)
    
    [ "$response" = "200" ]
}

test_groq_provider() {
    local test_url="https://api.groq.com/openai/v1/chat/completions"
    
    local payload=$(cat << EOF
{
    "messages": [{"role": "user", "content": "Hello"}],
    "model": "llama-3.1-8b-instant",
    "max_tokens": 10
}
EOF
)
    
    local response=$(curl -s -w "%{http_code}" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$test_url" 2>/dev/null | tail -n1)
    
    [ "$response" = "200" ]
}

test_ollama_provider() {
    if ! command -v ollama >/dev/null 2>&1; then
        return 1
    fi
    
    # Try with the smallest available model first
    for model in "llama3.2:1b" "qwen2.5:1.5b" "gemma2:2b" "llama3.2:3b" "llama3.1:8b"; do
        local response=$(curl -s --max-time 10 "http://localhost:11434/api/generate" \
            -d "{\"model\": \"$model\", \"prompt\": \"Hi\", \"stream\": false}" 2>/dev/null)
        
        if echo "$response" | grep -q '"response"'; then
            return 0
        fi
    done
    
    return 1
}

# ============================================================================
# SMART API SELECTION AND CALLING
# ============================================================================

smart_api_call() {
    local prompt="$1"
    local system_prompt="${2:-You are a helpful AI assistant.}"
    local task_type="${3:-general}"
    local temperature="${4:-0.7}"
    local max_tokens="${5:-4096}"
    local max_retries="${6:-$MAX_RETRIES_PER_REQUEST}"
    
    local providers=()
    
    # Select providers based on task type
    case "$task_type" in
        "fast")
            providers=("ollama:llama3.2:1b" "ollama:qwen2.5:1.5b" "ollama:gemma2:2b" "groq:llama-3.1-8b-instant" "ollama:llama3.2:3b" "gemini:gemini-1.5-flash-latest")
            ;;
        "creative")
            providers=("ollama:llama3.2:1b" "ollama:llama3.2:3b" "ollama:qwen2.5:3b" "groq:llama-3.1-70b-versatile" "ollama:phi3.5:3.8b" "gemini:gemini-1.5-pro-latest" "ollama:llama3.1:8b")
            ;;
        "analytical")
            providers=("gemini:gemini-1.5-pro-latest" "ollama:qwen2.5:3b" "groq:llama-3.1-70b-versatile" "ollama:llama3.2:3b" "ollama:llama3.1:8b")
            ;;
        *)
            providers=("ollama:llama3.2:3b" "ollama:qwen2.5:1.5b" "gemini:gemini-1.5-flash-latest" "groq:llama-3.1-8b-instant" "ollama:llama3.1:8b")
            ;;
    esac
    
    # Try each provider
    for provider_model in "${providers[@]}"; do
        if is_provider_available "$provider_model"; then
            echo "🤖 Trying $provider_model..." >&2
            
            local result=""
            if call_provider "$provider_model" "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
                echo "$result"
                return 0
            fi
        fi
    done
    
    # # Fallback to any available Gemini if enabled
    # if [ "$FALLBACK_TO_GEMINI" = "true" ]; then
    #     echo "🔄 Falling back to any available Gemini provider..." >&2
    #     for i in {1..5}; do
    #         local key_var="GEMINI_API_KEY"
    #         if [ $i -gt 1 ]; then
    #             key_var="GEMINI_API_KEY_$i"
    #         fi
            
    #         if [ -n "${!key_var}" ] && is_provider_available "gemini:gemini-1.5-flash-latest:$i"; then
    #             if call_gemini_provider "gemini-1.5-flash-latest" "$prompt" "$system_prompt" "$temperature" "$max_tokens" "${!key_var}"; then
    #                 echo "$result"
    #                 return 0
    #             fi
    #         fi
    #     done
    # fi
    
    echo "❌ All providers failed" >&2
    return 1
}

# ============================================================================
# PROVIDER-SPECIFIC CALLING FUNCTIONS
# ============================================================================

call_provider() {
    local provider_model="$1"
    local prompt="$2"
    local system_prompt="$3"
    local temperature="$4"
    local max_tokens="$5"
    
    local provider=$(echo "$provider_model" | cut -d: -f1)
    local model=$(echo "$provider_model" | cut -d: -f2)
    
    # Check rate limits
    if ! check_rate_limit "$provider_model"; then
        echo "⏳ Rate limit reached for $provider_model" >&2
        return 1
    fi
    
    case "$provider" in
        "gemini")
            call_gemini_provider "$model" "$prompt" "$system_prompt" "$temperature" "$max_tokens"
            ;;
        "groq")
            call_groq_provider "$model" "$prompt" "$system_prompt" "$temperature" "$max_tokens"
            ;;
        "ollama")
            call_ollama_provider "$model" "$prompt" "$system_prompt" "$temperature" "$max_tokens"
            ;;
        *)
            echo "❌ Unknown provider: $provider" >&2
            return 1
            ;;
    esac
}

call_gemini_provider() {
    local model="$1"
    local prompt="$2"
    local system_prompt="$3"
    local temperature="$4"
    local max_tokens="$5"
    local api_key="${6:-$GEMINI_API_KEY}"
    
    local url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent"
    
    local payload=$(jq -n \
        --arg system "$system_prompt" \
        --arg prompt "$prompt" \
        --arg temp "$temperature" \
        --arg max "$max_tokens" \
        '{
            "contents": [{
                "parts": [{"text": ($system + "\n\n" + $prompt)}]
            }],
            "generationConfig": {
                "temperature": ($temp | tonumber),
                "maxOutputTokens": ($max | tonumber)
            }
        }')
    
    local response=$(curl -s \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $api_key" \
        -d "$payload" \
        "$url")
    
    if echo "$response" | jq -e '.candidates[0].content.parts[0].text' >/dev/null 2>&1; then
        result=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text')
        record_provider_usage "gemini:$model" "success"
        return 0
    else
        record_provider_usage "gemini:$model" "error"
        echo "❌ Gemini error: $response" >&2
        return 1
    fi
}

call_groq_provider() {
    local model="$1"
    local prompt="$2"
    local system_prompt="$3"
    local temperature="$4"
    local max_tokens="$5"
    
    local url="https://api.groq.com/openai/v1/chat/completions"
    
    local payload=$(jq -n \
        --arg model "$model" \
        --arg system "$system_prompt" \
        --arg prompt "$prompt" \
        --arg temp "$temperature" \
        --arg max "$max_tokens" \
        '{
            "messages": [
                {"role": "system", "content": $system},
                {"role": "user", "content": $prompt}
            ],
            "model": $model,
            "temperature": ($temp | tonumber),
            "max_tokens": ($max | tonumber)
        }')
    
    local response=$(curl -s \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")
    
    if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
        result=$(echo "$response" | jq -r '.choices[0].message.content')
        record_provider_usage "groq:$model" "success"
        return 0
    else
        record_provider_usage "groq:$model" "error"
        echo "❌ Groq error: $response" >&2
        return 1
    fi
}

call_ollama_provider() {
    local model="$1"
    local prompt="$2"
    local system_prompt="$3"
    local temperature="$4"
    local max_tokens="$5"
    
    local url="http://localhost:11434/api/generate"
    local full_prompt="$system_prompt\n\n$prompt"
    
    local payload=$(jq -n \
        --arg model "$model" \
        --arg prompt "$full_prompt" \
        --arg temp "$temperature" \
        '{
            "model": $model,
            "prompt": $prompt,
            "stream": false,
            "options": {
                "temperature": ($temp | tonumber),
                "max_tokens": ($max_tokens | tonumber)
            }
        }')
    
    local response=$(curl -s -m 120 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")
    
    if echo "$response" | jq -e '.response' >/dev/null 2>&1; then
        result=$(echo "$response" | jq -r '.response')
        record_provider_usage "ollama:$model" "success"
        return 0
    else
        record_provider_usage "ollama:$model" "error"
        echo "❌ Ollama error: $response" >&2
        return 1
    fi
}

# ============================================================================
# RATE LIMITING AND USAGE TRACKING
# ============================================================================

check_rate_limit() {
    local provider_model="$1"
    local current_time=$(date +%s)
    local last_request=$(get_config "$PROVIDER_LAST_REQUEST_FILE" "$provider_model" "0")
    local delay=$(get_config "$PROVIDER_DELAYS_FILE" "$provider_model" "5")
    
    local time_since_last=$((current_time - last_request))
    
    if [ $time_since_last -lt $delay ]; then
        local wait_time=$((delay - time_since_last))
        echo "⏳ Rate limiting: waiting ${wait_time}s for $provider_model" >&2
        sleep $wait_time
    fi
    
    set_config "$PROVIDER_LAST_REQUEST_FILE" "$provider_model" "$current_time"
    return 0
}

record_provider_usage() {
    local provider_model="$1"
    local status="$2"
    
    increment_counter "$PROVIDER_USAGE_FILE" "$provider_model"
    
    if [ "$status" = "success" ]; then
        increment_counter "$PROVIDER_SUCCESS_FILE" "$provider_model"
    fi
    
    # Log to file
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$provider_model,$status" >> "./multi_provider_logs/usage.log"
}

is_provider_available() {
    local provider_model="$1"
    local status=$(get_config "$PROVIDER_STATUS_FILE" "$provider_model" "unavailable")
    
    [ "$status" = "available" ]
}

# ============================================================================
# BOOK GENERATION SPECIFIC FUNCTIONS
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
# MONITORING AND DISPLAY FUNCTIONS
# ============================================================================

show_provider_status() {
    echo -e "\n${CYAN}📊 Provider Status Summary:${RESET}"
    echo "────────────────────────────────────────────────────────"
    
    # Read all providers from status file
    if [ -f "$PROVIDER_STATUS_FILE" ]; then
        while IFS='=' read -r provider_model status; do
            if [ -n "$provider_model" ] && [ -n "$status" ]; then
                local usage=$(get_config "$PROVIDER_USAGE_FILE" "$provider_model" "0")
                local success=$(get_config "$PROVIDER_SUCCESS_FILE" "$provider_model" "0")
                local success_rate=0
                
                if [ $usage -gt 0 ]; then
                    success_rate=$((success * 100 / usage))
                fi
                
                case "$status" in
                    "available")
                        echo -e "${GREEN}✅${RESET} $provider_model - Used: $usage (${success_rate}% success)"
                        ;;
                    "error"|"offline")
                        echo -e "${RED}❌${RESET} $provider_model - $status"
                        ;;
                    "missing_key")
                        echo -e "${YELLOW}🔑${RESET} $provider_model - API key missing"
                        ;;
                    "not_installed")
                        echo -e "${YELLOW}📦${RESET} $provider_model - Model not installed"
                        ;;
                esac
            fi
        done < "$PROVIDER_STATUS_FILE"
    fi
    
    echo "────────────────────────────────────────────────────────"
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

test_all_providers() {
    echo "🧪 Testing all configured providers..."
    
    local test_prompt="Write a brief hello message."
    local test_system="You are a helpful assistant."
    
    # Test priority models for M3 MacBook Air
    for provider_model in "ollama:llama3.2:1b" "ollama:qwen2.5:1.5b" "ollama:gemma2:2b" "gemini:gemini-1.5-flash-latest" "groq:llama-3.1-8b-instant"; do
        echo -n "Testing $provider_model: "
        
        if call_provider "$provider_model" "$test_prompt" "$test_system" 0.7 50 >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Working${RESET}"
        else
            echo -e "${RED}❌ Failed${RESET}"
        fi
        
        sleep 1
    done
}

# ============================================================================
# MAIN FUNCTION FOR STANDALONE TESTING
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
