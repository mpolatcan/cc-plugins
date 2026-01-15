---
name: Export/Import Config
description: Export current ccbell configuration to a portable JSON file and import from files or URLs
---

# Export/Import Config

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs.

## Table of Contents

1. [Summary](#summary)
2. [Benefit](#benefit)
3. [Priority & Complexity](#priority--complexity)
4. [Feasibility](#feasibility)
   - [Claude Code](#claude-code)
   - [Audio Player](#audio-player)
   - [External Dependencies](#external-dependencies)
5. [Usage in ccbell Plugin](#usage-in-ccbell-plugin)
6. [Repository Impact](#repository-impact)
   - [cc-plugins](#cc-plugins)
   - [ccbell](#ccbell)
7. [Implementation](#implementation)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Export current ccbell configuration to a portable JSON file. Import configurations from files or URLs. Enables team collaboration and easy backup.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Team collaboration, easy backup protection |
| :memo: Use Cases | Standardizing notification setups across team members |
| :dart: Value Proposition | New members get productive instantly |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Low]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `config` command with export/import options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for file operations |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go's standard `encoding/json`.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:config export` or `/ccbell:config import` |
| :wrench: Configuration | No schema change - pure JSON serialization |
| :gear: Default Behavior | Supports merge or replace on import |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `config.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add Export(), Import(), Merge() methods |
| `audio/player.go` | :speaker: Audio playback logic (no change) |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation

### cc-plugins

Steps required in cc-plugins repository:

```bash
# 1. Update plugin.json version
# 2. Update ccbell.sh if needed
# 3. Add/update command documentation
# 4. Add/update hooks configuration
# 5. Add new sound files if applicable
```

### ccbell

Steps required in ccbell repository:

```bash
# 1. Implement Export() method for config
# 2. Implement Import() method with merge option
# 3. Create internal/config/export.go
# 4. Add config command with export/import options
# 5. Update version in main.go
# 6. Tag and release vX.X.X
# 7. Sync version to cc-plugins
```

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Config export/import command can be added.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Other Findings

Export/Import features:
- Export to file with optional secrets exclusion
- Import from file or URL
- Merge or replace on import

## Research Sources

| Source | Description |
|--------|-------------|
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config loading |
| [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Validation |
| [JSON marshaling](https://pkg.go.dev/encoding/json) | :books: JSON handling |
