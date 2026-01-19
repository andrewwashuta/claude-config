# Workflows

## Setting up on a new machine

```bash
git clone git@github.com:brianlovin/claude-config.git ~/Developer/claude-config
cd ~/Developer/claude-config
./install.sh
```

Creates symlinks from `~/.claude/` to this repo. Local-only items are preserved.

## Sync status legend

```bash
./sync.sh
```

Shows status grouped by type (Skills, Agents, Rules):

- `✓` synced (symlinked to this repo)
- `○` local only (not in repo)
- `⚠` conflict (exists in both - run `./install.sh` to fix)
- `→` external (symlinked elsewhere)

## Adding items to sync across machines

```bash
./sync.sh add skill <name>   # Add a skill directory
./sync.sh add agent <name>   # Add an agent file (without .md extension)
./sync.sh add rule <name>    # Add a rule file (without .md extension)
./sync.sh push
```

Copies the item to repo, replaces local with symlink, prompts for commit.

## Removing items from repo

```bash
./sync.sh remove skill <name>
./sync.sh remove agent <name>
./sync.sh remove rule <name>
./sync.sh push
```

Removes from repo but keeps local copy.

## Keeping items local-only

Any item in `~/.claude/` that isn't symlinked stays local. The install script only creates symlinks for what's in this repo—it never deletes local files.

Use this for work-specific or experimental items.

## Directory structure

```
~/.claude/
├── skills/          # Skill directories (each has SKILL.md)
├── agents/          # Subagent markdown files
├── rules/           # Rule markdown files
├── settings.json
└── statusline.sh
```
