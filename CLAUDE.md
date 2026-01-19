# Claude Config

Claude Code configuration - settings and skills.

## Repository structure

```
~/Developer/claude-config/
├── settings.json          # Global Claude Code settings
├── statusline.sh          # Custom statusline script
├── skills/                # Skills (subdirectories)
│   ├── agent-browser/
│   ├── favicon/
│   ├── rams/
│   ├── reclaude/
│   └── simplify/
├── install.sh             # Symlink installer
├── sync.sh                # Sync management tool
└── README.md
```

## Key workflows

### Setting up on a new machine

```bash
git clone git@github.com:brianlovin/claude-config.git ~/Developer/claude-config
cd ~/Developer/claude-config
./install.sh
```

This creates symlinks from `~/.claude/` to this repo. Local-only skills are preserved.

### Check sync status

```bash
cd ~/Developer/claude-config
./sync.sh
```

Shows:
- `✓` synced (symlinked to this repo)
- `○` local only (not in repo)
- `⚠` conflict (exists in both)

### Add a local skill to the repo (to share across machines)

```bash
./sync.sh add <skill-name>
./sync.sh push
```

This copies the skill to the repo, replaces the local copy with a symlink, and prompts for a commit message.

### Remove a skill from repo (keep local copy)

```bash
./sync.sh remove <skill-name>
./sync.sh push
```

The skill is removed from the repo but kept as a local file.

### Pull changes from another machine

```bash
./sync.sh pull
```

This runs `git pull` and re-runs `install.sh`.

### Quick push after manual edits

```bash
./sync.sh push
```

Shows changes, prompts for commit message, commits and pushes.

## Keeping skills local (not synced)

Any skill in `~/.claude/` that isn't symlinked to this repo stays local. The install script only creates symlinks for what's in this repo - it never deletes local files.

Use this for work-specific or experimental skills you don't want to share.

## File locations

| Repo file | Symlinked to |
|-----------|--------------|
| `settings.json` | `~/.claude/settings.json` |
| `statusline.sh` | `~/.claude/statusline.sh` |
| `skills/*/` | `~/.claude/skills/*/` |

## Related

Traditional dotfiles (git, zsh, ssh, Brewfile) live in a separate repo:
- https://github.com/brianlovin/dotfiles
- Clone to `~/Developer/dotfiles`
