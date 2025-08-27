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
COOLDOWN_JITTER=${COOLDOWN_JITTER:-30} # random jitter max
MAX_RETRIES=${MAX_RETRIES:-2}

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

# Source the multi-provider helper (smart_api_call) if present
if [ -f "$SCRIPT_DIR/multi_provider_ai_simple.sh" ]; then
  # shellcheck source=/dev/null
  . "$SCRIPT_DIR/multi_provider_ai_simple.sh"
else
  log "Warning: multi_provider_ai_simple.sh not found; will attempt direct Gemini calls"
fi

random_sleep() {
  local jitter=$((RANDOM % COOLDOWN_JITTER))
  local delay=$((COOLDOWN_BASE + jitter))
  log "Cooling down for ${delay}s (base=${COOLDOWN_BASE}s jitter=${jitter}s)"
  sleep "$delay"
}

build_seen_list() {
  # produce a compact JSON array of keys (url/doi/title) already seen
  jq -s '[ .[] | .sources[]? ] | map({key: ((.url // .doi // .title) | ascii_downcase)}) | map(select(.key != null and .key != "")) | unique_by(.key) | map(.key)' "$SOURCES_DIR"/*_sources.json 2>/dev/null || echo '[]'
}

call_gemini_raw() {
  local prompt_text="$1"
  local out_file="$2"
  local attempt=0
  while :; do
    attempt=$((attempt+1))
    curl -sS -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_KEY}" \
      -H 'Content-Type: application/json' \
      -d @- >"$out_file" <<EOF || true
{
  "contents": [{"parts": [{"text": $(printf '%s' "$prompt_text" | jq -Rs .)}]}],
  "generationConfig": {"temperature": 0.2, "topP": 0.95, "maxOutputTokens": 8192}
}
EOF
    if [ -s "$out_file" ] && grep -q '{' "$out_file" 2>/dev/null; then
      return 0
    fi
    if [ $attempt -ge $MAX_RETRIES ]; then
      return 1
    fi
    sleep 3
  done
}

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

# Main processing
chapter_files=("$BOOK_DIR"/chapter_*.md)
[ -e "${chapter_files[0]:-}" ] || { log "No chapters found in $BOOK_DIR"; exit 0; }

total=${#chapter_files[@]}
log "Found $total chapters; batch size $BATCH_SIZE"

i=0
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
  if ! call_gemini_raw "$PROMPT" "$RAW_OUT"; then
    log "Gemini call failed for batch; saving raw output"
    cp "$RAW_OUT" "$SOURCES_DIR/batch_error_$(date +%s).txt" || true
    random_sleep
    continue
  fi

  JSON_OUT="$TEMP_DIR/parsed_$(date +%s).json"
  extract_json_block "$RAW_OUT" "$JSON_OUT"

  if jq -e . "$JSON_OUT" >/dev/null 2>&1; then
    # split chapters to per-chapter files
    jq -c '.chapters[]' "$JSON_OUT" | while read -r chap; do
      chap_name=$(echo "$chap" | jq -r '.chapter')
      safe=$(basename "$chap_name")
      out="$SOURCES_DIR/${safe}_sources.json"
      echo "$chap" | jq '.' > "$out"
      log "Wrote sources for $safe -> $out"
      # merge into seen index
      merge_into_seen "$out"
    done
  else
    log "Invalid JSON from Gemini; saving raw to $SOURCES_DIR"
    cp "$RAW_OUT" "$SOURCES_DIR/raw_invalid_$(date +%s).txt"
  fi

  # cooldown with jitter
  random_sleep
done

# Consolidate seen files into final bibliography markdown
log "Consolidating seen sources into $FINAL_MD"
cat > "$FINAL_MD" <<EOF

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

  echo "## $count. $title" >> "$FINAL_MD"
  [ -n "$authors" ] && echo "- **Authors:** $authors" >> "$FINAL_MD"
  [ -n "$pub" ] && echo "- **Publisher:** $pub" >> "$FINAL_MD"
  [ -n "$datep" ] && echo "- **Date:** $datep" >> "$FINAL_MD"
  [ -n "$url" ] && echo "- **URL:** $url" >> "$FINAL_MD"
  [ -n "$doi" ] && echo "- **DOI:** $doi" >> "$FINAL_MD"
  [ -n "$relevance" ] && echo "- **Relevance:** $relevance/10" >> "$FINAL_MD"
  echo "- **Referenced in:** $chapters" >> "$FINAL_MD"
  [ -n "$summary" ] && echo "- **Summary:** $summary" >> "$FINAL_MD"
  if [ -n "$apa" ] || [ -n "$mla" ]; then
    echo "- **Citations:**" >> "$FINAL_MD"
    [ -n "$apa" ] && echo "  - APA: $apa" >> "$FINAL_MD"
    [ -n "$mla" ] && echo "  - MLA: $mla" >> "$FINAL_MD"
  fi
  echo "" >> "$FINAL_MD"
  echo "---" >> "$FINAL_MD"
  echo "" >> "$FINAL_MD"
done

log "Final bibliography written to $FINAL_MD (sources: $count)"
exit 0
