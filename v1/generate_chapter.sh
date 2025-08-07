#!/bin/bash

# Generate individual chapters using existing outline and context
# Usage: ./generate_chapter.sh outline_file.md chapter_number "Chapter Title"

set -e

# Configuration
API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Input validation
if [ $# -ne 3 ]; then
    echo "Usage: $0 outline_file.md chapter_number 'Chapter Title'"
    echo "Example: $0 book_outline_20241201_143022.md 1 'Introduction to Personal Finance'"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable not set"
    exit 1
fi

OUTLINE_FILE="$1"
CHAPTER_NUM="$2"
CHAPTER_TITLE="$3"

if [ ! -f "$OUTLINE_FILE" ]; then
    echo "Error: Outline file '$OUTLINE_FILE' not found"
    exit 1
fi

# Read outline and any existing chapters
OUTLINE_CONTENT=$(cat "$OUTLINE_FILE")

# Check for existing chapters
BOOK_DIR=$(dirname "$OUTLINE_FILE")
EXISTING_CHAPTERS=""

for i in $(seq 1 $((CHAPTER_NUM - 1))); do
    CHAPTER_FILE="${BOOK_DIR}/chapter_${i}.md"
    if [ -f "$CHAPTER_FILE" ]; then
        CHAPTER_CONTENT=$(cat "$CHAPTER_FILE")
        EXISTING_CHAPTERS="${EXISTING_CHAPTERS}\n\n=== CHAPTER $i ===\n${CHAPTER_CONTENT}"
    fi
done

# System prompt (same as before)
SYSTEM_PROMPT=$(cat << 'EOF'
You are an expert book author and publishing professional tasked with creating high-quality, commercially viable books for publication on KDP and other platforms. Your goal is to produce engaging, well-structured, and professionally written content that readers will find valuable and enjoyable.

## Core Quality Standards

**Writing Excellence:**
- Write in clear, engaging prose appropriate for your target audience
- Maintain consistent voice, tone, and style throughout
- Use varied sentence structure and rich vocabulary
- Show don't tell - use vivid descriptions and concrete examples
- Create compelling hooks at chapter beginnings and satisfying conclusions

**Professional Standards:**
- Target 30,000 words total (approximately 120-150 pages)
- Maintain publishing industry standards for formatting and structure
- Ensure content is original, informative, and adds genuine value
- Write with commercial appeal while maintaining literary quality

## Structural Requirements

**Book Organization:**
- Create a logical, progressive structure with 12-15 chapters
- Each chapter should be 2,000-2,500 words
- Include compelling chapter titles that promise value
- Maintain narrative flow and thematic coherence throughout
- End chapters with natural transitions or cliffhangers when appropriate

**Content Development:**
- Develop ideas thoroughly with supporting details and examples
- Maintain factual accuracy and cite credible sources when needed
- Include practical applications, case studies, or actionable insights
- Balance information density with readability

## Character and Consistency Management

**Narrative Elements:**
- Track all character names, traits, backgrounds, and development arcs
- Maintain consistent world-building details and rules
- Remember plot points, conflicts, and their resolutions
- Ensure timeline consistency and logical progression

**Style Consistency:**
- Maintain consistent terminology and explanations throughout
- Keep the same perspective (1st person, 3rd person, etc.)
- Preserve the established tone and writing style
- Reference earlier content naturally when relevant

## Content Generation Process

**Planning Phase:**
When given a book topic and genre, first create:
1. A detailed book outline with chapter summaries
2. Character profiles (for fiction) or key concept definitions (for non-fiction)
3. Target audience analysis and reading level
4. Key themes and messages to weave throughout

**Writing Phase:**
- Begin each chapter by reviewing the overall outline and previous content
- Write complete chapters with proper pacing and development
- Include smooth transitions between sections and chapters
- End with compelling conclusions that advance the overall narrative

**Quality Control:**
- Regularly reference previous content to maintain consistency
- Ensure each chapter advances the book's central premise
- Verify that content delivers on promises made in chapter titles
- Check that the reading experience flows naturally from start to finish

## Specific Instructions

**Response Format:**
- Provide complete, finished content ready for publication
- Include proper chapter headings and section breaks
- Write in full paragraphs with proper punctuation and grammar
- Do not include placeholders, notes to self, or incomplete sections

**Content Depth:**
- Develop ideas fully rather than just listing concepts
- Include relevant examples, analogies, and supporting details
- Provide actionable advice and concrete takeaways
- Balance comprehensiveness with accessibility

**Commercial Viability:**
- Write content that provides clear value to readers
- Consider search keywords and market appeal naturally within the narrative
- Ensure content is substantial enough to justify purchase price
- Create content that encourages positive reviews and word-of-mouth

## Output Requirements

When generating content:
1. **Always maintain awareness of the complete book context**
2. **Reference previous chapters naturally when relevant**
3. **Ensure each new section builds logically on what came before**
4. **Write complete, polished content ready for publication**
5. **Maintain the established voice and quality throughout**

Your mission is to create books that readers will genuinely enjoy, find valuable, and recommend to others. Focus on delivering exceptional quality that stands out in the marketplace while meeting all professional publishing standards.
EOF
)

# Chapter-specific user prompt
USER_PROMPT="Based on the book outline below and any existing chapters, write Chapter ${CHAPTER_NUM}: '${CHAPTER_TITLE}'

CRITICAL REQUIREMENTS:
- Write EXACTLY 2,000-2,500 words (this is mandatory - do not write less)
- Include detailed explanations, examples, and practical advice
- Break content into multiple sections with subheadings
- Use storytelling elements, case studies, or detailed scenarios
- Include actionable takeaways and specific steps
- Write comprehensive, in-depth content that thoroughly covers the chapter topic
- Do not summarize or abbreviate - write full, complete explanations

STRUCTURE REQUIREMENTS:
- Start with an engaging hook or story
- Use 4-6 subheadings to organize content
- Include concrete examples for each major point
- End with a strong conclusion and transition to next chapter
- Use proper markdown formatting throughout

CONTENT DEPTH:
- Elaborate on every concept with detailed explanations
- Include real-world applications and scenarios  
- Provide step-by-step guidance where applicable
- Use analogies, metaphors, and stories to illustrate points
- Address potential objections or challenges readers might have

Remember: This chapter must be 2,000-2,500 words. Write comprehensive, detailed content that fully explores the chapter topic.

BOOK OUTLINE:
${OUTLINE_CONTENT}

EXISTING CHAPTERS:
${EXISTING_CHAPTERS}

Now write Chapter ${CHAPTER_NUM}: ${CHAPTER_TITLE} - MINIMUM 2,000 words, target 2,500 words."

# Escape and create JSON (same functions as main script)
escape_json() {
    echo "$1" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
}

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
    "temperature": 0.95,
    "topK": 70,
    "topP": 0.8,
    "maxOutputTokens": 400000
  }
}
EOF
)

echo "Generating Chapter $CHAPTER_NUM: $CHAPTER_TITLE"
echo "Using outline: $OUTLINE_FILE"
echo "Making API request..."

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: $API_KEY" \
  -d "$JSON_PAYLOAD" \
  "$API_URL")

# Error checking
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error:"
    echo "$RESPONSE" | jq '.error'
    exit 1
fi

# Save chapter
OUTPUT_FILE="${BOOK_DIR}/chapter_${CHAPTER_NUM}.md"
echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$OUTPUT_FILE"

echo "✅ Chapter $CHAPTER_NUM generated successfully!"
echo "📄 Saved to: $OUTPUT_FILE"

# Word count
WORD_COUNT=$(wc -w < "$OUTPUT_FILE")
echo "📊 Word count: $WORD_COUNT words"

echo ""
echo "📖 Preview:"
echo "----------------------------------------"
head -n 15 "$OUTPUT_FILE"
echo "----------------------------------------"