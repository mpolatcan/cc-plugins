# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** mpolatcan/cc-plugins

## Purpose

Contains plugin distributions that users install via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## Structure

```
plugins/ccbell/
├── .claude-plugin/     # Plugin manifest (plugin.json, marketplace.json)
├── hooks/              # Claude Code hook definitions (hooks.json)
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
├── scripts/            # Postinstall script (install.sh)
└── README.md           # Plugin documentation
```

## ccbell Plugin

The `ccbell` plugin distributes:
- Audio files for notifications
- Hook definitions that trigger `ccbell <event>` commands
- Slash commands (`/ccbell:*`)
- Postinstall script that downloads the Go binary from ccbell releases

### Plugin Commands

- `/ccbell:configure` - Configure settings
- `/ccbell:test` - Test sound playback
- `/ccbell:enable` - Enable notifications
- `/ccbell:disable` - Disable notifications
- `/ccbell:status` - Show current status
- `/ccbell:profile` - Manage profiles
- `/ccbell:validate` - Validate configuration
- `/ccbell:help` - Show help

## Note

This is a distribution repository - no build commands needed. Plugins are installed directly from this repository.
