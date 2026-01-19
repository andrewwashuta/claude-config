#!/bin/bash
set -e

CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)"

show_status() {
    echo "Claude Config Sync Status"
    echo "========================="
    echo ""

    echo "Skills:"
    for skill in ~/.claude/skills/*/; do
        [ -d "$skill" ] || continue
        skill_name=$(basename "$skill")

        if [ -L "$skill" ]; then
            target=$(readlink "$skill")
            if [[ "$target" == "$CONFIG_DIR"* ]]; then
                echo "  ✓ $skill_name (synced)"
            else
                echo "  → $skill_name (symlink to elsewhere)"
            fi
        else
            if [ -d "$CONFIG_DIR/skills/$skill_name" ]; then
                echo "  ⚠ $skill_name (exists in both - local copy)"
            else
                echo "  ○ $skill_name (local only)"
            fi
        fi
    done

    echo ""
    echo "Commands:"
    for cmd in ~/.claude/commands/*.md 2>/dev/null; do
        [ -f "$cmd" ] || continue
        cmd_name=$(basename "$cmd")

        if [ -L "$cmd" ]; then
            target=$(readlink "$cmd")
            if [[ "$target" == "$CONFIG_DIR"* ]]; then
                echo "  ✓ $cmd_name (synced)"
            else
                echo "  → $cmd_name (symlink to elsewhere)"
            fi
        else
            if [ -f "$CONFIG_DIR/commands/$cmd_name" ]; then
                echo "  ⚠ $cmd_name (exists in both - local copy)"
            else
                echo "  ○ $cmd_name (local only)"
            fi
        fi
    done

    echo ""
    echo "Legend: ✓ synced | ○ local only | ⚠ conflict | → external"
    echo ""
    echo "Commands:"
    echo "  ./sync.sh add skill <name>      Add a local skill to repo"
    echo "  ./sync.sh add command <name>    Add a local command to repo"
    echo "  ./sync.sh remove skill <name>   Remove a skill from repo (keeps local)"
    echo "  ./sync.sh remove command <name> Remove a command from repo (keeps local)"
    echo "  ./sync.sh pull                  Pull latest and reinstall"
    echo "  ./sync.sh push                  Commit and push changes"
}

add_skill() {
    skill_name="$1"
    src="$HOME/.claude/skills/$skill_name"
    dest="$CONFIG_DIR/skills/$skill_name"

    if [ ! -d "$src" ]; then
        echo "Error: Skill not found at $src"
        exit 1
    fi

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        echo "Error: '$skill_name' is already synced"
        exit 1
    fi

    echo "Adding skill '$skill_name' to repo..."
    cp -r "$src" "$dest"
    rm -rf "$src"
    ln -s "$dest" "$src"

    echo "✓ Skill '$skill_name' added and symlinked"
    echo "  Run: ./sync.sh push"
}

add_command() {
    cmd_name="$1"
    [[ "$cmd_name" != *.md ]] && cmd_name="${cmd_name}.md"
    src="$HOME/.claude/commands/$cmd_name"
    dest="$CONFIG_DIR/commands/$cmd_name"

    if [ ! -f "$src" ]; then
        echo "Error: Command not found at $src"
        exit 1
    fi

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        echo "Error: '$cmd_name' is already synced"
        exit 1
    fi

    echo "Adding command '$cmd_name' to repo..."
    cp "$src" "$dest"
    rm "$src"
    ln -s "$dest" "$src"

    echo "✓ Command '$cmd_name' added and symlinked"
    echo "  Run: ./sync.sh push"
}

remove_skill() {
    skill_name="$1"
    src="$HOME/.claude/skills/$skill_name"
    dest="$CONFIG_DIR/skills/$skill_name"

    if [ ! -d "$dest" ]; then
        echo "Error: Skill '$skill_name' not in repo"
        exit 1
    fi

    echo "Removing skill '$skill_name' from repo..."

    # If it's a symlink to our repo, copy back to local
    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        rm "$src"
        cp -r "$dest" "$src"
    fi

    rm -rf "$dest"

    echo "✓ Skill '$skill_name' removed from repo (kept as local)"
    echo "  Run: ./sync.sh push"
}

remove_command() {
    cmd_name="$1"
    [[ "$cmd_name" != *.md ]] && cmd_name="${cmd_name}.md"
    src="$HOME/.claude/commands/$cmd_name"
    dest="$CONFIG_DIR/commands/$cmd_name"

    if [ ! -f "$dest" ]; then
        echo "Error: Command '$cmd_name' not in repo"
        exit 1
    fi

    echo "Removing command '$cmd_name' from repo..."

    if [ -L "$src" ] && [[ "$(readlink "$src")" == "$CONFIG_DIR"* ]]; then
        rm "$src"
        cp "$dest" "$src"
    fi

    rm "$dest"

    echo "✓ Command '$cmd_name' removed from repo (kept as local)"
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
        case "${2:-}" in
            skill)
                [ -z "${3:-}" ] && { echo "Usage: ./sync.sh add skill <name>"; exit 1; }
                add_skill "$3"
                ;;
            command)
                [ -z "${3:-}" ] && { echo "Usage: ./sync.sh add command <name>"; exit 1; }
                add_command "$3"
                ;;
            *)
                echo "Usage: ./sync.sh add <skill|command> <name>"
                exit 1
                ;;
        esac
        ;;
    remove)
        case "${2:-}" in
            skill)
                [ -z "${3:-}" ] && { echo "Usage: ./sync.sh remove skill <name>"; exit 1; }
                remove_skill "$3"
                ;;
            command)
                [ -z "${3:-}" ] && { echo "Usage: ./sync.sh remove command <name>"; exit 1; }
                remove_command "$3"
                ;;
            *)
                echo "Usage: ./sync.sh remove <skill|command> <name>"
                exit 1
                ;;
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
