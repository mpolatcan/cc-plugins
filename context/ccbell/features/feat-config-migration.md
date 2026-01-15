---
name: Config Migration
description: Automatically update old config formats to newer versions while preserving settings
---

# Feature: Config Migration

Automatically update old config formats to newer versions while preserving settings.

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

Automatically update old config formats to newer versions while preserving settings. Ensures zero-downtime upgrades and future-proof configuration.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Update ccbell without losing or manually reconfiguring settings |
| :memo: Use Cases | Upgrading from older ccbell versions with different config schemas |
| :dart: Value Proposition | Seamless transitions build trust and reduce friction |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Low]` |
| :construction: Complexity | `[Medium]` |
| :warning: Risk Level | `[Medium]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Slash command for `migrate` with dry-run/apply options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config manipulation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected by this feature |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies beyond standard Go libraries.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:migrate` to apply config migrations |
| :wrench: Configuration | Adds `version` field to config for tracking |
| :gear: Default Behavior | Auto-migrates on config load if needed |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `migrate.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add version field, migration chain, `LoadWithMigration()` |
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

1. Add version field to config structure
2. Create migration chain for version-to-version transforms
3. Implement LoadWithMigration() function
4. Add migrate command with dry-run/apply options
5. Test migration scenarios
6. Update version in main.go
7. Tag and release v0.3.0
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands and hooks. Feature is implemented entirely in ccbell binary.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Other Findings

Config migration pattern follows standard practices:
- Version field in config
- Ordered migration chain
- Dry-run support for preview
- Rollback capability consideration

## Research Sources

| Source | Description |
|--------|-------------|
| [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Current config loading implementation |
| [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) | :books: Schema validation approach |
