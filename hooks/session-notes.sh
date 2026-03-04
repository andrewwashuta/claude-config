#!/bin/bash
# session-notes.sh — Claude Code Stop hook
# Summarizes a CC session and writes a note to the Obsidian vault,
# organized into subfolders by project.

LOG_FILE="$HOME/.claude/hooks/session-notes.log"
exec >> "$LOG_FILE" 2>&1
echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') — Stop hook fired ==="

VAULT_DIR="$HOME/Documents/Obsidian Vault/Personal/sessions"

# ── Read hook input ──────────────────────────────────────────────
HOOK_INPUT=$(cat)
echo "Hook input: $HOOK_INPUT"

# Parse fields from JSON
eval "$(echo "$HOOK_INPUT" | python3 -c "
import json, sys, shlex
data = json.load(sys.stdin)
print(f'TRANSCRIPT_PATH={shlex.quote(data.get(\"transcript_path\", \"\"))}')
print(f'SESSION_CWD={shlex.quote(data.get(\"cwd\", \"\"))}')
print(f'SESSION_ID={shlex.quote(data.get(\"session_id\", \"\"))}')
print(f'LAST_MSG={shlex.quote(data.get(\"last_assistant_message\", \"\")[:200])}')
")"

echo "Transcript: $TRANSCRIPT_PATH"
echo "CWD: $SESSION_CWD"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "ERROR: transcript not found at '$TRANSCRIPT_PATH'. Exiting."
  exit 0
fi

# ── Determine project, workspace, and subfolder ─────────────────
DIR_NAME=$(basename "$(dirname "$TRANSCRIPT_PATH")")
PROJECT=""
WORKSPACE=""
SUBFOLDER=""

if echo "$DIR_NAME" | grep -q "conductor-workspaces"; then
  # Conductor: extract repo name + workspace (branch city name)
  SUFFIX=$(echo "$DIR_NAME" | sed 's/.*conductor-workspaces-//')

  # Match against known project directories
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
  # Non-conductor: derive a clean name from the cwd
  if [ -n "$SESSION_CWD" ]; then
    # Strip home prefix, use the last meaningful directory component
    CLEAN=$(echo "$SESSION_CWD" | sed "s|^$HOME/||; s|^/Users/[^/]*/||; s|/$||")
    if [ -z "$CLEAN" ] || [ "$CLEAN" = "$SESSION_CWD" ]; then
      PROJECT="home"
    else
      PROJECT="$CLEAN"
    fi
  else
    # Fallback: parse from the transcript directory name
    CLEAN=$(echo "$DIR_NAME" | sed 's/^-Users-[^-]*-//; s/^-//' | tr '-' '/')
    PROJECT="${CLEAN:-misc}"
  fi

  SUBFOLDER=$(echo "$PROJECT" | tr '/' '-')
fi

echo "Project: $PROJECT | Workspace: $WORKSPACE | Subfolder: $SUBFOLDER"

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

if [ "$EXCHANGE_COUNT" -lt 4 ]; then
  echo "Skipping — too few exchanges ($EXCHANGE_COUNT)"
  exit 0
fi

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

# ── Write the note ───────────────────────────────────────────────
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
DATE_SLUG=$(date +"%Y-%m-%d-%H%M")

if [ -n "$WORKSPACE" ]; then
  FILENAME="${DATE_SLUG}-${WORKSPACE}.md"
  TITLE="${PROJECT} / ${WORKSPACE}"
else
  FILENAME="${DATE_SLUG}.md"
  TITLE="$PROJECT"
fi

# Clean filename
FILENAME=$(echo "$FILENAME" | tr '/' '-' | tr ' ' '-')

# Create subfolder
NOTE_DIR="${VAULT_DIR}/${SUBFOLDER}"
mkdir -p "$NOTE_DIR"

FULL_PATH="${NOTE_DIR}/${FILENAME}"

cat > "$FULL_PATH" << NOTEEOF
---
type: session-note
project: ${PROJECT}
workspace: ${WORKSPACE}
date: ${TIMESTAMP}
transcript: ${TRANSCRIPT_PATH}
tags:
  - session-note
  - ${SUBFOLDER}
---

# ${TITLE}
_${TIMESTAMP}_

${SUMMARY}
NOTEEOF

if [ -f "$FULL_PATH" ]; then
  echo "SUCCESS: $FULL_PATH ($(wc -c < "$FULL_PATH") bytes)"
else
  echo "ERROR: failed to write $FULL_PATH"
fi
