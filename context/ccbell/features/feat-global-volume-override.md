---
name: Global Volume Override
description: Temporarily adjust notification volume without modifying the config file
category: Audio
---

# Feature: Global Volume Override

Temporarily adjust notification volume without modifying the config file, using command-line flags.

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

Temporarily adjust notification volume without modifying the config file. Allows quick volume adjustments via CLI flags for testing or session-based control.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Test volume without modifying config |
| :memo: Use Cases | Session-based control, faster iteration |
| :dart: Value Proposition | No permanent commitment, convenient one-liners |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | 🟡 Medium | |
| :construction: Complexity | 🟢 Low | |
| :warning: Risk Level | 🟢 Low | |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | Uses existing test command with volume flag |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash, Write, Read tools for volume control |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Volume override passed to afplay command |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `ccbell stop --volume 0.8` or `/ccbell:test stop --volume 0.8` |
| :wrench: Configuration | No config changes - CLI flag only |
| :gear: Default Behavior | Uses config volume unless override specified |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `test.md` with volume flag docs |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (add `-v/--volume` flag) |
| `config/config.go` | :wrench: Configuration handling (no change) |
| `audio/player.go` | :speaker: Accept volume override in Play() |
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

1. Add -v/--volume flag to main command
2. Pass volume override to player.Play()
3. Update version in main.go
4. Tag and release vX.X.X
5. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ❌ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported (afplay) |
| ✅ | Linux supported (amixer, pactl) |
| ✅ | No external dependencies (uses system commands) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Volume flag can be added to test command.

### Claude Code Hooks

No new hooks needed - uses existing event hooks.

### Audio Playback

Volume override is passed to afplay with the `-volume` parameter.

### Volume Control Options

#### Platform-Native Volume Control

**macOS afplay**
- **Command**: `afplay -v <volume> <file>`
- **Volume Range**: 0.0 to 1.0 (linear)
- **Note**: Smooth volume adjustment

**Linux (PulseAudio)**
- **Command**: `amixer -D pulse sset Master <volume>%`
- **Alternative**: `pactl set-sink-volume @DEFAULT_SINK@ <volume>`
- **Volume Range**: 0% to 100%

**Linux (ALSA)**
- **Command**: `amixer sset Master <volume>%`
- **Volume Range**: 0% to 100%

#### Go Audio Libraries for Advanced Control

**Oto (Recommended for Go)**
- **URL**: https://github.com/ebitengine/oto
- **Features**:
  - Low-level cross-platform audio playback
  - Real-time volume control
  - Multiple audio streams
  - Minimal latency
- **Platforms**: Windows, macOS, Linux, Android, iOS
- **Best For**: When native afplay isn't sufficient

**Beep**
- **URL**: https://github.com/gopxl/beep
- **Features**:
  - Rich library of compositors and effects
  - Loop, pause/resume, volume control
  - Mix multiple sounds
  - Change playback speed
- **Best For**: Advanced audio manipulation, sound effects

### Volume Control Considerations

- Linear vs logarithmic volume perception
- Platform-specific volume ranges
- Smooth transitions to avoid popping
- Mute toggle functionality

### Other Findings

Volume flag behavior:
- `-v 0.8` or `--volume 0.8` for specific volume
- Overrides event-level and global volume settings
- Only affects the current invocation

## Research Sources

| Source | Description |
|--------|-------------|
| [Oto - Go Audio Library](https://github.com/ebitengine/oto) | :books: Cross-platform audio playback |
| [Beep - Go Audio Library](https://github.com/gopxl/beep) | :books: Audio synthesis and effects |
| [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main entry point |
| [Config volume](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L36) | :books: Volume configuration |
| [Player volume](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49) | :books: Volume handling |
| [afplay man page](https://ss64.com/osx/afplay.html) | :books: macOS afplay documentation |
