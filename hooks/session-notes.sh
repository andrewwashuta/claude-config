#!/bin/bash
# session-notes.sh — Claude Code Stop hook
# Summarizes a CC session and writes/overwrites a single note per session
# in the Obsidian vault, organized into subfolders by project.

LOG_FILE="$HOME/.claude/hooks/session-notes.log"
exec >> "$LOG_FILE" 2>&1
echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') — Stop hook fired ==="

# Prevent recursion: claude -p fires Stop hook too
LOCK_FILE="/tmp/session-notes-hook.lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
  if [ "$LOCK_AGE" -lt 60 ]; then
    echo "Skipping — lock file exists (${LOCK_AGE}s old, likely recursive call). Exiting."
    exit 0
  else
    echo "Stale lock file (${LOCK_AGE}s old), removing and continuing."
    rm -f "$LOCK_FILE"
  fi
fi
touch "$LOCK_FILE"
trap 'sleep 5; rm -f "$LOCK_FILE"' EXIT

VAULT_DIR="$HOME/Documents/Obsidian Vault/Personal/sessions"

# ── Read hook input ──────────────────────────────────────────────
HOOK_INPUT=$(cat)
echo "Hook input: $HOOK_INPUT"

eval "$(echo "$HOOK_INPUT" | python3 -c "
import json, sys, shlex
data = json.load(sys.stdin)
print(f'TRANSCRIPT_PATH={shlex.quote(data.get(\"transcript_path\", \"\"))}')
print(f'SESSION_CWD={shlex.quote(data.get(\"cwd\", \"\"))}')
print(f'SESSION_ID={shlex.quote(data.get(\"session_id\", \"\"))}')
")"

echo "Transcript: $TRANSCRIPT_PATH"
echo "CWD: $SESSION_CWD"
echo "Session ID: $SESSION_ID"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "ERROR: transcript not found at '$TRANSCRIPT_PATH'. Exiting."
  exit 0
fi

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: no session_id. Exiting."
  exit 0
fi

# ── Determine project and subfolder ──────────────────────────────
DIR_NAME=$(basename "$(dirname "$TRANSCRIPT_PATH")")
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
  if [ -n "$SESSION_CWD" ]; then
    CLEAN=$(echo "$SESSION_CWD" | sed "s|^$HOME/||; s|^/Users/[^/]*/||; s|/$||")
    if [ -z "$CLEAN" ] || [ "$CLEAN" = "$SESSION_CWD" ]; then
      PROJECT="home"
    else
      PROJECT="$CLEAN"
    fi
  else
    CLEAN=$(echo "$DIR_NAME" | sed 's/^-Users-[^-]*-//; s/^-//' | tr '-' '/')
    PROJECT="${CLEAN:-misc}"
  fi
  SUBFOLDER=$(echo "$PROJECT" | tr '/' '-')
fi

echo "Project: $PROJECT | Workspace: $WORKSPACE | Subfolder: $SUBFOLDER"

# ── Get session start date from transcript ───────────────────────
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
SESSION_DATE="${SESSION_DATE:-$(date +%Y-%m-%d)}"

# ── Check for existing note for this session ─────────────────────
SESSION_SHORT="${SESSION_ID:0:8}"
NOTE_DIR="${VAULT_DIR}/${SUBFOLDER}"
mkdir -p "$NOTE_DIR"

# Find existing note for this session (glob on session ID prefix)
EXISTING=$(find "$NOTE_DIR" -name "*-${SESSION_SHORT}.md" -type f 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
  FULL_PATH="$EXISTING"
  echo "Updating existing note: $FULL_PATH"
else
  if [ -n "$WORKSPACE" ]; then
    FILENAME="${SESSION_DATE}-${SESSION_SHORT}-${WORKSPACE}.md"
  else
    FILENAME="${SESSION_DATE}-${SESSION_SHORT}.md"
  fi
  FILENAME=$(echo "$FILENAME" | tr '/' '-' | tr ' ' '-')
  FULL_PATH="${NOTE_DIR}/${FILENAME}"
  echo "Creating new note: $FULL_PATH"
fi

# ── Extract conversation ─────────────────────────────────────────
CONVERSATION=$(TRANSCRIPT_PATH="$TRANSCRIPT_PATH" python3 << 'PYEOF'
import json, sys, os

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
)

if [ $? -ne 0 ]; then
  echo "ERROR: transcript parsing failed"
  exit 0
fi

EXCHANGE_COUNT=$(echo "$CONVERSATION" | grep -c "^\*\*User:\*\*\|^\*\*Assistant:\*\*" || true)
echo "Exchange count: $EXCHANGE_COUNT"

# ── Summarize via claude CLI ─────────────────────────────────────
echo "Calling claude -p..."
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

CLAUDE_EXIT=$?
echo "claude -p exit: $CLAUDE_EXIT"

if [ $CLAUDE_EXIT -ne 0 ] || [ -z "$SUMMARY" ]; then
  echo "ERROR: claude -p failed. Output: $SUMMARY"
  SUMMARY="_Summarization failed (exit $CLAUDE_EXIT). Review transcript manually._

Exchanges: $EXCHANGE_COUNT"
fi

# ── Write/overwrite the note ─────────────────────────────────────
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

if [ -n "$WORKSPACE" ]; then
  TITLE="${PROJECT} / ${WORKSPACE}"
else
  TITLE="$PROJECT"
fi

cat > "$FULL_PATH" << NOTEEOF
---
type: session-note
project: ${PROJECT}
workspace: ${WORKSPACE}
session_id: ${SESSION_ID}
date: ${SESSION_DATE}
updated: ${TIMESTAMP}
transcript: ${TRANSCRIPT_PATH}
exchanges: ${EXCHANGE_COUNT}
tags:
  - session-note
  - ${SUBFOLDER}
---

# ${TITLE}
_${SESSION_DATE} | ${EXCHANGE_COUNT} exchanges | updated ${TIMESTAMP}_

${SUMMARY}
NOTEEOF

if [ -f "$FULL_PATH" ]; then
  echo "SUCCESS: $FULL_PATH ($(wc -c < "$FULL_PATH") bytes)"
else
  echo "ERROR: failed to write $FULL_PATH"
fi
