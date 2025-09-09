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

# Smart API call with task-specific model selection and fallbacks
function smart_api_call() {
    # Expected canonical call signature used across the project:
    # smart_api_call <prompt> <system_prompt> <task_type> <temperature> <max_tokens> <max_retries> <model>

    local prompt="$1" # User prompt
    local system_prompt="$2" # System prompt
    local task_type="$3" # Task type
    local temperature="$4" # Temperature
    local max_tokens="$5" # Max tokens
    local max_retries="$6" # Max retries
    local model="$7" # Model

    # Debug output (commented out to avoid including prompt in response)
    # echo "$prompt $system_prompt $task_type $temperature $max_tokens $max_retries $model" >&2

    # Default system prompt if none provided
    local default_system_prompt="Be helpful, accurate, and clear."

    # Known short task type tokens (used by callers when they omit system_prompt)
    local TASK_TYPES=("analytical" "creative" "plagiarism_check" "chapter_rewrite" "rewrite" "quality_check" "outline" "continuation" "general" "rewrite" "plagiarism_check" "summary")

    # Helper to check if a value is a known task type
    is_task_type() {
        local v="$1"
        for t in "${TASK_TYPES[@]}"; do
            if [ "$v" = "$t" ]; then
                return 0
            fi
        done
        return 1
    }
    
    # Try to fetch a response with multiple fallback options
    local success=false
    local max_retries=3
    local current_attempt=1
    
    # Prioritize faster/smaller models for better response times
    # Start with fast small models and progress to larger ones if needed
    local fallback_models=("llama3:8b" "llama3.2:1b" "llama3:latest" "gemma:7b" "tinyllama:latest" "mixtral:latest" "llama2:latest")
    
    # If model is specified, use it first, otherwise try default models
    # if [ -n "$model" ]; then
    #     echo "🤖 Using specified model: $model" >&2
    #     # call_ollama_api expects: prompt, system_prompt, task_type, temperature, max_tokens, model_name
    #     if call_ollama_api "$prompt" "$system_prompt" "$task_type" "$temperature" "$max_tokens" "$max_retries" "$model"; then
    #         success=true
    #     fi
    # fi

    if [ -n "$GEMINI_API_KEY" ]; then
        echo "🔄 Trying Gemini API (attempt $current_attempt/$max_retries)" >&2
        if call_gemini_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
            success=true
        fi
        sleep 1
    fi

    # Ensure values are numeric for comparison
    if ! [[ "$current_attempt" =~ ^[0-9]+$ ]]; then
        echo "⚠️ Invalid current_attempt value: $current_attempt, setting to 1" >&2
        current_attempt=1
    fi
    
    if ! [[ "$max_retries" =~ ^[0-9]+$ ]]; then
        echo "⚠️ Invalid max_retries value: $max_retries, setting to 3" >&2
        max_retries=3
    fi
    
    while [ "$success" = false ] && [ $current_attempt -le $max_retries ]; do
        
        # If still not successful, try Gemini
        if [ "$success" = false ] && [ -n "$GEMINI_API_KEY" ]; then
            echo "🔄 Trying Gemini API (attempt $current_attempt/$max_retries)" >&2
            if call_gemini_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
                success=true
                break
            fi
            sleep 1
        fi

        if [ "$success" = false ] && [ "${#fallback_models[@]}" -gt 0 ]; then
            # Try each fallback model in turn
            for fallback_model in "${fallback_models[@]}"; do
                echo "🔄 Trying fallback model: $fallback_model (attempt $current_attempt/$max_retries)" >&2
                if call_ollama_api "$prompt" "$system_prompt" "$task_type" "$temperature" "$max_tokens" "$max_retries" "$fallback_model"; then
                    success=true
                    break
                fi
                sleep 1
            done
        fi

        # If still not successful, try Groq
        if [ "$success" = false ] && [ -n "$GROQ_API_KEY" ]; then
            echo "🔄 Trying Groq API (attempt $current_attempt/$max_retries)" >&2
            if call_groq_api "$prompt" "$system_prompt" "$temperature" "$max_tokens"; then
                success=true
                break
            fi
            sleep 1
        fi
        
        # Increment attempt counter
        current_attempt=$((current_attempt + 1))
        
        # If we're going to try again, wait a moment
        if [ "$success" = false ] && [ $current_attempt -le $max_retries ]; then
            sleep 2
        fi
    done
    
    # If we couldn't get a response from any provider, return an error
    if [ "$success" = false ]; then
        echo "❌ All AI providers failed to respond after $max_retries attempts" >&2
        return 1
    fi
    
    return 0
}

# Gemini models with rate limits
# Model array format: "model_name:RPM:TPM:RPD"
GEMINI_MODELS=(
    # Gemini 2.5 models (newest, try these first)
    # "gemini-2.5-pro:5:250000:100"
    
    "gemini-2.5-flash:10:250000:250"
    "gemini-2.0-flash:15:1000000:200"
    "gemini-2.5-flash-lite:15:250000:1000"
    "gemini-2.0-flash-lite:30:1000000:200"

    "gemini-1.5-flash:10:250000:250"

    "gemini-1.5-pro:5:250000:100" 
    
    # Gemini 2.0 models
    
    # Gemini 1.5 models (fallback)
    
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

    API_KEY="${GEMINI_API_KEY}"
    local top_k=40
    local top_p=0.9
    
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

        echo "Max Tokens: $max_tokens" >&2
        echo "➡️ Trying Gemini model: $model_name" >&2
        local url="https://generativelanguage.googleapis.com/v1beta/models/${model_name}:generateContent"
        echo "📡 Sending request to: $url" >&2
        local full_prompt="$system_prompt\n\n$prompt"
        
        local payload=$(jq -n \
            --arg prompt "$prompt" \
            --argjson temp "$temperature" \
            --argjson maxtokens "$max_tokens" \
            --argjson topk "$top_k" \
            --argjson topp "$top_p" \
            '{
                "contents": [{
                    "role": "user",
                    "parts": [{"text": $prompt}]
                }],
                "generationConfig": {
                    "temperature": ($temp | tonumber),
                    "maxOutputTokens": ($maxtokens | tonumber),
                    "topK": ($topk | tonumber),
                    "topP": ($topp | tonumber)
                }
            }')

    echo -e "🤖 Generating response with Gemini..." >&2

    # Make the API call
    local response=$(curl -s -X POST --max-time 120 \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $API_KEY" \
        -d "$payload" \
        "$url")
    local curl_exit_code=$?

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

# Ollama API call with improved context handling
call_ollama_api() {
    local prompt="$1" # User prompt
    local system_prompt="$2" # System prompt
    local task_type="$3" # Task type
    local temperature="$4" # Temperature
    local max_tokens="$5" # Max tokens
    local max_retries="$6" # Max retries
    local model="$7" # Model

    local LOG_FILE="multi_provider_logs/debug.log"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "DEBUG: call_ollama_api started with prompt length: ${#prompt}, system_prompt length: ${#system_prompt}" >> "$LOG_FILE"
    
    # Validate temperature is a number and fix common format issues
    # Handle missing or empty temperature
    if [ -z "$temperature" ]; then
        echo "⚠️ Warning: Empty temperature value, defaulting to 0.7" >&2
        temperature=0.7
    else
        # First clean up the temperature value - convert '.65' to '0.65'
        if [[ "$temperature" =~ ^\.[0-9]+$ ]]; then
            temperature="0$temperature"
            echo "⚠️ Note: Reformatted temperature from '.$temperature' to '$temperature'" >&2
        fi
        
        # Now validate that it's a proper number
        if ! [[ "$temperature" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "⚠️ Warning: Invalid temperature value '$temperature', defaulting to 0.7" >&2
            temperature=0.7
        fi
        
        # Ensure temperature is within valid range (0-2)
        if (( $(echo "$temperature > 2.0" | bc -l) )); then
            echo "⚠️ Warning: Temperature too high ($temperature), capping at 2.0" >&2
            temperature=2.0
        elif (( $(echo "$temperature < 0.0" | bc -l) )); then
            echo "⚠️ Warning: Temperature too low ($temperature), setting to 0.1" >&2
            temperature=0.1
        fi
    fi
    
    # Choose appropriate model based on availability
    if ! ollama list 2>/dev/null | grep -q "$model_name"; then
        # First try popular high-quality models
        local fallback_models=(
            "llama3.1:8b"
            "phi3:3.8b"
            "phi4-mini:3.8b"
            "gemma3:4b"
            "gemma2:2b"
            "llama3.2:1b"
            "qwen2.5:1.5b"
            "granite3:3b"
        )
        
        for fallback in "${fallback_models[@]}"; do
            if ollama list 2>/dev/null | grep -q "$fallback"; then
                model_name="$fallback"
                echo "⚠️ Model '$5' not found, using fallback: $model_name" >&2
                break
            fi
        done
    fi
    
    # Calculate optimal context window based on model and prompt size
    local prompt_length=${#prompt}
    local system_length=${#system_prompt}
    local total_length=$((prompt_length + system_length + 200)) # Adding buffer
    
    # Set context window based on model capabilities
    local ctx_window=4096
    local num_batch=128
    local stream=false
    local top_k=40
    local top_p=0.9
    
    # Adjust context window and batch size based on model
    if [[ "$model_name" == *"llama3.1:8b"* ]]; then
        ctx_window=8192
        num_batch=256
    elif [[ "$model_name" == *"phi3:3.8b"* ]] || [[ "$model_name" == *"phi4-mini"* ]]; then
        ctx_window=4096
        num_batch=192
    elif [[ "$model_name" == *"gemma3"* ]]; then
        ctx_window=8192
        num_batch=256
    elif [[ "$model_name" == *"granite"* ]]; then
        ctx_window=16384
        num_batch=512
    fi

    # Latency-focused overrides for specific models
    # These reduce context, lower batch sizes, enable streaming, and tighten sampling to reduce wall-clock time
    if [[ "$model_name" == *"qwen2:7b"* ]] || [[ "$model_name" == *"qwen2.5"* ]] || [[ "$model_name" == *"qwen2.5:14b"* ]]; then
        ctx_window=4096
        num_batch=32
        stream=true
        top_k=20
        top_p=0.95
        # Cap long responses by default to avoid long-running generations
        if [ -z "$max_tokens" ] || [ "$max_tokens" -gt 2048 ]; then
            max_tokens=2048
        fi
    fi

    if [[ "$model_name" == *"gemma2:9b"* ]] || [[ "$model_name" == *"gemma2"* ]]; then
        ctx_window=4096
        num_batch=48
        stream=true
        top_k=30
        top_p=0.95
        if [ -z "$max_tokens" ] || [ "$max_tokens" -gt 4096 ]; then
            max_tokens=4096
        fi
    fi

    # Write message directly without using grep in pipe
    echo -e "🖥️  Using local Ollama model: $model with temperature $temperature" >&2
    echo "DEBUG: Using model: $model_name, temperature: $temperature, max_tokens: $max_tokens, ctx: $ctx_window" >> "$LOG_FILE"
    
    local url="http://localhost:11434/api/generate"
    
    # Format prompts according to model's preferred format
    local formatted_prompt=""
    if [[ "$model_name" == *"llama"* ]]; then
        # LLaMA format
        formatted_prompt="<|system|>\n$system_prompt\n\n<|user|>\n$prompt\n\n<|assistant|>"
    elif [[ "$model_name" == *"phi"* ]]; then
        # Phi format
        formatted_prompt="<|system|>\n$system_prompt\n\n<|user|>\n$prompt\n\n<|assistant|>"
    elif [[ "$model_name" == *"gemma"* ]]; then
        # Gemma format
        formatted_prompt="<start_of_turn>system\n$system_prompt<end_of_turn>\n<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model"
    else
        # Default/generic format
        formatted_prompt="System: $system_prompt\n\nUser: $prompt\n\nAssistant:"
    fi
    
    echo "DEBUG: Using formatted prompt length: ${#formatted_prompt}" >> "$LOG_FILE"
    
    # Use jq to properly format the JSON payload
    local payload=$(jq -n \
        --arg model "$model" \
        --arg prompt "$formatted_prompt" \
        --argjson temp "$temperature" \
        --argjson max_tokens "$max_tokens" \
        --argjson ctx_window "$ctx_window" \
        --argjson num_batch "$num_batch" \
        --argjson stream_val "$stream" \
        --argjson topk "$top_k" \
        --argjson topp "$top_p" \
        '{
            "model": $model,
            "prompt": $prompt,
            "stream": ($stream_val == true),
            "options": {
                "temperature": $temp,
                "max_tokens": $max_tokens,
                "top_k": $topk,
                "top_p": $topp,
                "num_batch": $num_batch,
                "num_ctx": $ctx_window
            }
        }')
    
    echo "DEBUG: About to make curl request to Ollama" >> "$LOG_FILE"
    
    # Command line for Ollama - verbose debug
    # local response=$(ollama generate --model "$model" --prompt "$formatted_prompt" --temperature "$temperature" --max_tokens "$max_tokens" --ctx_window "$ctx_window" --num_batch "$num_batch" --stream "$stream" --top_k "$top_k" --top_p "$top_p")

    # Make the API call with longer timeout for bigger models
    local response=$(curl -s --max-time 300 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url")
    local curl_exit_code=$?
    
    echo "DEBUG: curl completed with exit code: $curl_exit_code" >> "$LOG_FILE"
    echo "DEBUG: Response length: ${#response} characters" >> "$LOG_FILE"
    
    # Check for successful response
    if echo "$response" | jq -e '.response' >/dev/null 2>&1; then
        local extracted_response=$(echo "$response" | jq -r '.response')
        
        # BUGFIX: Remove the original prompt from the response
        # The issue was that Ollama sometimes includes the original prompt in the response
        # This fix ensures we only get the generated content, not the prompt
        
        # Remove system and user prompt parts that might be included
        extracted_response=$(echo "$extracted_response" | sed -E 's/^.*<\|assistant\|>//g')
        extracted_response=$(echo "$extracted_response" | sed -E 's/^.*<start_of_turn>model//g')
        extracted_response=$(echo "$extracted_response" | sed -E 's/^.*Assistant://g')
        
        # Remove the original prompt text if it appears at the beginning
        if [[ "$extracted_response" == *"$prompt"* ]]; then
            extracted_response=$(echo "$extracted_response" | sed "s|$prompt||g")
        fi
        
        # Remove any remaining system/user markers
        extracted_response=$(echo "$extracted_response" | sed -E 's/<\|system\|>.*<\|user\|>//g')
        extracted_response=$(echo "$extracted_response" | sed -E 's/<\|user\|>.*<\|assistant\|>//g')
        
        echo "DEBUG: Successfully extracted response, length: ${#extracted_response}" >> "$LOG_FILE"
        echo -e "${GREEN}✓ Generated with $model_name${RESET}" >&2
        echo "$extracted_response"
        return 0
    else
        # Try to provide better error info
        local error_message=$(echo "$response" | jq -r '.error // "Unknown error"')
        echo "❌ Ollama API error with $model_name: $error_message" >&2
        echo "DEBUG: Failed to extract .response from JSON, error: $error_message" >> "$LOG_FILE"
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
    
    local system_prompt="You are an expert book author and publishing professional tasked with creating high-quality, commercially viable books for publication on KDP and other platforms. Your goal is to produce engaging, well-structured, and professionally written content that readers will find valuable and enjoyable.

Create detailed book outlines that will guide the generation of 20,000-25,000 word books with 12-15 chapters of 2,500-3,000 words each.

When creating outlines, always format chapter titles clearly as:
Chapter 1: [Title]
Chapter 2: [Title]
etc.

Include comprehensive chapter summaries that will guide detailed content generation. DO NOT include any markdown characters or formatting other than numbered lists."
    
    local user_prompt="Create a detailed outline for a ${genre} book about '${topic}' targeting ${audience}.

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
    local words_per_chapter="${2:-2200}"
    
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
            estimate_book_cost "${2:-12}" "${3:-2200}"
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
