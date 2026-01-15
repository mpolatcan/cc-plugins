---
name: Cooldown Status Display
description: Display how much time remains before each event can trigger again
---

# Cooldown Status Display

Display how much time remains before each event can trigger again.

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

Display how much time remains before each event can trigger again. Helps users understand why notifications aren't firing and adjust their workflow accordingly.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Users understand why notifications aren't firing |
| :memo: Use Cases | Troubleshooting cooldown settings, planning workflow |
| :dart: Value Proposition | Transparent behavior makes ccbell predictable |

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
| :keyboard: Commands | Enhanced `status` command with cooldown subcommand |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for state access |

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
| :hand: User Interaction | Users run `/ccbell:status` or `/ccbell:status cooldown` |
| :wrench: Configuration | No config changes - enhances status display |
| :gear: Default Behavior | Shows cooldown status automatically in status output |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `status.md` with cooldown section |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Configuration handling (no change) |
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
# 1. Add GetCooldownRemaining() method to State
# 2. Add formatDuration() helper function
# 3. Enhance status command to show cooldown info
# 4. Update version in main.go
# 5. Tag and release vX.X.X
# 6. Sync version to cc-plugins
```

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Status command enhancement uses existing patterns.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Not affected by this feature.

### Other Findings

Cooldown display should show:
- Ready status for events not in cooldown
- Time remaining for events in cooldown
- Estimated resume time

## Research Sources

| Source | Description |
|--------|-------------|
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: Current state implementation |
| [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: Cooldown tracking |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config structure |
