# cc-plugins

Claude Code plugin marketplace - hosts distributable plugins.

**GitHub:** [mpolatcan/cc-plugins](https://github.com/mpolatcan/cc-plugins)

## Purpose

Contains plugin distributions installed via `/plugin install <plugin_name>`. Currently hosts two variants of the ccbell plugin:
- **ccbell** (production) - Stable release
- **ccbell-nightly** (nightly) - Pre-release for testing new features

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
├── production/                    # Stable release (name: "ccbell")
│   ├── .claude-plugin/
│   │   └── plugin.json            # Plugin manifest (metadata only)
│   ├── bin/
│   │   └── ccbell                 # Compiled binary (auto-downloaded)
│   ├── commands/                  # Slash command documentation (.md)
│   ├── hooks/
│   │   └── hooks.json             # Hook definitions
│   ├── scripts/
│   │   └── ccbell.sh              # Auto-downloads binary from stable GitHub releases
│   ├── sounds/                    # Audio files (.aiff)
│   └── README.md
│
└── nightly/                       # Pre-release (name: "ccbell-nightly")
    ├── .claude-plugin/
    │   └── plugin.json            # Plugin manifest (metadata only)
    ├── bin/
    │   └── ccbell                 # Compiled binary (auto-downloaded from pre-release)
    ├── commands/                  # Slash command documentation (.md)
    ├── hooks/
    │   └── hooks.json             # Hook definitions
    ├── scripts/
    │   └── ccbell.sh              # Auto-downloads binary from pre-release GitHub tags
    ├── sounds/                    # Audio files (.aiff)
    └── README.md
```

Each variant is a fully self-contained plugin. They share the same parent directory but are completely independent - separate config, logs, packs, and binary versions.

### Variant Isolation

| Resource | production (ccbell) | nightly (ccbell-nightly) |
|----------|---------------------|--------------------------|
| Config file | `~/.claude/ccbell.config.json` | `~/.claude/ccbell-nightly.config.json` |
| Log file | `~/.claude/ccbell.log` | `~/.claude/ccbell-nightly.log` |
| Packs dir | `~/.claude/ccbell/packs/` | `~/.claude/ccbell-nightly/packs/` |
| Command prefix | `/ccbell:` | `/ccbell-nightly:` |
| Binary source | Stable release tags | Pre-release tags |

**Critical Plugin Structure Rules:**

- `plugin.json` must be in `.claude-plugin/` folder at each variant's root
- Commands are auto-discovered from `commands/` directory within each variant
- Each variant must be fully self-contained (sounds, scripts, hooks all inside its own directory)
- `${CLAUDE_PLUGIN_ROOT}` resolves to the installed variant's root, not the parent `ccbell/` directory

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
- `hooks` must be in `hooks/hooks.json` (not inline in plugin.json)
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

Nightly uses pre-release suffixes: `X.Y.Z-nightly.N` (e.g., `0.3.0-nightly.1`)

### Version Sync Rule

**VERSION MUST BE SYNCED BETWEEN BOTH REPOSITORIES**

#### Production (ccbell)

| Repository | File | Field |
|------------|------|-------|
| cc-plugins | `plugins/ccbell/production/.claude-plugin/plugin.json` | `version` |
| cc-plugins | `plugins/ccbell/production/scripts/ccbell.sh` | `VERSION` |
| ccbell | Built binary | `main.version` (via LDFLAGS) |

#### Nightly (ccbell-nightly)

| Repository | File | Field |
|------------|------|-------|
| cc-plugins | `plugins/ccbell/nightly/.claude-plugin/plugin.json` | `version` |
| cc-plugins | `plugins/ccbell/nightly/scripts/ccbell.sh` | `VERSION` |
| ccbell | Pre-release binary | `main.version` (via LDFLAGS) |

**IMPORTANT: When releasing a new version in ccbell, you MUST also:**
1. Tag ccbell with the version (e.g., `v1.0.0` for stable, `v1.0.0-nightly.1` for pre-release)
2. Release ccbell to create GitHub Release
3. Then sync the version to cc-plugins (run `make sync-version VERSION=v1.0.0` from ccbell directory)

### External Release Check Rule

**CRITICAL: For plugins with external source code repositories or binary releases, BEFORE bumping version you MUST:**

1. Check if the external repository has a release available for the intended version
2. If release is available → proceed with version bump
3. If release is NOT available → NEVER bump version

**NEVER bump version in cc-plugins unless the corresponding external release exists.** This ensures plugin users can actually download and use the binaries. This applies to BOTH production and nightly variants.

### Release Process

#### Production Release

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
   make sync-version VERSION=v1.0.0
   ```
5. Commit and push cc-plugins:
   ```bash
   cd ../cc-plugins
   git add plugins/ccbell/production/.claude-plugin/plugin.json plugins/ccbell/production/scripts/ccbell.sh
   git commit -m "chore(ccbell): sync production version to v1.0.0"
   git push
   ```

#### Nightly Release

1. Make changes and test in ccbell
2. Tag and push a pre-release in ccbell:
   ```bash
   cd ../ccbell
   git tag v1.0.0-nightly.1
   git push origin v1.0.0-nightly.1
   ```
3. Wait for GitHub Pre-release to be created
4. Update nightly version in cc-plugins:
   ```bash
   cd ../cc-plugins
   # Update VERSION in plugins/ccbell/nightly/scripts/ccbell.sh
   # Update version in plugins/ccbell/nightly/.claude-plugin/plugin.json
   git add plugins/ccbell/nightly/.claude-plugin/plugin.json plugins/ccbell/nightly/scripts/ccbell.sh
   git commit -m "chore(ccbell): sync nightly version to v1.0.0-nightly.1"
   git push
   ```

NEVER skip version bumping - even documentation-only changes require a version bump

## ccbell Plugin (Production)

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
| `/ccbell:packs` | Browse, install, and manage sound packs |
| `/ccbell:validate` | Run installation diagnostics |
| `/ccbell:help` | Show help and documentation |

## ccbell-nightly Plugin

Same feature set as production but uses pre-release binaries and isolated configuration. All commands use the `/ccbell-nightly:` prefix.

### Commands

| Command | Description |
|---------|-------------|
| `/ccbell-nightly:configure` | Interactive setup for sounds, events, cooldowns, and quiet hours |
| `/ccbell-nightly:test [event]` | Test sounds (all or specific event) |
| `/ccbell-nightly:enable` | Enable all notifications |
| `/ccbell-nightly:disable` | Disable all notifications |
| `/ccbell-nightly:status` | Show current configuration |
| `/ccbell-nightly:profile` | Switch between sound profiles |
| `/ccbell-nightly:packs` | Browse, install, and manage sound packs |
| `/ccbell-nightly:validate` | Run installation diagnostics |
| `/ccbell-nightly:help` | Show help and documentation |

### Nightly Environment Variables

The nightly `ccbell.sh` script exports these env vars before running the binary to achieve config isolation:

```bash
CCBELL_CONFIG="$HOME/.claude/ccbell-nightly.config.json"
CCBELL_LOG="$HOME/.claude/ccbell-nightly.log"
CCBELL_PACKS_DIR="$HOME/.claude/ccbell-nightly/packs"
```

The nightly binary must support reading these env vars (falling back to defaults if not set).

### Supported Events (both variants)

| Event | Hook | Description |
|-------|------|-------------|
| `stop` | `Stop` | Claude finishes responding |
| `permission_prompt` | `Notification` | Claude needs your permission |
| `idle_prompt` | `Notification` | Claude is waiting for input |
| `subagent` | `SubagentStop` | Background agent completes |
