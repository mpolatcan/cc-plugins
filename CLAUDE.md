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

## CRITICAL: ALWAYS Validate Against Official Documentation

**ALWAYS use `context7` MCP tool to query official Claude Code documentation before validating or modifying any plugin code. NEVER skip this step.**

**NEVER assume existing code is correct. Plugin schemas, hook events, manifest formats, and command specifications change between Claude Code versions. Always verify against the latest official documentation.**

### Mandatory Validation Steps

1. **Resolve library ID:**
   ```
   mcp__context7__resolve-library-id with libraryName="claude-code" and query="Claude Code plugins hooks manifest"
   ```

2. **Query official documentation:**
   ```
   mcp__context7__query-docs with libraryId from step 1 and query="plugin manifest schema hooks commands specification"
   ```

3. **Validate structure before making changes:**
   - Verify `plugin.json` format matches official spec
   - Confirm hook structure (array vs object format)
   - Validate command specification format
   - Check timeout and matcher syntax

### Required Queries for Plugin Validation

When validating plugin code, ALWAYS query these topics:
- "plugin manifest schema JSON structure commands hooks specification"
- "hooks.json hook event matcher type command timeout configuration"
- "plugin.json hooks array format with event field inline hooks specification schema"
- "command specification format name description slash command"

### Plugins Documentation (ALWAYS READ - NEVER skip)

**Main Plugins Reference:** https://code.claude.com/docs/en/plugins-reference

**CRITICAL: You MUST READ the content at these URLs. Do NOT just list them.**

#### Within Plugins Reference:
| Section | URL |
|---------|-----|
| **Plugin Manifest** | https://code.claude.com/docs/en/plugins-reference#manifest |
| **Commands** | https://code.claude.com/docs/en/plugins-reference#commands |
| **Hooks in Plugins** | https://code.claude.com/docs/en/plugins-reference#hooks |
| **Manifest Schema** | https://code.claude.com/docs/en/plugins-reference#manifest-schema |
| **Command Spec** | https://code.claude.com/docs/en/plugins-reference#command-spec |
| **Hook Spec** | https://code.claude.com/docs/en/plugins-reference#hook-spec |

**Also See:**
- **Plugins Overview** - https://code.claude.com/docs/en/plugins
- **Discover Plugins** - https://code.claude.com/docs/en/discover-plugins
- **Plugin Marketplaces** - https://code.claude.com/docs/en/plugin-marketplaces

### Hooks Documentation (ALWAYS READ - NEVER skip)

**Main Hooks Reference:** https://code.claude.com/docs/en/hooks

**CRITICAL: You MUST READ the content at these URLs. Do NOT just list them.**

#### Within Hooks Reference:
| Section | URL |
|---------|-----|
| **Events** | https://code.claude.com/docs/en/hooks#events |
| **Hook Types** | https://code.claude.com/docs/en/hooks#hook-types |
| **Matcher** | https://code.claude.com/docs/en/hooks#matcher |
| **Timeout** | https://code.claude.com/docs/en/hooks#timeout |
| **Input/Output** | https://code.claude.com/docs/en/hooks#inputoutput |

**VALIDATION CHECKLIST (NEVER SKIP):**
- [ ] Verify hook structure format (array with `event` vs object with event as key)
- [ ] Confirm hook event names are current (e.g., `Notification` vs separate events)
- [ ] Validate hook type specifications (command, agent, skill)
- [ ] Check matcher patterns and syntax are up to date
- [ ] Confirm timeout defaults and maximum values

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
