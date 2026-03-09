#!/bin/bash
# backfill-sessions.sh — Process all existing Claude Code transcripts
# into one Obsidian note per session, then clean up duplicate notes.
#
# Usage: ./backfill-sessions.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

VAULT_DIR="$HOME/Documents/Obsidian Vault/Personal/sessions"
PROJECTS_DIR="$HOME/.claude/projects"
LOG_FILE="$HOME/.claude/hooks/backfill.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') — Backfill started (dry_run=$DRY_RUN) ==="

# ── Step 1: Clean up old per-Stop-event notes ────────────────────
echo ""
echo "--- Step 1: Removing old duplicate notes ---"
OLD_COUNT=$(find "$VAULT_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "Found $OLD_COUNT existing notes"

if [ "$OLD_COUNT" -gt 0 ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would remove $OLD_COUNT old notes from $VAULT_DIR"
  else
    find "$VAULT_DIR" -name "*.md" -type f -delete
    echo "Removed $OLD_COUNT old notes"
  fi
fi

# ── Step 2: Process each transcript ──────────────────────────────
echo ""
echo "--- Step 2: Processing transcripts ---"

TOTAL=0
SUCCESS=0
SKIPPED=0
FAILED=0

# Find all session transcripts (skip agent sub-sessions)
while IFS= read -r TRANSCRIPT_PATH; do
  TOTAL=$((TOTAL + 1))
  FILENAME=$(basename "$TRANSCRIPT_PATH" .jsonl)

  # Skip agent sub-sessions
  if echo "$FILENAME" | grep -q "^agent-"; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  SESSION_ID="$FILENAME"
  SESSION_SHORT="${SESSION_ID:0:8}"
  DIR_NAME=$(basename "$(dirname "$TRANSCRIPT_PATH")")

  # Get session date from first timestamp in transcript
  SESSION_DATE=$(python3 -c "
import json
with open('$TRANSCRIPT_PATH') as f:
    for line in f:
        try:
            obj = json.loads(line)
            ts = obj.get('timestamp', '')
            if ts:
                print(ts[:10])
                break
        except:
            continue
" 2>/dev/null)
  SESSION_DATE="${SESSION_DATE:-$(stat -f '%Sm' -t '%Y-%m-%d' "$TRANSCRIPT_PATH" 2>/dev/null || date +%Y-%m-%d)}"

  # Determine project/workspace/subfolder
  PROJECT=""
  WORKSPACE=""
  SUBFOLDER=""

  if echo "$DIR_NAME" | grep -q "conductor-workspaces"; then
    SUFFIX=$(echo "$DIR_NAME" | sed 's/.*conductor-workspaces-//')
    for PROJ_DIR in "$HOME/conductor/workspaces"/*/; do
      [ -d "$PROJ_DIR" ] || continue
      PROJ_NAME=$(basename "$PROJ_DIR")
      if echo "$SUFFIX" | grep -q "^${PROJ_NAME}-"; then
        PROJECT="$PROJ_NAME"
        WORKSPACE=$(echo "$SUFFIX" | sed "s/^${PROJ_NAME}-//")
        break
      fi
    done
    if [ -z "$PROJECT" ]; then
      PROJECT="conductor"
      WORKSPACE="$SUFFIX"
    fi
    SUBFOLDER="$PROJECT"
  else
    CLEAN=$(echo "$DIR_NAME" | sed 's/^-Users-[^-]*-//; s/^-//' | tr '-' '/')
    PROJECT="${CLEAN:-home}"
    SUBFOLDER=$(echo "$PROJECT" | tr '/' '-')
  fi

  NOTE_DIR="${VAULT_DIR}/${SUBFOLDER}"

  if [ -n "$WORKSPACE" ]; then
    NOTE_FILENAME="${SESSION_DATE}-${SESSION_SHORT}-${WORKSPACE}.md"
    TITLE="${PROJECT} / ${WORKSPACE}"
  else
    NOTE_FILENAME="${SESSION_DATE}-${SESSION_SHORT}.md"
    TITLE="$PROJECT"
  fi
  NOTE_FILENAME=$(echo "$NOTE_FILENAME" | tr '/' '-' | tr ' ' '-')
  FULL_PATH="${NOTE_DIR}/${NOTE_FILENAME}"

  # Extract conversation
  CONVERSATION=$(TRANSCRIPT_PATH="$TRANSCRIPT_PATH" python3 << 'PYEOF'
import json, os

transcript = os.environ["TRANSCRIPT_PATH"]
parts = []
for line in open(transcript):
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
  )

  EXCHANGE_COUNT=$(echo "$CONVERSATION" | grep -c "^\*\*User:\*\*\|^\*\*Assistant:\*\*" || true)

  # Skip trivial sessions (< 2 exchanges)
  if [ "$EXCHANGE_COUNT" -lt 2 ]; then
    echo "  [$TOTAL] SKIP $SESSION_SHORT ($SUBFOLDER) — only $EXCHANGE_COUNT exchanges"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  [$TOTAL] WOULD write $FULL_PATH ($EXCHANGE_COUNT exchanges)"
    SUCCESS=$((SUCCESS + 1))
    continue
  fi

  # Summarize
  SUMMARY=$(echo "$CONVERSATION" | env -u CLAUDE_CODE_ENTRYPOINT -u CLAUDECODE -u ANTHROPIC_API_KEY \
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

  if [ $? -ne 0 ] || [ -z "$SUMMARY" ]; then
    echo "  [$TOTAL] FAIL $SESSION_SHORT ($SUBFOLDER) — summarization failed"
    FAILED=$((FAILED + 1))
    continue
  fi

  mkdir -p "$NOTE_DIR"
  cat > "$FULL_PATH" << NOTEEOF
---
type: session-note
project: ${PROJECT}
workspace: ${WORKSPACE}
session_id: ${SESSION_ID}
date: ${SESSION_DATE}
transcript: ${TRANSCRIPT_PATH}
exchanges: ${EXCHANGE_COUNT}
tags:
  - session-note
  - ${SUBFOLDER}
---

# ${TITLE}
_${SESSION_DATE} | ${EXCHANGE_COUNT} exchanges_

${SUMMARY}
NOTEEOF

  if [ -f "$FULL_PATH" ]; then
    echo "  [$TOTAL] OK $SESSION_SHORT ($SUBFOLDER) — $EXCHANGE_COUNT exchanges"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  [$TOTAL] FAIL $SESSION_SHORT — write failed"
    FAILED=$((FAILED + 1))
  fi

done < <(find "$PROJECTS_DIR" -name "*.jsonl" -type f | sort)

echo ""
echo "=== Backfill complete ==="
echo "Total: $TOTAL | Written: $SUCCESS | Skipped: $SKIPPED | Failed: $FAILED"
