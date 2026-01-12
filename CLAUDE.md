# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** mpolatcan/cc-plugins

## Purpose

Contains plugin distributions that users install via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## Important: No Postinstall Script Support

Claude Code plugins do NOT support `scripts/postinstall` in the plugin manifest. The binary must be installed manually or via a different mechanism.

## Structure

```
plugins/ccbell/
├── .claude-plugin/     # Plugin manifest (plugin.json, marketplace.json)
├── hooks/              # Claude Code hook definitions (hooks.json)
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
├── scripts/            # install.sh (not auto-executed - run manually after plugin install)
└── README.md           # Plugin documentation
```

## ccbell Plugin

The `ccbell` plugin distributes:
- Audio files for notifications
- Hook definitions that trigger `ccbell <event>` commands
- Slash commands (`/ccbell:*`)

**Note:** Binary installation must be done manually after plugin installation:

```bash
# After /plugin install ccbell, run:
bash ~/.claude/plugins/local/ccbell/plugins/ccbell/scripts/install.sh
```

Or download manually from: https://github.com/mpolatcan/ccbell/releases

## Installation Steps

1. Add marketplace: `/plugin marketplace add mpolatcan/cc-plugins`
2. Install plugin: `/plugin install ccbell`
3. Download binary: Run `install.sh` manually or download from releases

## Note

This is a distribution repository - no build commands needed. Plugins are installed directly from this repository.
