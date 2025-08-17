#!/bin/bash

# LanguageTool Integration Script
# Handles grammar checking, style analysis, and basic quality assessment
# Usage: ./tools/languagetool_check.sh chapter_file.md [options]

set -e

# Configuration
LANGUAGETOOL_URL="http://localhost:8081/v2/check"  # Adjust to your server
FASTTEXT_MODEL_PATH="/path/to/fasttext/model"  # Adjust to your FastText model path
OUTPUT_DIR="./quality_reports"
VERBOSE=false
LANGUAGE="en-US"
MAX_TEXT_LENGTH=50000  # LanguageTool limit

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
LanguageTool Quality Checker for Book Generator

USAGE:
    $0 chapter_file.md [OPTIONS]

OPTIONS:
    -l, --language LANG     Language code (default: en-US)
    -u, --url URL          LanguageTool server URL
    -v, --verbose          Verbose output
    -o, --output-dir DIR   Output directory for reports
    -h, --help             Show this help

FEATURES:
    ✅ Grammar and spell checking
    ✅ Style and readability analysis
    ✅ Writing quality metrics
    ✅ Detailed error reports
    ❌ Copyright detection (not supported by LanguageTool)
    ❌ Plagiarism detection (not supported by LanguageTool)

EXAMPLES:
    $0 chapter_1.md
    $0 chapter_1.md --verbose --language en-US
    $0 chapter_1.md --output-dir ./reports

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--language)
            LANGUAGE="$2"
            shift 2
            ;;
        -u|--url)
            LANGUAGETOOL_URL="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            show_help
            exit 1
            ;;
        *)
            CHAPTER_FILE="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$CHAPTER_FILE" ]; then
    echo -e "${RED}❌ Error: Chapter file not specified${NC}"
    show_help
    exit 1
fi

if [ ! -f "$CHAPTER_FILE" ]; then
    echo -e "${RED}❌ Error: File '$CHAPTER_FILE' not found${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Extract text from markdown (remove markdown syntax)
extract_text_from_markdown() {
    local file="$1"
    # Remove markdown headers, links, bold/italic, etc. using multiple sed commands
    cat "$file" | \
    sed 's/^[#]*[[:space:]]*//g' | \
    sed 's/\*\*\([^*]*\)\*\*/\1/g' | \
    sed 's/\*\([^*]*\)\*/\1/g' | \
    sed 's/\[\([^]]*\)\]([^)]*)/\1/g' | \
    sed 's/`\([^`]*\)`/\1/g' | \
    sed '/^```/,/^```/d' | \
    sed 's/^[-*+][[:space:]]*//g' | \
    sed 's/^[0-9]*\.[[:space:]]*//g' | \
    sed '/^[[:space:]]*$/d' | \
    tr '\n' ' ' | \
    sed 's/[[:space:]]\+/ /g' | \
    sed 's/^[[:space:]]*//' | \
    sed 's/[[:space:]]*$//'
}

# Check LanguageTool server availability
check_languagetool_server() {
    local health_url=$(echo "$LANGUAGETOOL_URL" | sed 's|/v2/check|/v2/languages|')
    
    if ! curl -s --connect-timeout 5 "$health_url" > /dev/null 2>&1; then
        echo -e "${RED}❌ Error: LanguageTool server not available at $LANGUAGETOOL_URL${NC}"
        echo -e "${YELLOW}💡 Make sure your LanguageTool server is running:${NC}"
        echo -e "   java -cp languagetool-server.jar org.languagetool.server.HTTPServer --port 8081"
        exit 1
    fi
}

# Analyze text with LanguageTool
analyze_with_languagetool() {
    local text="$1"
    local temp_file=$(mktemp)
    
    # Split text into chunks if too long
    local text_length=${#text}
    if [ $text_length -gt $MAX_TEXT_LENGTH ]; then
        echo -e "${YELLOW}⚠️  Text is long ($text_length chars), splitting into chunks...${NC}"
        
        # Split into sentences and group them into chunks
        echo "$text" | sed 's/\([.!?]\)\s*/\1\n/g' | \
        awk -v max=$MAX_TEXT_LENGTH '
            {
                if (length(chunk $0) > max) {
                    if (chunk != "") print chunk
                    chunk = $0 "\n"
                } else {
                    chunk = chunk $0 "\n"
                }
            }
            END { if (chunk != "") print chunk }
        ' > "$temp_file"
        
        # Process each chunk
        local chunk_num=0
        local all_results=""
        
        while IFS= read -r chunk; do
            if [ -n "$chunk" ]; then
                chunk_num=$((chunk_num + 1))
                [ "$VERBOSE" = true ] && echo -e "${CYAN}📝 Processing chunk $chunk_num...${NC}"
                
                local result=$(curl -s -X POST \
                    -H "Content-Type: application/x-www-form-urlencoded" \
                    -d "text=$(echo "$chunk" | sed 's/+/%2B/g' | sed 's/ /+/g')" \
                    -d "language=$LANGUAGE" \
                    -d "enabledOnly=false" \
                    "$LANGUAGETOOL_URL")
                
                all_results="$all_results$result"
            fi
        done < "$temp_file"
        
        echo "$all_results"
    else
        # Process normally for shorter text
        curl -s -X POST \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "text=$(echo "$text" | sed 's/+/%2B/g' | sed 's/ /+/g')" \
            -d "language=$LANGUAGE" \
            -d "enabledOnly=false" \
            "$LANGUAGETOOL_URL"
    fi
    
    rm -f "$temp_file"
}

# Generate quality report
generate_quality_report() {
    local chapter_file="$1"
    local lt_result="$2"
    local chapter_name=$(basename "$chapter_file" .md)
    local report_file="$OUTPUT_DIR/${chapter_name}_quality_report.md"
    local text="$3"
    
    # Parse LanguageTool results
    local total_matches=$(echo "$lt_result" | jq -r '.matches | length' 2>/dev/null || echo "0")
    local grammar_errors=$(echo "$lt_result" | jq -r '[.matches[] | select(.rule.category.id == "GRAMMAR")] | length' 2>/dev/null || echo "0")
    local spelling_errors=$(echo "$lt_result" | jq -r '[.matches[] | select(.rule.category.id == "TYPOS")] | length' 2>/dev/null || echo "0")
    local style_issues=$(echo "$lt_result" | jq -r '[.matches[] | select(.rule.category.id == "STYLE")] | length' 2>/dev/null || echo "0")
    
    # Calculate basic metrics
    local word_count=$(echo "$text" | wc -w)
    local sentence_count=$(echo "$text" | sed 's/[.!?]/\n/g' | grep -c '[a-zA-Z]' || echo "1")
    local avg_sentence_length=$(( word_count / sentence_count ))
    
    # Calculate quality score (0-100)
    local error_rate=0
    local quality_score=100
    
    if [ "$word_count" -gt 0 ] && [ "$total_matches" -gt 0 ]; then
        error_rate=$(echo "scale=2; $total_matches / $word_count * 100" | bc -l 2>/dev/null || echo "0")
        quality_score=$(echo "scale=0; 100 - ($error_rate * 10)" | bc -l 2>/dev/null || echo "100")
    fi
    
    # Ensure quality score is between 0 and 100
    if [ $(echo "$quality_score < 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
        quality_score=0
    elif [ $(echo "$quality_score > 100" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
        quality_score=100
    fi
    
    # Generate report
    cat << EOF > "$report_file"
# Quality Report: $chapter_name

Generated: $(date)
Source: $chapter_file

## Overview
- **Quality Score:** ${quality_score}%
- **Total Issues:** $total_matches
- **Word Count:** $word_count
- **Error Rate:** ${error_rate}% (errors per 100 words)

## Issue Breakdown
- **Grammar Errors:** $grammar_errors
- **Spelling Errors:** $spelling_errors  
- **Style Issues:** $style_issues
- **Other Issues:** $(( total_matches - grammar_errors - spelling_errors - style_issues ))

## Readability Metrics
- **Sentences:** $sentence_count
- **Average Sentence Length:** $avg_sentence_length words
- **Reading Level:** $(get_reading_level $avg_sentence_length)

EOF

    # Add detailed issues if any
    if [ "$total_matches" -gt 0 ]; then
        echo "## Detailed Issues" >> "$report_file"
        echo "" >> "$report_file"
        
        # Parse and format issues
        echo "$lt_result" | jq -r '.matches[] | "### " + .rule.category.name + ": " + .rule.description + "\n**Context:** \"" + .context.text + "\"\n**Suggestion:** " + (.replacements[0].value // "No suggestion") + "\n**Rule:** " + .rule.id + "\n"' 2>/dev/null >> "$report_file" || echo "Could not parse detailed issues" >> "$report_file"
    fi
    
    # Add recommendations
    cat << EOF >> "$report_file"

## Recommendations

EOF

    if [ "$grammar_errors" -gt 0 ]; then
        echo "- 📝 **Grammar:** $grammar_errors grammar errors detected. Review and fix before publishing." >> "$report_file"
    fi
    
    if [ "$spelling_errors" -gt 0 ]; then
        echo "- 🔤 **Spelling:** $spelling_errors spelling errors found. Use spell check or manual review." >> "$report_file"
    fi
    
    if [ "$avg_sentence_length" -gt 25 ]; then
        echo "- 📏 **Readability:** Average sentence length is high ($avg_sentence_length words). Consider shorter sentences." >> "$report_file"
    fi
    
    if [ $(echo "$quality_score < 80" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
        echo "- ⚠️  **Quality:** Overall quality score is below 80%. Significant editing recommended." >> "$report_file"
    fi
    
    echo "$report_file"
}

# Get reading level based on sentence length
get_reading_level() {
    local avg_length=$1
    if [ "$avg_length" -lt 15 ]; then
        echo "Elementary"
    elif [ "$avg_length" -lt 20 ]; then
        echo "High School"
    elif [ "$avg_length" -lt 25 ]; then
        echo "College"
    else
        echo "Graduate"
    fi
}

# Auto-fix common issues
auto_fix_issues() {
    local chapter_file="$1"
    local lt_result="$2"
    local backup_file="${chapter_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    echo -e "${CYAN}🔧 Creating backup: $(basename "$backup_file")${NC}"
    cp "$chapter_file" "$backup_file"
    
    # Apply simple fixes (be very conservative)
    local fixes_applied=0
    local temp_file=$(mktemp)
    
    # Fix double spaces
    if sed 's/  \+/ /g' "$chapter_file" > "$temp_file" && mv "$temp_file" "$chapter_file"; then
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # Fix common punctuation issues (remove spaces before punctuation)
    if sed 's/ \+\([,.!?]\)/\1/g' "$chapter_file" > "$temp_file" && mv "$temp_file" "$chapter_file"; then
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # Add space after periods if missing (but be careful with abbreviations)
    if sed 's/\([.!?]\)\([A-Z]\)/\1 \2/g' "$chapter_file" > "$temp_file" && mv "$temp_file" "$chapter_file"; then
        fixes_applied=$((fixes_applied + 1))
    fi
    
    rm -f "$temp_file"
    
    echo -e "${GREEN}✅ Applied $fixes_applied basic fixes${NC}"
    echo -e "${YELLOW}💾 Backup saved as: $(basename "$backup_file")${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}🔍 LanguageTool Quality Check${NC}"
    echo -e "File: $CHAPTER_FILE"
    echo -e "Language: $LANGUAGE"
    echo ""
    
    # Check server availability
    echo -e "${CYAN}📡 Checking LanguageTool server...${NC}"
    check_languagetool_server
    echo -e "${GREEN}✅ Server is available${NC}"
    
    # Extract and prepare text
    echo -e "${CYAN}📄 Extracting text from markdown...${NC}"
    TEXT=$(extract_text_from_markdown "$CHAPTER_FILE")
    WORD_COUNT=$(echo "$TEXT" | wc -w)
    echo -e "${GREEN}✅ Extracted $WORD_COUNT words${NC}"
    
    if [ "$WORD_COUNT" -eq 0 ]; then
        echo -e "${RED}❌ No text found in file${NC}"
        exit 1
    fi
    
    # Analyze with LanguageTool
    echo -e "${CYAN}🔍 Analyzing with LanguageTool...${NC}"
    LT_RESULT=$(analyze_with_languagetool "$TEXT")
    
    if [ $? -ne 0 ] || [ -z "$LT_RESULT" ]; then
        echo -e "${RED}❌ LanguageTool analysis failed${NC}"
        exit 1
    fi
    
    # Check if result is valid JSON
    if ! echo "$LT_RESULT" | jq . > /dev/null 2>&1; then
        echo -e "${RED}❌ Invalid response from LanguageTool${NC}"
        echo "Response: $LT_RESULT"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Analysis complete${NC}"
    
    # Generate report
    echo -e "${CYAN}📊 Generating quality report...${NC}"
    REPORT_FILE=$(generate_quality_report "$CHAPTER_FILE" "$LT_RESULT" "$TEXT")
    echo -e "${GREEN}✅ Report saved: $(basename "$REPORT_FILE")${NC}"
    
    # Show summary
    TOTAL_ISSUES=$(echo "$LT_RESULT" | jq -r '.matches | length')
    QUALITY_SCORE=$(grep "Quality Score" "$REPORT_FILE" | sed 's/.*Quality Score:\*\* \([0-9]*\)%.*/\1%/' || echo "N/A")
    
    echo ""
    echo -e "${PURPLE}📋 SUMMARY${NC}"
    echo -e "Quality Score: $QUALITY_SCORE"
    echo -e "Total Issues: $TOTAL_ISSUES"
    echo -e "Report: $(basename "$REPORT_FILE")"
    
    if [ "$TOTAL_ISSUES" -gt 0 ]; then
        echo -e "${CYAN}🔧 Applying automatic fixes for common issues...${NC}"
        auto_fix_issues "$CHAPTER_FILE" "$LT_RESULT"
    fi
    
    # Verbose output
    if [ "$VERBOSE" = true ] && [ "$TOTAL_ISSUES" -gt 0 ]; then
        echo ""
        echo -e "${CYAN}📝 DETAILED ISSUES:${NC}"
        echo "$LT_RESULT" | jq -r '.matches[] | "• " + .rule.category.name + ": " + .message'
    fi
}

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: jq is required but not installed${NC}"
    echo "Install with: sudo apt install jq"
    exit 1
fi

if ! command -v bc >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: bc is required but not installed${NC}"
    echo "Install with: sudo apt install bc"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: curl is required but not installed${NC}"
    echo "Install with: sudo apt install curl"
    exit 1
fi

# Run main function
main "$@"