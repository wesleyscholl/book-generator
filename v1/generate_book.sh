#!/bin/bash

# Gemini Book Generation Script
# Usage: ./generate_book.sh "Book Topic" "Genre" "Target Audience"

set -e

# Configuration
API_KEY="${GEMINI_API_KEY}"
MODEL="gemini-1.5-flash-latest"
API_URL="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"

# Input validation
if [ $# -ne 3 ]; then
    echo "Usage: $0 'Book Topic' 'Genre' 'Target Audience'"
    echo "Example: $0 'Personal Finance for Millennials' 'Self-Help' 'Young Adults 25-35'"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable not set"
    echo "Set it with: export GEMINI_API_KEY='your-api-key'"
    exit 1
fi

TOPIC="$1"
GENRE="$2"
AUDIENCE="$3"

# System prompt (stored in heredoc for readability)
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

# User prompt for initial book planning
USER_PROMPT="Create a detailed outline for a ${GENRE} book about '${TOPIC}' targeting ${AUDIENCE}. Include:
- Complete chapter breakdown with 2-3 sentence summaries (12-15 chapters)
- Character profiles (fiction) or key concept definitions (non-fiction)
- Target reading level and tone
- 3-5 core themes to weave throughout
- Book title and subtitle suggestions"

# Escape quotes for JSON
escape_json() {
    echo "$1" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g'
}

ESCAPED_SYSTEM=$(escape_json "$SYSTEM_PROMPT")
ESCAPED_USER=$(escape_json "$USER_PROMPT")

# Create JSON payload
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
    "maxOutputTokens": 8192
  }
}
EOF
)

# Make API request
echo "Generating book outline for: $TOPIC ($GENRE)"
echo "Target audience: $AUDIENCE"
echo "Making API request to Gemini..."

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: $API_KEY" \
  -d "$JSON_PAYLOAD" \
  "$API_URL")

# Check for errors
if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    echo "API Error:"
    echo "$RESPONSE" | jq '.error'
    exit 1
fi

# Extract and save response
OUTPUT_DIR="./book_outputs"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${OUTPUT_DIR}/book_outline_${TIMESTAMP}.md"

# Extract text content from response
echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' > "$OUTPUT_FILE"

echo "✅ Book outline generated successfully!"
echo "📄 Output saved to: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "1. Review the outline in $OUTPUT_FILE"
echo "2. Use generate_chapter.sh to generate individual chapters"
echo "3. Or modify this script to continue with full book generation"

# Display first few lines of output
echo ""
echo "📖 Preview:"
echo "----------------------------------------"
head -n 20 "$OUTPUT_FILE"
echo "----------------------------------------"
echo "(See full output in $OUTPUT_FILE)"