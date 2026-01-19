#!/bin/bash
set -e

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for output
BOLD='\033[1m'
RESET='\033[0m'

# Show status for a directory-based item (skills)
show_dir_status() {
    local type="$1"
    local local_dir="$HOME/.claude/$type"
    local repo_dir="$CONFIG_DIR/$type"

    for item in "$local_dir"/*/; do
        [ -d "$item" ] || continue
        item_name=$(basename "$item")
        item_path="$local_dir/$item_name"

        if [ -L "$item_path" ]; then
            target=$(readlink "$item_path")
            if [[ "$target" == "$CONFIG_DIR"* ]]; then
                echo "  ✓ $item_name (synced)"
            else
                echo "  → $item_name (symlink to elsewhere)"
            fi
        else
            if [ -d "$repo_dir/$item_name" ]; then
                echo "  ⚠ $item_name (exists in both - local copy)"
            else
                echo "  ○ $item_name (local only)"
            fi
        fi
    done
}

# Show status for a file-based item (agents, rules)
show_file_status() {
    local type="$1"
    local local_dir="$HOME/.claude/$type"
    local repo_dir="$CONFIG_DIR/$type"

    for item in "$local_dir"/*.md; do
        [ -f "$item" ] || continue
        item_name=$(basename "$item")
        item_path="$local_dir/$item_name"

        if [ -L "$item_path" ]; then
            target=$(readlink "$item_path")
            if [[ "$target" == "$CONFIG_DIR"* ]]; then
                echo "  ✓ $item_name (synced)"
            else
                echo "  → $item_name (symlink to elsewhere)"
            fi
        else
            if [ -f "$repo_dir/$item_name" ]; then
                echo "  ⚠ $item_name (exists in both - local copy)"
            else
                echo "  ○ $item_name (local only)"
            fi
        fi
    done
}

show_status() {
    echo -e "${BOLD}Claude Config Sync Status${RESET}"
    echo "========================="
    echo ""

    echo -e "${BOLD}Skills:${RESET}"
    if [ -d "$HOME/.claude/skills" ] && [ -n "$(ls -A "$HOME/.claude/skills" 2>/dev/null)" ]; then
        show_dir_status "skills"
    else
        echo "  (none)"
    fi
    echo ""

    echo -e "${BOLD}Agents:${RESET}"
    if [ -d "$HOME/.claude/agents" ] && ls "$HOME/.claude/agents"/*.md &>/dev/null; then
        show_file_status "agents"
    else
        echo "  (none)"
    fi
    echo ""

    echo -e "${BOLD}Rules:${RESET}"
    if [ -d "$HOME/.claude/rules" ] && ls "$HOME/.claude/rules"/*.md &>/dev/null; then
        show_file_status "rules"
    else
        echo "  (none)"
    fi
    echo ""

    echo "Legend: ✓ synced | ○ local only | ⚠ conflict | → external"
    echo ""
    echo "Usage:"
    echo "  ./sync.sh add <type> <name>     Add a local item to repo"
    echo "  ./sync.sh remove <type> <name>  Remove an item from repo (keeps local)"
    echo "  ./sync.sh pull                  Pull latest and reinstall"
    echo "  ./sync.sh push                  Commit and push changes"
    echo ""
    echo "Types: skill, agent, rule"
}

add_skill() {
    local name="$1"
    local src="$HOME/.claude/skills/$name"
    local dest="$CONFIG_DIR/skills/$name"

    if [ ! -d "$src" ]; then
        echo "Error: Skill not found at $src"
        exit 1
    fi

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        echo "Error: '$name' is already synced"
        exit 1
    fi

    echo "Adding skill '$name' to repo..."
    mkdir -p "$CONFIG_DIR/skills"
    cp -r "$src" "$dest"
    rm -rf "$src"
    ln -s "$dest" "$src"

    echo "✓ Skill '$name' added and symlinked"
    echo "  Run: ./sync.sh push"
}

add_file() {
    local type="$1"
    local name="$2"
    local src="$HOME/.claude/$type/$name.md"
    local dest="$CONFIG_DIR/$type/$name.md"

    if [ ! -f "$src" ]; then
        echo "Error: ${type%s} not found at $src"
        exit 1
    fi

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        echo "Error: '$name' is already synced"
        exit 1
    fi

    echo "Adding ${type%s} '$name' to repo..."
    mkdir -p "$CONFIG_DIR/$type"
    cp "$src" "$dest"
    rm "$src"
    ln -s "$dest" "$src"

    echo "✓ ${type^} '$name' added and symlinked"
    echo "  Run: ./sync.sh push"
}

remove_skill() {
    local name="$1"
    local src="$HOME/.claude/skills/$name"
    local dest="$CONFIG_DIR/skills/$name"

    if [ ! -d "$dest" ]; then
        echo "Error: Skill '$name' not in repo"
        exit 1
    fi

    echo "Removing skill '$name' from repo..."

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        rm "$src"
        cp -r "$dest" "$src"
    fi

    rm -rf "$dest"

    echo "✓ Skill '$name' removed from repo (kept as local)"
    echo "  Run: ./sync.sh push"
}

remove_file() {
    local type="$1"
    local name="$2"
    local src="$HOME/.claude/$type/$name.md"
    local dest="$CONFIG_DIR/$type/$name.md"

    if [ ! -f "$dest" ]; then
        echo "Error: ${type%s} '$name' not in repo"
        exit 1
    fi

    echo "Removing ${type%s} '$name' from repo..."

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        rm "$src"
        cp "$dest" "$src"
    fi

    rm "$dest"

    echo "✓ ${type^} '$name' removed from repo (kept as local)"
    echo "  Run: ./sync.sh push"
}

pull_changes() {
    echo "Pulling latest changes..."
    cd "$CONFIG_DIR"
    git pull
    echo ""
    echo "Re-running install..."
    ./install.sh
}

push_changes() {
    cd "$CONFIG_DIR"

    if [ -z "$(git status --porcelain)" ]; then
        echo "Nothing to push - working tree clean"
        exit 0
    fi

    echo "Changes to push:"
    git status --short
    echo ""

    read -p "Commit message (or Ctrl+C to cancel): " msg
    git add -A
    git commit -m "$msg"
    git push

    echo "✓ Pushed to remote"
}

# Main
case "${1:-}" in
    add)
        type="${2:-}"
        name="${3:-}"
        [ -z "$type" ] || [ -z "$name" ] && { echo "Usage: ./sync.sh add <type> <name>"; echo "Types: skill, agent, rule"; exit 1; }
        case "$type" in
            skill)  add_skill "$name" ;;
            agent)  add_file "agents" "$name" ;;
            rule)   add_file "rules" "$name" ;;
            *)      echo "Unknown type: $type (use: skill, agent, rule)"; exit 1 ;;
        esac
        ;;
    remove)
        type="${2:-}"
        name="${3:-}"
        [ -z "$type" ] || [ -z "$name" ] && { echo "Usage: ./sync.sh remove <type> <name>"; echo "Types: skill, agent, rule"; exit 1; }
        case "$type" in
            skill)  remove_skill "$name" ;;
            agent)  remove_file "agents" "$name" ;;
            rule)   remove_file "rules" "$name" ;;
            *)      echo "Unknown type: $type (use: skill, agent, rule)"; exit 1 ;;
        esac
        ;;
    pull)
        pull_changes
        ;;
    push)
        push_changes
        ;;
    *)
        show_status
        ;;
esac
