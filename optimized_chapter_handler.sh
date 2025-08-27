#!/bin/bash

# Improved chapter handling functions to properly handle chapter length requirements

# Function to calculate tokens required for chapter extension
# Formula: MAX_TOKENS = (500 minimum word length * 1.25) - (current chapter word length * 1.25) 
#          + (system prompt word length * 1.25) + (user prompt word length * 1.25) + 250
calculate_chapter_extension_tokens() {
    local current_words="$1"
    local min_words="${2:-500}"
    local system_prompt_words="${3:-50}"  # Estimated system prompt length
    local user_prompt_words="${4:-200}"   # Estimated user prompt length
    
    # Calculate using formula
    local tokens=$(( (min_words * 125 / 100) - (current_words * 125 / 100) + 
                     (system_prompt_words * 125 / 100) + (user_prompt_words * 125 / 100) + 250 ))
    
    # Ensure we don't go below a reasonable minimum
    if [ "$tokens" -lt 500 ]; then
        tokens=500
    fi
    
    echo "$tokens"
}

# Function to review and process chapter based on length
process_chapter_by_length() {
    local chapter_file="$1"
    local min_words="${2:-2200}"
    local max_words="${3:-2500}"
    
    # Get current word count
    local current_word_count=$(wc -w < "$chapter_file" | tr -d ' ')
    echo "📊 Current word count: $current_word_count words"
    
    if [ "$current_word_count" -ge "$min_words" ]; then
        # Chapter is already long enough, just review for quality
        echo "✅ Chapter meets minimum word count requirement ($current_word_count words)"
        # review_chapter_quality "$chapter_file"
        return 0
    else
        # Chapter needs extension
        echo "⚠️ Chapter below minimum word count: $current_word_count/$min_words words"
        extend_chapter_to_min_length "$chapter_file" "$min_words" "$max_words"
        
        # Check if extension succeeded
        local final_word_count=$(wc -w < "$chapter_file" | tr -d ' ')
        if [ "$final_word_count" -lt "$min_words" ]; then
            echo "⚠️ Chapter still below minimum after extension: $final_word_count/$min_words words"
            echo "🔄 Trying one final extension attempt..."
            extend_chapter_to_min_length "$chapter_file" "$min_words" "$max_words" "final"
        fi
        
        return 0
    fi
}

# Function to review chapter quality without changing length
review_chapter_quality() {
    local chapter_file="$1"
    
    echo "🔍 Reviewing chapter quality..."
    local chapter_content=$(cat "$chapter_file")
    
    # Create a review prompt that doesn't change length
    local review_prompt="Review and improve this chapter for quality without significantly changing its length. 

Focus on:
- Improving flow and readability
- Enhancing clarity and precision
- Fixing grammar and style issues
- Ensuring consistency in tone and voice
- Strengthening arguments and examples

DO NOT:
- Add significant new content
- Remove substantial content
- Change the structure or organization

Return the complete revised chapter with the same approximate word count.

CHAPTER CONTENT:
$chapter_content"

    local review_system_prompt="You are an expert book editor who improves content quality without changing length."
    
    # Call API to review the chapter
    echo "🤖 Generating quality improvements..."
    local reviewed_content=$(smart_api_call "$review_prompt" "$review_system_prompt" "quality_check" 0.7 3000 1 "llama3.2:1b")
    
    # Check if API call was successful
    if [ $? -eq 0 ] && [ -n "$reviewed_content" ]; then
        # Clean up the content
        reviewed_content=$(clean_llm_output "$reviewed_content")
        
        # Save the reviewed chapter
        local backup_file="${chapter_file}.before_review"
        cp "$chapter_file" "$backup_file"
        echo "$reviewed_content" > "$chapter_file"
        echo "✅ Quality review completed and saved"
        
        # Final word count
        local final_word_count=$(wc -w < "$chapter_file" | tr -d ' ')
        echo "📊 Final word count after review: $final_word_count words"
    else
        echo "⚠️ Quality review failed, keeping original chapter"
    fi
}

# Function to extend chapter to meet minimum length
extend_chapter_to_min_length() {
    local chapter_file="$1"
    local min_words="$2"
    local max_words="$3"
    local attempt_type="${4:-standard}"
    
    # Get current content and word count
    local chapter_content=$(cat "$chapter_file")
    local current_word_count=$(wc -w < "$chapter_file" | tr -d ' ')
    local words_needed=$((min_words - current_word_count))
    
    echo "🔍 Extending chapter by approximately $words_needed words..."
    
    # Calculate tokens based on our formula
    local extension_tokens=$(calculate_chapter_extension_tokens "$current_word_count" "$min_words")
    echo "ℹ️ Using $extension_tokens tokens for chapter extension"
    
    # Create an extension prompt
    local extension_prompt="Extend this chapter to reach a minimum of ${min_words} words (currently ${current_word_count} words).

REQUIREMENTS:
- Add approximately ${words_needed} more words
- Expand existing ideas with more depth, examples, and explanations
- Maintain the same style, tone, and voice as the original
- Add substantive content, not just filler text
- Integrate new content seamlessly with existing content
- Return the COMPLETE chapter with your additions integrated

CHAPTER CONTENT:
$chapter_content"

    local extension_system_prompt="You are an expert book author who excels at extending chapters with substantive, valuable content."
    
    # Use a more capable model for the final attempt
    local model="llama3.2:1b"
    if [ "$attempt_type" = "final" ]; then
        model="gemma2:2b"
        # Increase token count by 20% for final attempt
        extension_tokens=$(( extension_tokens * 120 / 100 ))
    fi
    
    # Call API to extend the chapter
    echo "🤖 Generating extended content using model: $model..."
    local extended_content=$(smart_api_call "$extension_prompt" "$extension_system_prompt" "chapter_extension" 0.7 "$extension_tokens" 1 "$model")
    
    # Check if API call was successful
    if [ $? -eq 0 ] && [ -n "$extended_content" ]; then
        # Clean up the content
        extended_content=$(clean_llm_output "$extended_content")
        
        # Save the extended chapter
        local backup_file="${chapter_file}.before_extension"
        cp "$chapter_file" "$backup_file"
        echo "$extended_content" > "$chapter_file"
        echo "✅ Chapter extension completed and saved"
        
        # Final word count
        local final_word_count=$(wc -w < "$chapter_file" | tr -d ' ')
        echo "📊 Final word count after extension: $final_word_count words"
        
        # Check if we're still below minimum
        if [ "$final_word_count" -lt "$min_words" ] && [ "$attempt_type" != "final" ]; then
            echo "⚠️ Still below minimum word count: $final_word_count/$min_words words"
        elif [ "$final_word_count" -ge "$min_words" ]; then
            echo "✅ Successfully extended chapter to meet minimum word count"
        fi
    else
        echo "⚠️ Chapter extension failed, keeping original chapter"
    fi
}
