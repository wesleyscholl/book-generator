#!/bin/bash

# KDP Market Analyzer - Deep dive analysis for specific topics
# Usage: ./kdp_market_analyzer.sh "topic_name"

set -e

TOPIC="$1"
RESULTS_DIR="kdp_analysis_$(date +%Y%m%d)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Create analysis directory
setup_analysis() {
    mkdir -p "$RESULTS_DIR"
    cd "$RESULTS_DIR"
    print_status "Analysis directory created: $RESULTS_DIR"
}

# Generate comprehensive keyword list
generate_keywords() {
    local topic="$1"
    local keywords_file="keywords_${topic// /_}.txt"
    
    cat > "$keywords_file" << EOF
# Primary Keywords
$topic
$topic guide
$topic book
$topic workbook
$topic manual
$topic handbook

# Question-based Keywords
how to $topic
$topic for beginners
$topic step by step
$topic tips
$topic secrets
$topic strategies

# Problem-solving Keywords
$topic problems
$topic solutions
$topic help
$topic advice
$topic support

# Advanced Keywords
advanced $topic
$topic mastery
$topic expert
$topic professional
$topic complete guide

# Audience-specific
$topic for women
$topic for men
$topic for kids
$topic for seniors
$topic for teens
EOF

    print_status "Keywords generated: $keywords_file"
}

# Analyze competition gaps
analyze_gaps() {
    local topic="$1"
    local gaps_file="market_gaps_${topic// /_}.txt"
    
    cat > "$gaps_file" << EOF
# Market Gap Analysis for: $topic

## Potential Gaps to Explore:
1. Specific audience segments (age, gender, profession)
2. Different skill levels (beginner, intermediate, advanced)
3. Format variations (workbook, journal, reference, quick guide)
4. Problem-specific solutions
5. Seasonal or trending angles
6. Geographic or cultural adaptations

## Questions to Research:
- Are there books for complete beginners?
- Is there a quick-start guide (30 days or less)?
- Are there workbooks with exercises?
- Is there content for specific demographics?
- Are there books addressing common complaints in reviews?

## Suggested Sub-niches:
- $topic for busy professionals
- $topic on a budget
- $topic without equipment/tools
- $topic for small spaces
- Emergency/quick $topic
EOF

    print_status "Market gaps analysis created: $gaps_file"
}

# Generate title ideas
generate_titles() {
    local topic="$1"
    local titles_file="title_ideas_${topic// /_}.txt"
    
    cat > "$titles_file" << EOF
# Title Ideas for: $topic

## Power Words Format:
- The Ultimate $topic Guide
- $topic Secrets Revealed
- Master $topic in 30 Days
- The Complete $topic Handbook
- $topic Made Simple

## Problem/Solution Format:
- Solve Your $topic Problems
- $topic Without the Stress
- Effortless $topic for Everyone
- $topic That Actually Works
- No-Fail $topic Strategy

## Audience-Specific Format:
- $topic for Busy People
- The Working Parent's $topic Guide
- $topic After 40
- Student's Guide to $topic
- $topic for Small Budgets

## Benefit-Driven Format:
- Transform Your Life with $topic
- From Zero to $topic Hero
- $topic Success in 90 Days
- The $topic Breakthrough Method
- Unlock Your $topic Potential

## Format-Specific:
- The $topic Workbook
- $topic Journal & Planner
- $topic Quick Reference
- 365 Days of $topic
- The $topic Checklist
EOF

    print_status "Title ideas generated: $titles_file"
}

# Create research checklist
create_checklist() {
    local checklist_file="research_checklist.md"
    
    cat > "$checklist_file" << EOF
# KDP Research Checklist

## Market Research
- [ ] Check Amazon Best Sellers in relevant categories
- [ ] Analyze top 10 competitors' titles and covers
- [ ] Read recent reviews for common complaints/gaps
- [ ] Check Google Trends for search volume
- [ ] Research seasonal trends
- [ ] Verify target audience size

## Keyword Research
- [ ] Use Helium 10 or Publisher Rocket for keyword data
- [ ] Check search volumes and competition levels
- [ ] Find long-tail keyword opportunities
- [ ] Analyze competitor keywords
- [ ] Test keywords in Amazon search

## Competition Analysis
- [ ] Count number of books with <100 reviews
- [ ] Find average price point
- [ ] Analyze cover designs and common elements
- [ ] Check publication dates (market saturation timing)
- [ ] Review book lengths and formats

## Content Planning
- [ ] Outline unique angle/approach
- [ ] Plan chapter structure
- [ ] Identify value-adds (checklists, templates, etc.)
- [ ] Consider series potential
- [ ] Plan complementary products

## Validation
- [ ] Survey potential readers (social media, forums)
- [ ] Check related Facebook groups/communities
- [ ] Analyze Pinterest/Instagram content engagement
- [ ] Test title ideas with target audience
- [ ] Validate price point expectations
EOF

    print_status "Research checklist created: $checklist_file"
}

# Main function
main() {
    if [[ -z "$TOPIC" ]]; then
        echo "Usage: $0 'topic name'"
        echo "Example: $0 'weight loss'"
        exit 1
    fi
    
    echo -e "${BLUE}KDP Market Analyzer${NC}"
    echo "Deep analysis for topic: $TOPIC"
    echo
    
    setup_analysis
    generate_keywords "$TOPIC"
    analyze_gaps "$TOPIC"
    generate_titles "$TOPIC"
    create_checklist
    
    echo
    print_status "Analysis complete! Files created in: $RESULTS_DIR"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review generated keywords and add more specific ones"
    echo "2. Research actual Amazon data using the keywords"
    echo "3. Use the market gaps analysis to find your unique angle"
    echo "4. Test title ideas with your target audience"
    echo "5. Follow the research checklist for thorough validation"
}

main "$@"