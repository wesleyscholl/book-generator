#!/usr/bin/env bash
# Generate references for a book using Gemini (shell-only)
# Usage: generate_references.sh /path/to/book [batch_size]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
BOOK_DIR="${1:-.}"
BATCH_SIZE="${2:-2}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-1.5-pro}"
GEMINI_KEY="${GEMINI_API_KEY:-}" # must be exported by caller/user
COOLDOWN_BASE=${COOLDOWN_BASE:-60}   # base seconds
COOLDOWN_JITTER=${COOLDOWN_JITTER:-10} # random jitter max
MAX_RETRIES=${MAX_RETRIES:-2}

MAX_TOKENS=65000
SOURCES_DIR="$BOOK_DIR/sources"
TEMP_DIR="$BOOK_DIR/temp_refs"
SEEN_DIR="$TEMP_DIR/seen"
FINAL_MD="$BOOK_DIR/final_bibliography.md"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || command -v sha1sum >/dev/null 2>&1 || { echo "shasum/sha1sum required" >&2; exit 1; }
[ -n "$GEMINI_KEY" ] || { echo "GEMINI_API_KEY environment variable must be set" >&2; exit 1; }

mkdir -p "$SOURCES_DIR" "$TEMP_DIR" "$SEEN_DIR"

log() { printf '%s %s\n' "[refs]" "$*"; }

# Animation function for waiting periods
show_wait_animation() {
    local wait_time=$1
    local message=$2
    local animation_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local start_time=$(date +%s)
    local end_time=$((start_time + wait_time))
    local current_time=$start_time
    
    # Hide cursor
    echo -en "\033[?25l"
    
    while [ $current_time -lt $end_time ]; do
        local remaining=$((end_time - current_time))
        local char="${animation_chars[$i]}"
        echo -ne "\r${CYAN}${char}${RESET} ${message} (${YELLOW}${remaining}s${RESET} remaining)     "
        i=$(((i + 1) % ${#animation_chars[@]}))
        sleep 0.1
        current_time=$(date +%s)
    done
    
    # Show cursor and clear line
    echo -e "\r\033[K${GREEN}✓${RESET} ${message} completed!     "
    echo -en "\033[?25h"
}

# Source the multi-provider helper (smart_api_call). This script requires it.
if [ -f "$SCRIPT_DIR/multi_provider_ai_simple.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/multi_provider_ai_simple.sh"
else
  log "ERROR: multi_provider_ai_simple.sh not found; this script now requires smart_api_call. Please place multi_provider_ai_simple.sh alongside this script."
  exit 1
fi

random_sleep() {
  local jitter=$((RANDOM % COOLDOWN_JITTER))
  local delay=$((COOLDOWN_BASE + jitter))
  log "Cooling down for ${delay}s (base=${COOLDOWN_BASE}s jitter=${jitter}s)"
  # API rate limit delay
  show_wait_animation "$delay" "API cooldown"
}

build_seen_list() {
  # produce a compact JSON array of keys (url/doi/title) already seen
  jq -s '[ .[] | .sources[]? ] | map({key: ((.url // .doi // .title) | ascii_downcase)}) | map(select(.key != null and .key != "")) | unique_by(.key) | map(.key)' "$SOURCES_DIR"/*_sources.json 2>/dev/null || echo '[]'
}

# NOTE: direct Gemini HTTP caller removed. This script requires multi_provider_ai_simple.sh
# which provides smart_api_call. All API requests use smart_api_call now.

extract_json_block() {
  local raw=$1
  local dst=$2
  if grep -q '```json' "$raw" 2>/dev/null; then
    sed -n '/```json/,/```/p' "$raw" | sed '1d;$d' > "$dst" && return 0
  fi
  # naive first { ... } block
  awk 'BEGIN{p=0} /\{/ {if(!p){p=1; print; next}} p{print} /\}/{if(p){exit}}' "$raw" > "$dst" && return 0
  cp "$raw" "$dst"
}

sanitize_key() {
  # lowercase and trim
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^\s*//;s/\s*$//'
}

merge_into_seen() {
  local chapter_json="$1"
  # iterate sources
  jq -c '.sources[]' "$chapter_json" 2>/dev/null | while read -r src; do
    local url; url=$(echo "$src" | jq -r '.url // empty')
    local doi; doi=$(echo "$src" | jq -r '.doi // empty')
    local title; title=$(echo "$src" | jq -r '.title // empty')
    local rawkey; rawkey="${url:-${doi:-${title:-}}}"
    [ -n "$rawkey" ] || continue
    local key; key=$(sanitize_key "$rawkey")
    local sig; sig=$(printf '%s' "$key" | (command -v shasum >/dev/null 2>&1 && shasum -a 1 || sha1sum) | awk '{print $1}')
    local out="$SEEN_DIR/$sig.json"
    if [ ! -f "$out" ]; then
      # create new seen file
      echo "$src" | jq '. + {chapters:[ (input_filename // empty) ] }' --arg input_filename "$(basename "$chapter_json" .json)" > "$out" 2>/dev/null || echo "$src" > "$out"
    else
      # merge chapters and authors
      tmp=$(mktemp)
      jq -s '.[0] as $a | .[1] as $b | ($a + $b) | .chapters = ((($a.chapters//[]) + ($b.chapters//[])) | unique) | .authors = ((($a.authors//[]) + ($b.authors//[])) | unique)' "$out" <(echo "$src" | jq '. + {chapters:[ (input_filename // empty) ] }' --arg input_filename "$(basename "$chapter_json" .json)") > "$tmp"
      mv "$tmp" "$out"
    fi
  done
}

generate_prompt_for_batch() {
  # Accept files as positional arguments to avoid 'local -n' namerefs (macOS bash lacks them)
  local files=("$@")
  local seen_json
  seen_json=$(build_seen_list)
  # Build prompt with seen keys to avoid duplicates
  local p="You are a research assistant. For each chapter provided, return a JSON object: {\"chapter\": \"<filename>\", \"sources\": [ ... ]} inside a top-level {\"chapters\": [ ... ] } array.\n\n"
  p+="ALSO: here is a JSON array of keys (url/doi/title) of sources we already have; DO NOT RETURN sources whose url/doi/title matches any of these keys.\n"
  p+="ExistingSourcesKeys: $(printf '%s' "$seen_json")\n\n"
  p+="Return pure JSON only. For each source provide fields: id,type,title,authors,url,publication_date,publisher,doi,isbn,relevance_score,citation_apa,citation_mla,summary,key_quotes. If no sources are found for a chapter return \"sources\": [] for that chapter.\n\n"
  for f in "${files[@]}"; do
    p+="===CHAPTER: $(basename "$f")===\n"
    p+="$(sed -n '1,1200p' "$f")\n\n"
  done
  printf '%s' "$p"
}

# How many times to retry a single chapter when API returns an empty sources array
CHAPTER_RETRIES=${CHAPTER_RETRIES:-3}

# Main processing
# Build a numerically-sorted list of chapter files (chapter_1.md, chapter_2.md ...)
chapter_files=()
if ls "$BOOK_DIR"/chapter_*.md >/dev/null 2>&1; then
  # create list with numeric prefix for safe sorting
  # Use a direct loop on chapter files (avoid subshell array population issues)
  for f in "$BOOK_DIR"/chapter_*.md; do
    [ -f "$f" ] || continue
    chapter_files+=("$f")
  done
  
  # Sort the array by numeric chapter number
  if [ ${#chapter_files[@]} -gt 0 ]; then
    # Create a temporary file for sorting
    SORT_TMP=$(mktemp)
    # Write chapter files with their numeric indices for sorting
    for f in "${chapter_files[@]}"; do
      base=$(basename "$f")
      num=$(echo "$base" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
      if printf '%s' "$num" | grep -qE '^[0-9]+$'; then
        printf "%s\t%s\n" "$num" "$f"
      fi
    done | sort -n -k1,1 > "$SORT_TMP"
    
    # Clear and rebuild the array in sorted order
    chapter_files=()
    while IFS=$'\t' read -r _ path; do
      chapter_files+=("$path")
    done < "$SORT_TMP"
    rm -f "$SORT_TMP"
  fi
  # Count matched chapter files without expanding the array (avoid unbound var with set -u)
  matched_count=0
  for _cf in "$BOOK_DIR"/chapter_*.md; do
    [ -f "$_cf" ] || continue
    matched_count=$((matched_count + 1))
  done
  log "Matched ${matched_count} chapter files in $BOOK_DIR"
fi

[ -e "${chapter_files[0]:-}" ] || { log "No chapters found in $BOOK_DIR"; exit 0; }

total=${#chapter_files[@]}
log "Found $total chapters (numerically ordered); batch size $BATCH_SIZE"

# Determine resume index from existing per-chapter source files.
# Find the lowest chapter index that doesn't have a corresponding source file.
# Determine START_CHAPTER from existing per-chapter sources files if not set.
if [ -z "${START_CHAPTER:-}" ]; then
  START_CHAPTER=1
  
  # Check if any source files exist
  if compgen -G "${BOOK_DIR}/sources/chapter_*.md_sources.json" > /dev/null 2>&1; then
    # Find which chapters already have source files
    existing_chapters=()
    missing_chapters=()
    
    # First identify chapter numbers from the original chapter files
    all_chapter_nums=()
    for f in "${chapter_files[@]}"; do
      base=$(basename "$f")
      num=$(echo "$base" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
      if printf '%s' "$num" | grep -qE '^[0-9]+$'; then
        all_chapter_nums+=("$num")
      fi
    done
    
    # Then identify chapters that have source files
    for f in "${BOOK_DIR}"/sources/chapter_*.md_sources.json; do
      base=$(basename "$f")
      num=$(echo "$base" | sed -E 's/chapter_([0-9]+)\.md_sources\.json/\1/')
      if [[ "$num" =~ ^[0-9]+$ ]]; then
        existing_chapters+=("$num")
      fi
    done
    
    # Find lowest missing chapter number
    for num in "${all_chapter_nums[@]}"; do
      found=false
      for enum in "${existing_chapters[@]}"; do
        if [ "$num" -eq "$enum" ]; then
          found=true
          break
        fi
      done
      if [ "$found" = false ]; then
        missing_chapters+=("$num")
      fi
    done
    
    # Sort missing chapters to find the lowest
    if [ ${#missing_chapters[@]} -gt 0 ]; then
      # Create a temporary file for sorting
      SORT_TMP=$(mktemp)
      for num in "${missing_chapters[@]}"; do
        echo "$num"
      done | sort -n > "$SORT_TMP"
      
      # Get the lowest missing chapter
      lowest_missing=$(head -n 1 "$SORT_TMP")
      rm -f "$SORT_TMP"
      
      if [ -n "$lowest_missing" ]; then
        START_CHAPTER=$lowest_missing
      fi
    else
      # All chapters have source files, start after the highest
      max=0
      for num in "${existing_chapters[@]}"; do
        if [ "$num" -gt "$max" ]; then
          max=$num
        fi
      done
      START_CHAPTER=$((max + 1))
    fi
  fi
  log "Resuming from chapter: $START_CHAPTER"
fi

# Find the first chapter file whose numeric index is >= START_CHAPTER
start_index=0
for idx in "${!chapter_files[@]}"; do
  b=$(basename "${chapter_files[idx]}")
  num=$(echo "$b" | sed -E 's/[^0-9]*([0-9]+).*/\1/')
  if printf '%s' "$num" | grep -qE '^[0-9]+$' && [ "$num" -ge "$START_CHAPTER" ]; then
    start_index=$idx
    break
  fi
done

if [ "$start_index" -ge "$total" ]; then
  log "All chapters already processed (start_index $start_index >= total $total); nothing to do."
  exit 0
fi

i=$start_index
while [ $i -lt $total ]; do
  batch_files=()
  for ((k=0;k<BATCH_SIZE && i<total; k++)); do
    f=${chapter_files[i]}
    base=$(basename "$f")
    if [ -f "$SOURCES_DIR/${base}_sources.json" ]; then
      log "Skipping already-processed $base"
      i=$((i+1))
      continue
    fi
    batch_files+=("$f")
    i=$((i+1))
  done
  [ ${#batch_files[@]} -gt 0 ] || { log "No unprocessed files in this pass"; break; }

  log "Processing batch: ${batch_files[*]}"
  # pass batch_files elements as positional args
  PROMPT=$(generate_prompt_for_batch "${batch_files[@]}")
  RAW_OUT="$TEMP_DIR/raw_$(date +%s).txt"

  # Call smart_api_call (multi-provider helper is required)
  log "Calling smart_api_call for batch"
  if ! smart_api_call "$PROMPT" "" "general" 0.2 $MAX_TOKENS $MAX_RETRIES "" > "$RAW_OUT" 2>/dev/null; then
    log "smart_api_call failed for batch; saving raw output"
    cp "$RAW_OUT" "$SOURCES_DIR/batch_error_$(date +%s).txt" || true
    random_sleep
    continue
  fi

  JSON_OUT="$TEMP_DIR/parsed_$(date +%s).json"
  extract_json_block "$RAW_OUT" "$JSON_OUT"

  if jq -e . "$JSON_OUT" >/dev/null 2>&1; then
    # For each chapter returned, write out and handle empty-source retries
    jq -c '.chapters[]' "$JSON_OUT" | while read -r chap; do
      chap_name=$(echo "$chap" | jq -r '.chapter')
      safe=$(basename "$chap_name")
      out="$SOURCES_DIR/${safe}_sources.json"

      # Check if sources array is empty
      src_count=$(echo "$chap" | jq '.sources | length' 2>/dev/null || echo 0)
      attempt=0
      if [ "$src_count" -eq 0 ]; then
        # Retry this chapter individually up to CHAPTER_RETRIES with cooldown
        while [ $attempt -lt $CHAPTER_RETRIES ] && [ "$src_count" -eq 0 ]; do
          attempt=$((attempt + 1))
          log "Empty sources for $safe; retry attempt $attempt/$CHAPTER_RETRIES"
          # regenerate prompt for this single chapter and call API
          SINGLE_PROMPT=$(generate_prompt_for_batch "$BOOK_DIR/$safe")
          SINGLE_OUT="$TEMP_DIR/raw_retry_${safe}_$(date +%s).txt"
          # retry using smart_api_call
          if ! smart_api_call "$SINGLE_PROMPT" "" "general" 0.2 $MAX_TOKENS $MAX_RETRIES "" > "$SINGLE_OUT" 2>/dev/null; then
            log "smart_api_call retry failed for $safe (attempt $attempt)"
          fi
          # try to extract JSON
          extract_json_block "$SINGLE_OUT" "$TEMP_DIR/parsed_retry_${safe}_$(date +%s).json" || true
          # read sources length if possible
          if jq -e . "$TEMP_DIR/parsed_retry_${safe}_$(date +%s).json" >/dev/null 2>&1; then
            newsrc_count=$(jq '.chapters[0].sources | length' "$TEMP_DIR/parsed_retry_${safe}_$(date +%s).json" 2>/dev/null || echo 0)
            if [ "$newsrc_count" -gt 0 ]; then
              # replace chap with new content
              chap=$(jq -c '.chapters[0]' "$TEMP_DIR/parsed_retry_${safe}_$(date +%s).json")
              src_count=$newsrc_count
              log "Retry for $safe returned $src_count sources"
            fi
          fi
          # cooldown before next retry
          random_sleep
        done
      fi

      # write result (either original or retried)
      echo "$chap" | jq '.' > "$out"
      log "Wrote sources for $safe -> $out (sources: ${src_count:-0})"
      # merge into seen index
      merge_into_seen "$out"
    done
  else
    log "Invalid JSON from Gemini; saving raw to $SOURCES_DIR"
    cp "$RAW_OUT" "$SOURCES_DIR/raw_invalid_$(date +%s).txt"
  fi
done

# Check for any missing chapter source files and retry them before final consolidation
check_missing_sources() {
  local missing_chapters=()
  log "Checking for missing source files..."
  
  for chap_file in "${chapter_files[@]}"; do
    base=$(basename "$chap_file")
    if [ ! -f "$SOURCES_DIR/${base}_sources.json" ]; then
      log "Found missing source file for $base"
      missing_chapters+=("$chap_file")
    fi
  done
  
  if [ ${#missing_chapters[@]} -gt 0 ]; then
    log "Retrying ${#missing_chapters[@]} missing chapters before consolidation"
    
    # Process each missing chapter individually
    for f in "${missing_chapters[@]}"; do
      base=$(basename "$f")
      log "Retrying missing chapter: $base"
      
      # Generate prompt for single chapter
      SINGLE_PROMPT=$(generate_prompt_for_batch "$f")
      SINGLE_OUT="$TEMP_DIR/raw_missing_${base}_$(date +%s).txt"
      
      # Call API
      if ! smart_api_call "$SINGLE_PROMPT" "" "general" 0.2 $MAX_TOKENS $MAX_RETRIES "" > "$SINGLE_OUT" 2>/dev/null; then
        log "smart_api_call failed for missing chapter $base"
        continue
      fi
      
      # Extract JSON
      SINGLE_JSON="$TEMP_DIR/parsed_missing_${base}_$(date +%s).json"
      extract_json_block "$SINGLE_OUT" "$SINGLE_JSON"
      
      if jq -e . "$SINGLE_JSON" >/dev/null 2>&1; then
        # Get the chapter data and write to sources
        chap=$(jq -c '.chapters[0]' "$SINGLE_JSON" 2>/dev/null)
        if [ -n "$chap" ]; then
          out="$SOURCES_DIR/${base}_sources.json"
          echo "$chap" | jq '.' > "$out"
          src_count=$(echo "$chap" | jq '.sources | length' 2>/dev/null || echo 0)
          log "Wrote sources for missing $base -> $out (sources: ${src_count:-0})"
          # Merge into seen index
          merge_into_seen "$out"
        fi
      else
        log "Invalid JSON from retrying missing chapter $base"
      fi
      
      # Cooldown between chapters
      random_sleep
    done
  else
    log "No missing source files detected"
  fi
}

# Run check for missing chapters before final consolidation
check_missing_sources

# Consolidate seen files into final bibliography markdown
log "Consolidating seen sources into $FINAL_MD"
cat > "$FINAL_MD" <<EOF
## Citations
EOF

count=0
for f in "$SEEN_DIR"/*.json; do
  [ -f "$f" ] || continue
  count=$((count+1))
  title=$(jq -r '.title // "Untitled"' "$f")
  authors=$(jq -r '.authors // [] | join(", ")' "$f")
  url=$(jq -r '.url // empty' "$f")
  doi=$(jq -r '.doi // empty' "$f")
  pub=$(jq -r '.publisher // empty' "$f")
  datep=$(jq -r '.publication_date // empty' "$f")
  relevance=$(jq -r '.relevance_score // empty' "$f")
  chapters=$(jq -r '.chapters | join(", ")' "$f")
  apa=$(jq -r '.citation_apa // empty' "$f")
  mla=$(jq -r '.citation_mla // empty' "$f")
  summary=$(jq -r '.summary // empty' "$f")

  echo "#### $count. $title" >> "$FINAL_MD"
  [ -n "$mla" ] && echo "  - $mla" >> "$FINAL_MD"

#   [ -n "$authors" ] && echo "- **Authors:** $authors" >> "$FINAL_MD"
#   [ -n "$pub" ] && echo "- **Publisher:** $pub" >> "$FINAL_MD"
#   [ -n "$datep" ] && echo "- **Date:** $datep" >> "$FINAL_MD"
#   [ -n "$url" ] && echo "- **URL:** $url" >> "$FINAL_MD"
#   [ -n "$doi" ] && [ "$doi" != "n/a" ] && [ "$doi" != "N/A" ] && [ "$doi" != "" ] && echo "- **DOI:** $doi" >> "$FINAL_MD"
# #   [ -n "$summary" ] && echo "- **Summary:** $summary" >> "$FINAL_MD"
#   if [ -n "$apa" ] || [ -n "$mla" ]; then
#     echo "- **Citations:**" >> "$FINAL_MD"
#     [ -n "$apa" ] && echo "  - APA: $apa" >> "$FINAL_MD"
#     [ -n "$mla" ] && echo "  - MLA: $mla" >> "$FINAL_MD"
#   fi
  echo "" >> "$FINAL_MD"
  
done

echo "---" >> "$FINAL_MD"

log "Final bibliography written to $FINAL_MD (sources: $count)"
exit 0
