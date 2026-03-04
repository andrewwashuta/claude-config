#!/bin/bash
# backfill-notes.sh — Generate Obsidian session notes for old transcripts
# that existed before the Stop hook was set up.
#
# Usage:
#   ./backfill-notes.sh                     # Process all transcripts missing notes
#   ./backfill-notes.sh --dry-run           # Show what would be processed
#   ./backfill-notes.sh <transcript.jsonl>  # Process a specific transcript

set -u

VAULT_DIR="$HOME/Documents/Obsidian Vault/Personal/sessions"
PROJECTS_DIR="$HOME/.claude/projects"
LOG_FILE="$HOME/.claude/hooks/backfill-notes.log"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

DRY_RUN=false
SINGLE_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run|-n) DRY_RUN=true; shift ;;
    *) SINGLE_FILE="$1"; shift ;;
  esac
done

# ── Resolve project, workspace, subfolder from a transcript path ──
resolve_metadata() {
  local transcript="$1"
  local dir_name
  dir_name=$(basename "$(dirname "$transcript")")

  PROJECT=""
  WORKSPACE=""
  SUBFOLDER=""

  if echo "$dir_name" | grep -q "conductor-workspaces"; then
    local suffix
    suffix=$(echo "$dir_name" | sed 's/.*conductor-workspaces-//')

    for proj_dir in "$HOME/conductor/workspaces"/*/; do
      [ -d "$proj_dir" ] || continue
      local proj_name
      proj_name=$(basename "$proj_dir")
      if echo "$suffix" | grep -q "^${proj_name}-"; then
        PROJECT="$proj_name"
        WORKSPACE=$(echo "$suffix" | sed "s/^${proj_name}-//")
        break
      fi
    done

    if [ -z "$PROJECT" ]; then
      PROJECT="conductor"
      WORKSPACE="$suffix"
    fi
    SUBFOLDER="$PROJECT"
  else
    local clean
    clean=$(echo "$dir_name" | sed 's/^-Users-[^-]*-//; s/^-//' | tr '-' '/')
    PROJECT="${clean:-home}"
    SUBFOLDER=$(echo "$PROJECT" | tr '/' '-')
  fi
}

# ── Check if a note already exists for a transcript ──
note_exists() {
  local transcript="$1"
  grep -rl "transcript: ${transcript}" "$VAULT_DIR" 2>/dev/null | head -1
}

# ── Extract conversation text from JSONL ──
extract_conversation() {
  local transcript="$1"
  TRANSCRIPT_PATH="$transcript" python3 << 'PYEOF'
import json, os

transcript = os.environ["TRANSCRIPT_PATH"]
lines = open(transcript, "r").readlines()
parts = []
for line in lines:
    try:
        obj = json.loads(line)
    except:
        continue
    msg_type = obj.get("type", "")
    if msg_type not in ("user", "assistant"):
        continue
    role = "User" if msg_type == "user" else "Assistant"
    msg = obj.get("message", {})
    content = msg.get("content", "") if isinstance(msg, dict) else ""
    text = ""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text += block["text"] + "\n"
            elif isinstance(block, dict) and block.get("type") == "tool_use":
                text += f'[Used tool: {block.get("name", "?")}]\n'
    text = text.strip()
    if not text:
        continue
    if len(text) > 2000:
        text = text[:2000] + "... [truncated]"
    parts.append(f"**{role}:** {text}\n")
output = "\n".join(parts)
if len(output) > 60000:
    output = output[:60000] + "\n\n[... truncated]"
print(output)
PYEOF
}

# ── Process a single transcript ──
process_transcript() {
  local transcript="$1"

  # Check if note already exists
  local existing
  existing=$(note_exists "$transcript")
  if [ -n "$existing" ]; then
    echo -e "  ${YELLOW}skip${RESET} — note exists at $(basename "$existing")"
    return
  fi

  resolve_metadata "$transcript"

  # Get transcript modification date for the note timestamp
  local file_date
  file_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$transcript" 2>/dev/null \
    || stat -c "%y" "$transcript" 2>/dev/null | cut -d. -f1)
  local date_slug
  date_slug=$(stat -f "%Sm" -t "%Y-%m-%d-%H%M" "$transcript" 2>/dev/null \
    || date -d "$(stat -c "%y" "$transcript" 2>/dev/null)" +"%Y-%m-%d-%H%M")

  if $DRY_RUN; then
    local exchanges
    exchanges=$(TRANSCRIPT_PATH="$transcript" python3 -c "
import json, os
lines = open(os.environ['TRANSCRIPT_PATH']).readlines()
count = sum(1 for l in lines if json.loads(l).get('type','') in ('user','assistant') for _ in [None] if True)
print(count)
" 2>/dev/null || echo "?")
    echo -e "  ${BLUE}would process${RESET} — $PROJECT${WORKSPACE:+/$WORKSPACE} ($exchanges exchanges)"
    return
  fi

  echo -n "  extracting... "
  local conversation
  conversation=$(extract_conversation "$transcript")
  local exchange_count
  exchange_count=$(echo "$conversation" | grep -c '^\*\*User:\*\*\|^\*\*Assistant:\*\*' || true)
  echo "$exchange_count exchanges"

  echo -n "  summarizing... "
  local summary
  summary=$(echo "$conversation" | env -u CLAUDE_CODE_ENTRYPOINT -u CLAUDECODE -u ANTHROPIC_API_KEY \
    claude -p --model haiku "You are summarizing a Claude Code session transcript.

Context: project='$PROJECT', workspace='$WORKSPACE'

Write a concise Obsidian note. Use this format exactly:

## What happened
A short paragraph (2-4 sentences) describing what was accomplished in plain language. Be specific about outcomes, not process.

## Decisions
- Bullet any meaningful technical or design choices. Skip if none.

## Files touched
- List key files created or modified. Skip lock files, node_modules, etc. If unclear, describe the area of code.

## Still open
- Anything unresolved, left as a TODO, or to revisit next session. Write 'Nothing — wrapped up cleanly.' if none.

Be concise and direct. No preamble, no 'Here is the summary' intro." 2>&1)

  if [ $? -ne 0 ] || [ -z "$summary" ]; then
    echo "failed"
    echo "  ERROR: claude -p failed: $summary" >> "$LOG_FILE"
    summary="_Summarization failed. Review transcript manually._

Exchanges: $exchange_count"
  else
    echo "done"
  fi

  # Build filename and write note
  local filename
  if [ -n "$WORKSPACE" ]; then
    filename="${date_slug}-${WORKSPACE}.md"
  else
    filename="${date_slug}.md"
  fi
  filename=$(echo "$filename" | tr '/' '-' | tr ' ' '-')

  local note_dir="${VAULT_DIR}/${SUBFOLDER}"
  mkdir -p "$note_dir"
  local full_path="${note_dir}/${filename}"

  local title="${PROJECT}${WORKSPACE:+ / $WORKSPACE}"

  cat > "$full_path" << NOTEEOF
---
type: session-note
project: ${PROJECT}
workspace: ${WORKSPACE}
date: ${file_date}
transcript: ${transcript}
backfilled: true
tags:
  - session-note
  - ${SUBFOLDER}
---

# ${title}
_${file_date}_

${summary}
NOTEEOF

  echo -e "  ${GREEN}✓${RESET} $full_path"
}

# ── Main ──
if [ -n "$SINGLE_FILE" ]; then
  if [ ! -f "$SINGLE_FILE" ]; then
    echo "File not found: $SINGLE_FILE"
    exit 1
  fi
  echo "Processing: $(basename "$SINGLE_FILE")"
  process_transcript "$SINGLE_FILE"
else
  echo "Scanning for transcripts without notes..."
  if $DRY_RUN; then
    echo -e "${BLUE}(dry run — no changes will be made)${RESET}"
  fi
  echo ""

  count=0
  processed=0
  for jsonl in "$PROJECTS_DIR"/*/*.jsonl; do
    [ -f "$jsonl" ] || continue
    count=$((count + 1))
    dir_name=$(basename "$(dirname "$jsonl")")
    session_id=$(basename "$jsonl" .jsonl)
    echo "[$dir_name / $session_id]"
    process_transcript "$jsonl"
    processed=$((processed + 1))
  done

  echo ""
  echo "Done. Scanned $count transcripts."
fi
