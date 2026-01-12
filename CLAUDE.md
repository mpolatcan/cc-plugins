# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** mpolatcan/cc-plugins

## Purpose

Contains plugin distributions installed via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## Important: No Postinstall Script Support

Claude Code plugins do NOT support `scripts/postinstall` in the plugin manifest. The binary must be installed via `scripts/ccbell.sh` which downloads from GitHub releases on first use.

## Structure

```
plugins/ccbell/
├── .claude-plugin/
│   └── plugin.json     # Plugin manifest with commands and hooks
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
└── scripts/
    └── ccbell.sh       # Auto-downloads binary from GitHub releases
```

## Official Documentation (ALWAYS refer to these)

Plugin schemas and hook events may change. Always consult the official documentation.

### Hooks Documentation (ALWAYS refer to these)

**Main Hooks Reference:** https://code.claude.com/docs/en/hooks

#### Within Hooks Reference:
| Section | URL |
|---------|-----|
| **Events** | https://code.claude.com/docs/en/hooks#events |
| **Hook Types** | https://code.claude.com/docs/en/hooks#hook-types |
| **Matcher** | https://code.claude.com/docs/en/hooks#matcher |
| **Timeout** | https://code.claude.com/docs/en/hooks#timeout |
| **Input/Output** | https://code.claude.com/docs/en/hooks#inputoutput |

#### Related in Plugins Reference:
| Section | URL |
|---------|-----|
| **Plugin Manifest** | https://code.claude.com/docs/en/plugins-reference#manifest |
| **Commands** | https://code.claude.com/docs/en/plugins-reference#commands |
| **Hooks in Plugins** | https://code.claude.com/docs/en/plugins-reference#hooks |

**ALWAYS consult these pages for:**
- Complete list of available hook events (Stop, PermissionPrompt, Notification, UserPromptSubmit, SubagentStop, etc.)
- Hook type specifications (command, agent, skill)
- Matcher patterns and syntax
- Timeout configuration
- Input/output handling
- Plugin manifest schema

## ccbell Plugin

Distributes audio notifications for:
- `Stop` - Claude finishes responding
- `Notification` (permission_prompt) - Claude needs permission
- `Notification` (idle_prompt) - User waiting for input
- `SubagentStop` - Subagent task completes

## Installation

1. Add marketplace: `/plugin marketplace add mpolatcan/cc-plugins`
2. Install plugin: `/plugin install ccbell`
3. Binary is downloaded automatically by `ccbell.sh` on first use
