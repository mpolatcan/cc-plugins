---
name: Per-Workspace Configuration
description: Allow ccbell to read project-specific config from .claude-ccbell.json in the workspace root
---

# Per-Workspace Configuration

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications.

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
7. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Allow ccbell to read project-specific config from `.claude-ccbell.json` in the workspace root. Enables context-aware notifications (louder for production, subtle for dev).

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Notifications adapt to the project context |
| :memo: Use Cases | Team consistency, workflow optimization |
| :dart: Value Proposition | No global config changes needed |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[High]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Enhanced `config` command with --local flags |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config merging |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:config init --local` to create workspace config |
| :wrench: Configuration | Local config merges with global config |
| :gear: Default Behavior | Loads workspace config if present in current directory |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update configure.md with local options |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add LoadWithWorkspace(), MergeConfigs() |
| `audio/player.go` | :speaker: Audio playback logic (no change) |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation
4. Add/update hooks configuration
5. Add new sound files if applicable

### ccbell

Steps required in ccbell repository:

1. Implement LoadWithWorkspace() function
2. Implement MergeConfigs() for global + local merging
3. Add --local flag to config init/show/edit commands
4. Update version in main.go
5. Tag and release vX.X.X
6. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Local config can be integrated into existing commands.

### Claude Code Hooks

No new hooks needed - workspace config loaded at startup.

### Audio Playback

Not affected by this feature.

### Other Findings

Workspace config features:
- `.claude-ccbell.json` in workspace root
- Inherit option for global config
- Profile and volume overrides
- Event-level customization

## Research Sources

| Source | Description |
|--------|-------------|
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config loading |
| [Config merge pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L206-L220) | :books: Merge patterns |
| [Environment variable usage](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Environment handling |
