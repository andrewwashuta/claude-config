#!/bin/bash
set -e

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Claude Code config from $CONFIG_DIR"
echo ""

mkdir -p ~/.claude

# Settings
if [ -f "$CONFIG_DIR/settings.json" ]; then
    ln -sf "$CONFIG_DIR/settings.json" ~/.claude/settings.json
    echo "✓ settings.json"
fi

# Statusline
if [ -f "$CONFIG_DIR/statusline.sh" ]; then
    ln -sf "$CONFIG_DIR/statusline.sh" ~/.claude/statusline.sh
    echo "✓ statusline.sh"
fi

# Skills (directory symlinks per skill)
mkdir -p ~/.claude/skills
for skill in "$CONFIG_DIR/skills"/*/; do
    [ -d "$skill" ] || continue
    skill_name=$(basename "$skill")
    ln -sfn "$skill" ~/.claude/skills/"$skill_name"
    echo "✓ skills/$skill_name"
done

echo ""
echo "Done! Claude Code config installed."
echo ""
echo "Local-only skills in ~/.claude/ are preserved."
echo "Use ./sync.sh to manage what gets shared."
