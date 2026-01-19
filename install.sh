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
if [ -d "$CONFIG_DIR/skills" ] && [ -n "$(ls -A "$CONFIG_DIR/skills" 2>/dev/null)" ]; then
    mkdir -p ~/.claude/skills
    for skill in "$CONFIG_DIR/skills"/*/; do
        [ -d "$skill" ] || continue
        skill_name=$(basename "$skill")
        ln -sfn "$skill" ~/.claude/skills/"$skill_name"
        echo "✓ skills/$skill_name"
    done
fi

# Agents (file symlinks per agent)
if [ -d "$CONFIG_DIR/agents" ] && ls "$CONFIG_DIR/agents"/*.md &>/dev/null; then
    mkdir -p ~/.claude/agents
    for agent in "$CONFIG_DIR/agents"/*.md; do
        [ -f "$agent" ] || continue
        agent_name=$(basename "$agent")
        ln -sf "$agent" ~/.claude/agents/"$agent_name"
        echo "✓ agents/$agent_name"
    done
fi

# Rules (file symlinks per rule)
if [ -d "$CONFIG_DIR/rules" ] && ls "$CONFIG_DIR/rules"/*.md &>/dev/null; then
    mkdir -p ~/.claude/rules
    for rule in "$CONFIG_DIR/rules"/*.md; do
        [ -f "$rule" ] || continue
        rule_name=$(basename "$rule")
        ln -sf "$rule" ~/.claude/rules/"$rule_name"
        echo "✓ rules/$rule_name"
    done
fi

echo ""
echo "Done! Claude Code config installed."
echo ""
echo "Local-only items in ~/.claude/ are preserved."
echo "Use ./sync.sh to manage what gets shared."
