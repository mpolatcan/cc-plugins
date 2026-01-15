---
name: Notification Stacking
description: When multiple events fire quickly, queue them and play sequentially instead of overlapping
---

# Feature: Notification Stacking

When multiple events fire quickly, queue them and play sequentially instead of overlapping.

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

When multiple events fire quickly, queue them and play sequentially instead of overlapping. Ensures clearer and distinguishable notifications.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Every sound is distinguishable |
| :memo: Use Cases | High-frequency event scenarios |
| :dart: Value Proposition | Complete coverage, less stressful audio |

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
| :keyboard: Commands | New `stacking` command with status/clear/test |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for queue operations |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Sequential playback from queue with delays |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:stacking` commands to manage queue |
| :wrench: Configuration | Adds `stacking` section to config |
| :gear: Default Behavior | Events queued and played sequentially |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `stacking.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `stacking` section |
| `audio/player.go` | :speaker: Queue integration for sequential playback |
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

1. Add stacking section to config structure
2. Create internal/queue/stacking.go
3. Implement QueueManager with Enqueue/Flush methods
4. Add stacking command with status/clear/test options
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New stacking command can be added.

### Claude Code Hooks

No new hooks needed - queue management integrated into main flow.

### Audio Playback

Queue manager controls sequential playback with configurable delays.

### Other Findings

Stacking features:
- Max queue size limit
- Play delay between notifications
- Drop policy (oldest/newest) when queue full
- Status and clear commands

## Research Sources

| Source | Description |
|--------|-------------|
| [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main entry point |
| [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio playback |
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State management |
