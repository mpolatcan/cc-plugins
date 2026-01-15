---
name: Sound Validation
description: Check sound files and configuration for issues before use
---

# Feature: Sound Validation

Check sound files and configuration for issues before use. Proactive issue detection to prevent workflow disruptions.

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

Check sound files and configuration for issues before use. Provides clear error messages pointing to exact issues.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Find problems before they affect workflow |
| :memo: Use Cases | Reduced debugging time, proactive detection |
| :dart: Value Proposition | Prevents silent failures, peace of mind |

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
| :keyboard: Commands | Enhanced `validate` command with sounds, config, specific sound options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for validation |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - validation before playback |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | Validates supported formats |

### External Dependencies

Are external tools or libraries required?

Uses `ffprobe` for audio format validation (optional).

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:validate sounds` or `/ccbell:validate bundled:stop` |
| :wrench: Configuration | No config changes - CLI command based |
| :gear: Default Behavior | Validates all sounds and config on demand |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update `validate.md` with sound validation |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Configuration handling (no change) |
| `audio/player.go` | :speaker: Add ValidateSound() function |
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

1. Create internal/audio/validator.go
2. Implement ValidateSound(path string) function
3. Implement ValidateConfig() function
4. Add sounds, config, --json, --fix flags to validate command
5. Update version in main.go
6. Tag and release vX.X.X
7. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| ffprobe | | Audio format validation (from FFmpeg) | `[No]` |
| MediaInfo | | Alternative audio metadata extraction | `[No]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Validation enhanced with sound checks.

### Claude Code Hooks

No new hooks needed - validation command uses existing patterns.

### Audio Playback

Validation runs before any playback occurs.

### Audio Validation Tool Options

#### 1. ffprobe (Recommended - Standard)
- **URL**: https://ffmpeg.org/ffprobe.html
- **Install**: `brew install ffmpeg` (macOS), `apt install ffmpeg` (Linux)
- **Features**:
  - Part of FFmpeg suite
  - Extracts audio format, codec, duration, bitrate
  - JSON/XML output support
  - Wide format support
- **Example**: `ffprobe -v quiet -print_format json -show_format -show_streams sound.aiff`

#### 2. MediaInfo (Alternative - Rich Metadata)
- **URL**: https://mediaarea.net/en/MediaInfo
- **Install**: `brew install mediainfo` (macOS), `apt install mediainfo` (Linux)
- **Features**:
  - Superior container analysis
  - Human-readable output
  - Detailed audio metadata
  - Multiple output formats (text, JSON, XML)
- **Best For**: When ffprobe is unavailable, detailed codec information

### Validation Features

- File existence and accessibility checks
- Audio format validation (AIFF, WAV, MP3, OGG, FLAC, AAC)
- Config schema validation with JSON Schema
- Auto-fix option for common issues
- JSON output for automation integration
- Duration and sample rate verification

## Research Sources

| Source | Description |
|--------|-------------|
| [FFprobe Documentation](https://ffmpeg.org/ffprobe.html) | :books: FFprobe official documentation |
| [MediaInfo](https://mediaarea.net/en/MediaInfo) | :books: Audio/video metadata extraction |
| [FFprobe vs MediaInfo Comparison](https://probe.dev/resources/ffprobe-vs-mediainfo-comparison) | :books: Tool comparison guide |
| [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
| [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Path resolution |
| [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) | :books: Config structure |
