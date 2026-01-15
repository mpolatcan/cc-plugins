---
name: Visual Notifications
description: Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger
---

# Visual Notifications

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Users who are deaf or hard of hearing, or work in noisy environments, benefit from visual alerts.

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

Show visual notifications (macOS Notification Center, terminal bell) when Claude Code events trigger. Supports accessibility and noise-restricted environments.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Supports users with hearing differences |
| :memo: Use Cases | Libraries, meetings, shared spaces |
| :dart: Value Proposition | Multi-modal feedback, screen periphery awareness |

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
| :keyboard: Commands | New `visual` command with configure, test options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for notification execution |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - visual notifications alongside audio |
| :computer: Platform Support | macOS AppleScript, Linux notify-send |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

Uses system notification tools (`osascript`, `notify-send`).

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:configure visual`, `/ccbell:test --visual stop` |
| :wrench: Configuration | Adds `visual` section with mode (audio-only/visual-only/both) |
| :gear: Default Behavior | Sends visual notification alongside audio |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `visual.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `visual` section |
| `audio/player.go` | :speaker: Visual notifier alongside audio |
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

1. Add visual section to config structure
2. Create internal/visual/visual.go
3. Implement VisualNotifier interface for each platform
4. Add Send() method with urgency support
5. Add visual command with configure/test options
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| osascript | macOS | macOS Notification Center | `[Yes]` |
| notify-send | Linux | Linux notifications | `[Yes]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New visual command can be added.

### Claude Code Hooks

No new hooks needed - visual notifications integrated into main flow.

### Audio Playback

Visual notifications work alongside or instead of audio.

### Other Findings

Visual notification features:
- Platform-specific implementations (AppleScript, notify-send)
- Urgency levels (low, normal, critical)
- Customizable messages per event
- Mode: audio-only/visual-only/both

## Research Sources

| Source | Description |
|--------|-------------|
| [AppleScript Notification](https://apple.stackexchange.com/questions/57412/how-can-i-trigger-a-notification-from-the-apple-command-line) | :books: AppleScript |
| [notify-send man page](https://man7.org/linux/man-pages/man1/notify-send.1.html) | :books: notify-send |
| [Current ccbell audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
