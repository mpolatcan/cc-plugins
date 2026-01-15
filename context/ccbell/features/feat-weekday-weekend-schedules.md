---
name: Weekday/Weekend Schedules
description: Override default quiet hours with weekend-specific schedules
---

# Weekday/Weekend Schedules

Override default quiet hours with weekend-specific schedules. Respects different schedules for weekdays vs. weekends.

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

Override default quiet hours with weekend-specific schedules. Automated adaptation to different schedules for weekdays vs. weekends.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Respects different schedules for work-life balance |
| :memo: Use Cases | Family-friendly, personalized rhythms |
| :dart: Value Proposition | Automated adaptation, no manual changes needed |

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
| :keyboard: Commands | Enhanced `quiet hours` command with weekday/weekend options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for config manipulation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - quiet hours check before playback |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:quiet hours --weekday 22:00-07:00`, `/ccbell:quiet hours --weekend 23:00-09:00` |
| :wrench: Configuration | Extends `QuietHours` with `weekday` and `weekend` TimeWindow |
| :gear: Default Behavior | Uses weekday schedule Mon-Fri, weekend Sat-Sun |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update configure.md with weekday/weekend options |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Extend QuietHours with weekday/weekend |
| `audio/player.go` | :speaker: Check quiet hours before playback |
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

1. Extend QuietHoursConfig with weekday and weekend TimeWindow
2. Extend IsInQuietHours() with weekday/weekend logic
3. Add --weekday and --weekend flags to quiet hours command
4. Support timezone configuration
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Schedule options can be added to configure command.

### Claude Code Hooks

No new hooks needed - quiet hours check integrated into main flow.

### Audio Playback

Playback is skipped during quiet hours based on day of week.

### Other Findings

Schedule features:
- Default quiet hours (fallback)
- Weekday-specific schedule (Mon-Fri)
- Weekend-specific schedule (Sat-Sun)
- Timezone support
- Flexible start/end times

## Research Sources

| Source | Description |
|--------|-------------|
| [Go time package](https://pkg.go.dev/time) | :books: Time handling |
| [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) | :books: Quiet hours |
| [Time parsing](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) | :books: Time parsing |
