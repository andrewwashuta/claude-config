# Claude Config

Personal Claude Code settings, skills, agents, and rules, synced across machines via symlinks.

## Commands

```bash
./install.sh          # Set up symlinks (run after cloning)
./sync.sh             # Show sync status
./sync.sh add <type> <name>  # Add a local item to repo (types: skill, agent, rule)
./sync.sh pull        # Pull latest and reinstall symlinks
```

For detailed workflows, see [.claude/rules/workflows.md](.claude/rules/workflows.md).
