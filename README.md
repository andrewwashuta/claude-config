# claude-config

My [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration - settings, custom commands, and skills.

## Quick start

```bash
git clone https://github.com/brianlovin/claude-config.git ~/Developer/claude-config
cd ~/Developer/claude-config
./install.sh
```

## What's included

### Settings
- `settings.json` - Global permissions and preferences
- `statusline.sh` - Custom statusline showing token usage

### Commands
Custom slash commands (invoke with `/<name>` in Claude):

| Command | Description |
|---------|-------------|
| `/favicon` | Generate favicons from a source image |
| `/rams` | Run accessibility and visual design review |
| `/simplify` | Code simplification specialist |

### Skills
Reusable capabilities that Claude can invoke:

| Skill | Description |
|-------|-------------|
| `agent-browser` | Browser automation for web testing and interaction |
| `reclaude` | _(description)_ |

## Managing your config

```bash
# See what's synced vs local-only
./sync.sh

# Add a local skill to the repo
./sync.sh add skill my-skill
./sync.sh push

# Add a local command to the repo
./sync.sh add command my-command
./sync.sh push

# Pull changes on another machine
./sync.sh pull

# Remove something from repo (keeps local copy)
./sync.sh remove skill my-skill
./sync.sh push
```

## Local-only config

Not everything needs to be synced. The install script only creates symlinks for what's in this repo - it won't delete your local-only skills or commands.

Machine-specific permissions accumulate in `~/.claude/settings.local.json` (auto-created by Claude, not synced).

## Creating your own

Fork this repo and customize! The structure is simple:

```
claude-config/
├── settings.json      # Claude Code settings
├── statusline.sh      # Optional statusline script
├── commands/          # Custom slash commands (*.md)
└── skills/            # Skills (subdirectories with SKILL.md or skill.md)
```

## See also

- [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)
- [My dotfiles](https://github.com/brianlovin/dotfiles) - Shell, git, SSH config
