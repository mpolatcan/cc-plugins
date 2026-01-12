# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** mpolatcan/cc-plugins

## Purpose

Contains plugin distributions that users install via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## Important: No Postinstall Script Support

Claude Code plugins do NOT support `scripts/postinstall` in the plugin manifest. The binary must be installed manually or via a different mechanism.

**Always refer to the official Claude Code documentation for the latest plugin and hooks specifications:**
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)

Plugin schemas and hook events may change. The documentation below reflects the current state at the time of writing.

## Structure

```
plugins/ccbell/
├── plugin.json         # Plugin manifest
├── hooks/              # Claude Code hook definitions (hooks.json)
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
├── scripts/            # ccbell.sh (auto-downloads binary from GitHub releases)
└── README.md           # Plugin documentation
```

## ccbell Plugin

The `ccbell` plugin distributes:
- Audio files for notifications
- Hook definitions that trigger `ccbell <event>` commands
- Slash commands (`/ccbell:*`)

**Hook Events Used:**
| Event | Description |
|-------|-------------|
| `Stop` | Claude finishes responding |
| `PermissionPrompt` | Claude needs permission |
| `UserPromptSubmit` | User waiting for input |
| `SubagentStop` | Subagent task completes |

**Hook Structure (hooks.json):**
```json
{
  "Stop": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "ccbell stop"
        }
      ]
    }
  ]
}
```

**Note:** The `ccbell.sh` script automatically downloads and installs the correct binary for your platform from GitHub releases:

## Installation Steps

1. Add marketplace: `/plugin marketplace add mpolatcan/cc-plugins`
2. Install plugin: `/plugin install ccbell`
3. The `ccbell.sh` script automatically downloads the binary from GitHub releases

## Note

This is a distribution repository - no build commands needed. Plugins are installed directly from this repository.
