#!/bin/bash

# Plagiarism Report Manager
# Usage: ./plagiarism_report_manager.sh [book_directory] [action]

set -e

# Help function
show_help() {
    cat << 'EOF'
Plagiarism Report Manager

USAGE:
    ./plagiarism_report_manager.sh [book_directory] [action]

ACTIONS:
    summary      - Show overall plagiarism summary for all chapters
    details      - Show detailed reports for each chapter
    flagged      - Show only chapters with high risk or low scores
    export       - Export all reports to a consolidated document
    clean        - Remove all plagiarism reports and backups (use with caution)

EXAMPLES:
    ./plagiarism_report_manager.sh ./book_outputs/book_outline_20241201_143022 summary
    ./plagiarism_report_manager.sh ./book_outputs/book_outline_20241201_143022 flagged
    ./plagiarism_report_manager.sh ./book_outputs/book_outline_20241201_143022 export

If no arguments provided, will show interactive menu for latest book directory.
EOF
}

# Animation functions
typewriter() {
    local text="$1"
    local delay="${2:-0.03}"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%c" "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Get book directory
get_book_directory() {
    local book_dir="$1"
    
    if [ -z "$book_dir" ]; then
        echo "📁 Available book directories:"
        
        local book_dirs=($(ls -d ./book_outputs/book_outline_* 2>/dev/null | sort -r))
        
        if [ ${#book_dirs[@]} -eq 0 ]; then
            echo "❌ No book directories found in ./book_outputs/"
            exit 1
        fi
        
        for i in "${!book_dirs[@]}"; do
            local dir_name=$(basename "${book_dirs[$i]}")
            local chapter_count=$(ls "${book_dirs[$i]}"/chapter_*.md 2>/dev/null | wc -l)
            local report_count=$(ls "${book_dirs[$i]}"/chapter_*_plagiarism_report.md 2>/dev/null | wc -l)
            echo "   $((i+1))) $dir_name ($chapter_count chapters, $report_count reports)"
        done
        
        echo ""
        read -p "Select directory (1-${#book_dirs[@]}): " dir_choice
        
        if [[ ! "$dir_choice" =~ ^[0-9]+$ ]] || [ "$dir_choice" -lt 1 ] || [ "$dir_choice" -gt "${#book_dirs[@]}" ]; then
            echo "❌ Invalid selection"
            exit 1
        fi
        
        book_dir="${book_dirs[$((dir_choice-1))]}"
    fi
    
    if [ ! -d "$book_dir" ]; then
        echo "❌ Error: Directory '$book_dir' not found"
        exit 1
    fi
    
    echo "$book_dir"
}

# Show plagiarism summary
show_summary() {
    local book_dir="$1"
    
    typewriter "🔍 Plagiarism Check Summary for $(basename "$book_dir")"
    echo ""
    
    local reports=($(ls "${book_dir}"/chapter_*_plagiarism_report.md 2>/dev/null))
    local backups=($(ls "${book_dir}"/chapter_*.md.backup_* 2>/dev/null))
    
    if [ ${#reports[@]} -eq 0 ]; then
        echo "📊 No plagiarism reports found in this directory"
        echo "   This means plagiarism checking was not performed or reports were deleted"
        return
    fi
    
    echo "📊 Overall Statistics:"
    echo "   📝 Total chapters checked: ${#reports[@]}"
    echo "   🔄 Chapters rewritten: ${#backups[@]}"
    echo ""
    
    # Calculate score statistics
    local total_score=0
    local valid_scores=0
    local high_risk=0
    local medium_risk=0
    local low_risk=0
    
    echo "📈 Chapter-by-Chapter Scores:"
    for report in "${reports[@]}"; do
        if [ -f "$report" ]; then
            local chapter_num=$(basename "$report" | sed 's/chapter_\([0-9]*\)_plagiarism_report.md/\1/')
            local score=$(grep "ORIGINALITY_SCORE:" "$report" | sed 's/ORIGINALITY_SCORE: //' | tr -d ' ')
            local plag_risk=$(grep "PLAGIARISM_RISK:" "$report" | sed 's/PLAGIARISM_RISK: //' | tr -d ' ')
            local copy_risk=$(grep "COPYRIGHT_RISK:" "$report" | sed 's/COPYRIGHT_RISK: //' | tr -d ' ')
            
            if [ -n "$score" ] && [[ "$score" =~ ^[0-9]+$ ]]; then
                total_score=$((total_score + score))
                valid_scores=$((valid_scores + 1))
                
                # Determine overall risk
                if [[ "$plag_risk" == "HIGH" ]] || [[ "$copy_risk" == "HIGH" ]] || [ "$score" -lt 6 ]; then
                    high_risk=$((high_risk + 1))
                    echo "   Chapter $chapter_num: $score/10 🔴 (High Risk - $plag_risk/$copy_risk)"
                elif [[ "$plag_risk" == "MEDIUM" ]] || [[ "$copy_risk" == "MEDIUM" ]] || [ "$score" -lt 8 ]; then
                    medium_risk=$((medium_risk + 1))
                    echo "   Chapter $chapter_num: $score/10 🟡 (Medium Risk - $plag_risk/$copy_risk)"
                else
                    low_risk=$((low_risk + 1))
                    echo "   Chapter $chapter_num: $score/10 🟢 (Low Risk - $plag_risk/$copy_risk)"
                fi
            else
                echo "   Chapter $chapter_num: ❓ (Score not found)"
            fi
        fi
    done
    
    if [ $valid_scores -gt 0 ]; then
        local avg_score=$((total_score / valid_scores))
        echo ""
        echo "📊 Summary Statistics:"
        echo "   📈 Average Originality Score: $avg_score/10"
        echo "   🟢 Low Risk Chapters: $low_risk"
        echo "   🟡 Medium Risk Chapters: $medium_risk"
        echo "   🔴 High Risk Chapters: $high_risk"
        echo ""
        
        if [ $avg_score -ge 8 ]; then
            echo "✅ Overall Assessment: Excellent originality (98%+ original content)"
        elif [ $avg_score -ge 6 ]; then
            echo "✅ Overall Assessment: Good originality (85%+ original content)"  
        else
            echo "⚠️  Overall Assessment: Needs improvement (manual review recommended)"
        fi
    fi
}

# Show detailed reports
show_details() {
    local book_dir="$1"
    
    typewriter "📋 Detailed Plagiarism Reports for $(basename "$book_dir")"
    echo ""
    
    local reports=($(ls "${book_dir}"/chapter_*_plagiarism_report.md 2>/dev/null | sort -V))
    
    if [ ${#reports[@]} -eq 0 ]; then
        echo "📊 No plagiarism reports found in this directory"
        return
    fi
    
    for report in "${reports[@]}"; do
        local chapter_num=$(basename "$report" | sed 's/chapter_\([0-9]*\)_plagiarism_report.md/\1/')
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📄 Chapter $chapter_num Detailed Report"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        cat "$report"
        echo ""
        echo ""
        
        read -p "Press Enter to continue to next chapter (or 'q' to quit): " response
        if [[ "$response" == "q" ]]; then
            break
        fi
    done
}

# Show only flagged chapters
show_flagged() {
    local book_dir="$1"
    
    typewriter "🚨 Flagged Chapters (High Risk or Low Scores)"
    echo ""
    
    local reports=($(ls "${book_dir}"/chapter_*_plagiarism_report.md 2>/dev/null | sort -V))
    local flagged_count=0
    
    if [ ${#reports[@]} -eq 0 ]; then
        echo "📊 No plagiarism reports found in this directory"
        return
    fi
    
    for report in "${reports[@]}"; do
        if [ -f "$report" ]; then
            local chapter_num=$(basename "$report" | sed 's/chapter_\([0-9]*\)_plagiarism_report.md/\1/')
            local score=$(grep "ORIGINALITY_SCORE:" "$report" | sed 's/ORIGINALITY_SCORE: //' | tr -d ' ')
            local plag_risk=$(grep "PLAGIARISM_RISK:" "$report" | sed 's/PLAGIARISM_RISK: //' | tr -d ' ')
            local copy_risk=$(grep "COPYRIGHT_RISK:" "$report" | sed 's/COPYRIGHT_RISK: //' | tr -d ' ')
            local issues=$(grep "ISSUES_FOUND:" "$report" | sed 's/ISSUES_FOUND: //' | tr -d ' ')
            
            # Check if chapter is flagged
            local is_flagged=false
            if [[ "$plag_risk" == "HIGH" ]] || [[ "$copy_risk" == "HIGH" ]] || [[ "$issues" == "YES" ]]; then
                is_flagged=true
            elif [[ -n "$score" ]] && [[ "$score" =~ ^[0-9]+$ ]] && [ "$score" -lt 6 ]; then
                is_flagged=true
            fi
            
            if [ "$is_flagged" = true ]; then
                flagged_count=$((flagged_count + 1))
                echo "🚨 Chapter $chapter_num - HIGH PRIORITY"
                echo "   📊 Originality Score: ${score:-N/A}/10"
                echo "   ⚠️  Plagiarism Risk: $plag_risk"
                echo "   ⚠️  Copyright Risk: $copy_risk"
                echo "   🔍 Issues Found: $issues"
                echo ""
                
                # Show flagged sections if available
                local flagged_sections=$(grep -A 10 "FLAGGED_SECTIONS:" "$report" | tail -n +2 | head -3)
                if [ -n "$flagged_sections" ]; then
                    echo "   🎯 Flagged Content:"
                    echo "$flagged_sections" | sed 's/^/      /'
                    echo ""
                fi
                
                # Check if chapter was rewritten
                local backup_files=($(ls "${book_dir}"/chapter_${chapter_num}.md.backup_* 2>/dev/null))
                if [ ${#backup_files[@]} -gt 0 ]; then
                    echo "   ✅ Chapter was automatically rewritten (${#backup_files[@]} backup(s) available)"
                else
                    echo "   ❌ Chapter was NOT rewritten - manual review needed"
                fi
                echo ""
                echo "───────────────────────────────────────────────────────────────────────────────"
                echo ""
            fi
        fi
    done
    
    if [ $flagged_count -eq 0 ]; then
        echo "✅ No chapters flagged for high risk or low originality scores"
        echo "   All chapters appear to have acceptable originality levels"
    else
        echo "⚠️  Found $flagged_count flagged chapter(s) requiring attention"
        echo ""
        echo "📋 Recommended Actions:"
        echo "   1. Review the flagged content sections"
        echo "   2. Manually edit problematic passages"
        echo "   3. Consider regenerating chapters with low scores"
        echo "   4. Verify that rewritten chapters address the issues"
    fi
}

# Export consolidated report
export_report() {
    local book_dir="$1"
    
    typewriter "📤 Exporting Consolidated Plagiarism Report"
    echo ""
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_file="${book_dir}/plagiarism_summary_${timestamp}.md"
    
    cat << EOF > "$export_file"
# Plagiarism Check Summary Report

**Book Directory:** $(basename "$book_dir")  
**Generated:** $(date +"%B %d, %Y at %I:%M %p")  
**Report Type:** Consolidated Plagiarism Analysis

---

## Executive Summary

EOF
    
    # Add summary statistics
    local reports=($(ls "${book_dir}"/chapter_*_plagiarism_report.md 2>/dev/null))
    local backups=($(ls "${book_dir}"/chapter_*.md.backup_* 2>/dev/null))
    
    echo "- **Total Chapters Analyzed:** ${#reports[@]}" >> "$export_file"
    echo "- **Chapters Rewritten:** ${#backups[@]}" >> "$export_file"
    
    if [ ${#reports[@]} -gt 0 ]; then
        local total_score=0
        local valid_scores=0
        local high_risk=0
        local medium_risk=0
        local low_risk=0
        
        for report in "${reports[@]}"; do
            if [ -f "$report" ]; then
                local score=$(grep "ORIGINALITY_SCORE:" "$report" | sed 's/ORIGINALITY_SCORE: //' | tr -d ' ')
                local plag_risk=$(grep "PLAGIARISM_RISK:" "$report" | sed 's/PLAGIARISM_RISK: //' | tr -d ' ')
                local copy_risk=$(grep "COPYRIGHT_RISK:" "$report" | sed 's/COPYRIGHT_RISK: //' | tr -d ' ')
                
                if [ -n "$score" ] && [[ "$score" =~ ^[0-9]+$ ]]; then
                    total_score=$((total_score + score))
                    valid_scores=$((valid_scores + 1))
                    
                    if [[ "$plag_risk" == "HIGH" ]] || [[ "$copy_risk" == "HIGH" ]] || [ "$score" -lt 6 ]; then
                        high_risk=$((high_risk + 1))
                    elif [[ "$plag_risk" == "MEDIUM" ]] || [[ "$copy_risk" == "MEDIUM" ]] || [ "$score" -lt 8 ]; then
                        medium_risk=$((medium_risk + 1))
                    else
                        low_risk=$((low_risk + 1))
                    fi
                fi
            fi
        done
        
        if [ $valid_scores -gt 0 ]; then
            local avg_score=$((total_score / valid_scores))
            echo "- **Average Originality Score:** $avg_score/10" >> "$export_file"
            echo "- **Low Risk Chapters:** $low_risk" >> "$export_file"
            echo "- **Medium Risk Chapters:** $medium_risk" >> "$export_file"
            echo "- **High Risk Chapters:** $high_risk" >> "$export_file"
        fi
    fi
    
    cat << EOF >> "$export_file"

---

## Chapter-by-Chapter Analysis

EOF
    
    # Add individual chapter reports
    for report in "${reports[@]}"; do
        if [ -f "$report" ]; then
            local chapter_num=$(basename "$report" | sed 's/chapter_\([0-9]*\)_plagiarism_report.md/\1/')
            echo "### Chapter $chapter_num" >> "$export_file"
            echo "" >> "$export_file"
            cat "$report" >> "$export_file"
            echo "" >> "$export_file"
            echo "---" >> "$export_file"
            echo "" >> "$export_file"
        fi
    done
    
    cat << EOF >> "$export_file"

## Recommendations

Based on this analysis, the following actions are recommended:

1. **High Risk Chapters:** Require immediate review and potential rewriting
2. **Medium Risk Chapters:** Should be manually reviewed for originality
3. **Low Risk Chapters:** Generally acceptable but brief review recommended
4. **Backup Files:** Original versions are preserved for comparison

## Technical Notes

- Plagiarism detection performed using Gemini LLM analysis
- Scores represent estimated originality on a 1-10 scale
- Risk levels combine plagiarism and copyright assessments
- This is an AI-assisted analysis and should be supplemented with human review

---

*Report generated by Plagiarism Report Manager*  
*$(date)*
EOF
    
    echo "✅ Consolidated report exported to: $(basename "$export_file")"
    echo "📁 Full path: $export_file"
    echo ""
    echo "📋 Report includes:"
    echo "   • Executive summary with statistics"
    echo "   • Chapter-by-chapter analysis"
    echo "   • Detailed plagiarism reports for each chapter"
    echo "   • Recommendations for next steps"
}

# Clean reports (with confirmation)
clean_reports() {
    local book_dir="$1"
    
    echo "🧹 Clean Plagiarism Reports and Backups"
    echo ""
    echo "⚠️  WARNING: This will permanently delete:"
    
    local reports=($(ls "${book_dir}"/chapter_*_plagiarism_report.md 2>/dev/null))
    local backups=($(ls "${book_dir}"/chapter_*.md.backup_* 2>/dev/null))
    local detailed=($(ls "${book_dir}"/chapter_*_detailed_analysis.md 2>/dev/null))
    
    echo "   📄 ${#reports[@]} plagiarism reports"
    echo "   📦 ${#backups[@]} backup files"
    echo "   📋 ${#detailed[@]} detailed analysis files"
    echo ""
    
    if [ ${#reports[@]} -eq 0 ] && [ ${#backups[@]} -eq 0 ] && [ ${#detailed[@]} -eq 0 ]; then
        echo "✅ No plagiarism-related files found to clean"
        return
    fi
    
    read -p "❓ Are you sure you want to delete these files? (type 'DELETE' to confirm): " confirm
    
    if [ "$confirm" = "DELETE" ]; then
        local deleted_count=0
        
        for file in "${reports[@]}" "${backups[@]}" "${detailed[@]}"; do
            if [ -f "$file" ]; then
                rm "$file"
                deleted_count=$((deleted_count + 1))
            fi
        done
        
        echo "✅ Deleted $deleted_count files successfully"
        echo "🧹 Plagiarism tracking data has been cleared"
    else
        echo "❌ Operation cancelled - no files deleted"
    fi
}

# Interactive menu
show_interactive_menu() {
    local book_dir="$1"
    
    while true; do
        clear
        echo "🔍 Plagiarism Report Manager"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📁 Book Directory: $(basename "$book_dir")"
        echo ""
        echo "Choose an action:"
        echo ""
        echo "1) 📊 Show Summary"
        echo "2) 📋 Show Detailed Reports"
        echo "3) 🚨 Show Flagged Chapters Only"
        echo "4) 📤 Export Consolidated Report"
        echo "5) 🧹 Clean Reports and Backups"
        echo "6) 🚪 Exit"
        echo ""
        read -p "Select option (1-6): " choice
        
        case $choice in
            1)
                clear
                show_summary "$book_dir"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                clear
                show_details "$book_dir"
                ;;
            3)
                clear
                show_flagged "$book_dir"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                clear
                export_report "$book_dir"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            5)
                clear
                clean_reports "$book_dir"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            6)
                echo "👋 Goodbye!"
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Please choose 1-6."
                sleep 2
                ;;
        esac
    done
}

# Main execution
main() {
    local book_dir="$1"
    local action="$2"
    
    # Show help if requested
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    # Get book directory
    book_dir=$(get_book_directory "$book_dir")
    
    # Execute action or show interactive menu
    case "$action" in
        summary)
            show_summary "$book_dir"
            ;;
        details)
            show_details "$book_dir"
            ;;
        flagged)
            show_flagged "$book_dir"
            ;;
        export)
            export_report "$book_dir"
            ;;
        clean)
            clean_reports "$book_dir"
            ;;
        "")
            show_interactive_menu "$book_dir"
            ;;
        *)
            echo "❌ Unknown action: $action"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# Check if running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
