# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** [mpolatcan/cc-plugins](https://github.com/mpolatcan/cc-plugins)

## Purpose

Contains plugin distributions installed via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## CRITICAL: ALWAYS Use TodoWrite for Task Tracking

For every development task, you MUST create and maintain a todo list using the `TodoWrite` tool.

### Why Use TodoWrite

- Tracks progress across complex multi-step tasks
- Ensures no steps are forgotten
- Provides visibility into task completion status
- Helps break down complex work into manageable steps

### Mandatory Todo Usage

1. Create todo list at task start
2. Update as you work
3. Never have more than one `in_progress` task at a time

## Structure

```
plugins/ccbell/
├── .claude-plugin/
│   └── plugin.json     # Plugin manifest (metadata only)
├── hooks/
│   └── hooks.json      # Hook definitions
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
└── scripts/
    └── ccbell.sh       # Auto-downloads binary from GitHub releases
```

**Critical Plugin Structure Rules:**

- `plugin.json` must be in `.claude-plugin/` folder at plugin root
- `hooks` can be defined inline in `plugin.json` OR in `hooks/hooks.json` (hooks.json preferred for complex plugins)
- Commands are auto-discovered from `commands/` directory

## CRITICAL: ALWAYS Validate Against Official Documentation

ALWAYS use BOTH `context7` MCP tool AND the official documentation links below to query official Claude Code documentation before validating or modifying any plugin code.

**NEVER assume existing code is correct.** Plugin schemas, hook events, manifest formats, and command specifications change between Claude Code versions. Always verify against the latest official documentation using BOTH methods.

### Mandatory Validation Steps

1. Resolve library ID with context7
2. Query official documentation with context7
3. Read official documentation from the provided links
4. Validate structure before making changes

### Required Documentation Links

**Main Plugins Reference:** https://code.claude.com/docs/en/plugins-reference

Within Plugins Reference:
- Plugin Manifest
- Commands
- Hooks in Plugins
- Manifest Schema
- Command Spec
- Hook Spec

**Main Hooks Reference:** https://code.claude.com/docs/en/hooks

Within Hooks Reference:
- Events
- Hook Types
- Matcher
- Timeout
- Input/Output

### VALIDATION CHECKLIST

- Verify `plugin.json` is in `.claude-plugin/` folder
- `hooks` can be in `plugin.json` (inline) or `hooks/hooks.json`
- Confirm hook event names are current (e.g., `Notification`, `Stop`, `SubagentStop`)
- Validate hook structure format (wrapper with `description` + `hooks` object)
- Validate hook type specifications (command, prompt)
- Check matcher patterns and syntax are up to date
- Confirm timeout defaults and maximum values

## Version Bumping Process

CRITICAL: ALWAYS bump version on every change. Never skip.

This project uses **Semantic Versioning (SemVer)**:
- `MAJOR` - Breaking changes
- `MINOR` - New features (backward-compatible)
- `PATCH` - Bug fixes (backward-compatible)

### Version Sync Rule

**VERSION MUST BE SYNCED BETWEEN BOTH REPOSITORIES**

| Repository | File | Field |
|------------|------|-------|
| cc-plugins | `plugins/ccbell/.claude-plugin/plugin.json` | `version` |
| cc-plugins | `plugins/ccbell/scripts/ccbell.sh` | `VERSION` |
| ccbell | Built binary | `main.version` (via LDFLAGS) |

**IMPORTANT: When bumping version in cc-plugins, you MUST also:**
1. Bump version in ccbell repository to the SAME version
2. Tag ccbell with the SAME version (e.g., `v1.0.0`)
3. Release ccbell to create GitHub Release
4. Then sync the version to cc-plugins

### External Release Check Rule

**CRITICAL: For plugins with external source code repositories or binary releases, BEFORE bumping version you MUST:**

1. Check if the external repository has a release available for the intended version
2. If release is available → proceed with version bump
3. If release is NOT available → NEVER bump version

**NEVER bump version in cc-plugins unless the corresponding external release exists.** This ensures plugin users can actually download and use the binaries.

### Release Process

1. Make changes and test in ccbell
2. Tag and push in ccbell:
   ```bash
   cd ../ccbell
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. Wait for GitHub Release to be created
4. Sync version to cc-plugins (run from **ccbell** directory - Makefile is in ccbell repo):
   ```bash
   cd ../ccbell
   make sync-version VERSION=v1.0.0
   ```
5. Commit and push cc-plugins:
   ```bash
   cd ../cc-plugins
   git add plugins/ccbell/.claude-plugin/plugin.json plugins/ccbell/scripts/ccbell.sh
   git commit -m "chore(ccbell): sync version to v1.0.0"
   git push
   ```

NEVER skip version bumping - even documentation-only changes require a version bump

## ccbell Plugin

Distributes audio notifications for:
- `Stop` - Claude finishes responding
- `Notification` (permission_prompt, idle_prompt) - Claude needs permission or is waiting
- `SubagentStop` - Subagent task completes

### Commands

| Command | Description |
|---------|-------------|
| `/ccbell:configure` | Interactive setup for sounds, events, cooldowns, and quiet hours |
| `/ccbell:test [event]` | Test sounds (all or specific event) |
| `/ccbell:enable` | Enable all notifications |
| `/ccbell:disable` | Disable all notifications |
| `/ccbell:status` | Show current configuration |
| `/ccbell:profile` | Switch between sound profiles |
| `/ccbell:validate` | Run installation diagnostics |
| `/ccbell:help` | Show help and documentation |

### Supported Events

| Event | Hook | Description |
|-------|------|-------------|
| `stop` | `Stop` | Claude finishes responding |
| `permission_prompt` | `Notification` | Claude needs your permission |
| `idle_prompt` | `Notification` | Claude is waiting for input |
| `subagent` | `SubagentStop` | Background agent completes |
