---
name: Do Not Disturb Integration
description: Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled
---

# Feature: Do Not Disturb Integration

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled.

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

Automatically suppress ccbell notifications when the system Do Not Disturb mode is enabled. Integrates with macOS and Linux DND settings.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | No manual toggling when entering DND mode |
| :memo: Use Cases | Focus time, meetings, presentations |
| :dart: Value Proposition | System-level DND controls everything |

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
| :keyboard: Commands | No new commands - automatic detection |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash for executing platform DND commands |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - playback skipped when DND active |
| :computer: Platform Support | macOS `defaults read`, Linux `gsettings`/`qdbus` |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses system commands (`defaults`, `gsettings`, `qdbus`) which are platform-specific.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Automatic - no user action needed |
| :wrench: Configuration | Optional `dnd` section with `enabled` and `behavior` |
| :gear: Default Behavior | Checks system DND before every notification |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `configure.md` with DND section |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add DND section to config |
| `audio/player.go` | :speaker: Check DND before playback |
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

1. Create internal/dnd/dnd.go for DND detection
2. Implement isMacOSDND() using defaults read
3. Implement isLinuxDND() using gsettings/qdbus
4. Add DND section to config structure
5. Modify main flow to check DND before playing
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| `defaults` | macOS | Read DND status | `[Yes]` |
| `gsettings` | Linux/GNOME | Read DND status | `[Yes]` |
| `qdbus` | Linux/KDE | Read DND status | `[Yes]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports hooks. DND check can be integrated into main flow.

### Claude Code Hooks

No new hooks needed - check DND before existing hooks fire.

### Audio Playback

Playback is skipped when DND is active, but no audio changes needed.

### Other Findings

Platform DND detection methods:
- macOS: `defaults read com.apple.notificationcenterui doNotDisturb`
- GNOME Linux: `gsettings get org.gnome.desktop.notifications show-banners`
- KDE Linux: `qdbus org.kde.kded /modules/kded readConfig global`

## Research Sources

| Source | Description |
|--------|-------------|
| [macOS DND via defaults](https://developer.apple.com/documentation/foundation/preferences) | :books: Apple preferences documentation |
| [GNOME notifications](https://developer.gnome.org/notification-spec/) | :books: GNOME notification spec |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: ccbell main flow |
| [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82-L91) | :books: Platform detection patterns |
