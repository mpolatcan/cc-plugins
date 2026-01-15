---
name: Quick Disable
description: Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration
---

# Feature: Quick Disable

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command.

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

Temporarily disable notifications for 15min, 1hr, 4hr without changing the full configuration. Quick toggle via command with auto-restore.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | One command silences notifications temporarily |
| :memo: Use Cases | Meetings, focus time, instant focus |
| :dart: Value Proposition | No config editing needed, auto-restores |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Medium]` |
| :construction: Complexity | `[Low]` |
| :warning: Risk Level | `[Low]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `quiet` command with duration and status options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for state manipulation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - playback skipped when disabled |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:quiet 15m`, `/ccbell:quiet 1h`, etc. |
| :wrench: Configuration | Adds `quick_disable` section to config |
| :gear: Default Behavior | Switches to silent profile, auto-restores after timeout |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `quiet.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `quick_disable` section |
| `audio/player.go` | :speaker: Check quick disable before playback |
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

1. Add quick_disable section to config structure
2. Add QuickDisableUntil timestamp to State
3. Implement IsQuickDisabled() and SetQuickDisable() methods
4. Add quiet command with 15m/1h/4h/status/cancel options
5. Modify main flow to check quick disable before playing
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New quiet command can be added.

### Claude Code Hooks

No new hooks needed - quick disable check integrated into main flow.

### Audio Playback

Playback is skipped when quick disable is active.

### Other Findings

Quick disable features:
- Duration options: 15m, 1h, 4h
- Status command showing time remaining
- Cancel command to restore immediately
- Auto-cancel when duration expires

## Research Sources

| Source | Description |
|--------|-------------|
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State management |
| [State file location](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State file handling |
