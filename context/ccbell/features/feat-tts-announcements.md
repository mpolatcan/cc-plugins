---
name: TTS Announcements
description: Play spoken announcements instead of or alongside audio files
---

# TTS Announcements

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS.

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

Play spoken announcements instead of (or alongside) audio files. Announce events like "Claude finished" or "Permission needed" using TTS for accessibility and hands-free awareness.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Voice announcements help users with hearing impairments |
| :memo: Use Cases | Hands-free awareness, rich context announcements |
| :dart: Value Proposition | Personalized experience, accessibility-first |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `[Low]` |
| :construction: Complexity | `[High]` |
| :warning: Risk Level | `[High]` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `tts` command with configure, voices, test options |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for TTS execution |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | TTS output played through afplay or native TTS |
| :computer: Platform Support | macOS `say`, Linux Piper/Kokoro |
| :musical_note: Audio Formats | TTS generates audio on demand |

### External Dependencies

Are external tools or libraries required?

TTS engines (say, piper, kokoro) required for non-macOS platforms.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:tts configure`, `/ccbell:tts voices`, `/ccbell:tts test stop` |
| :wrench: Configuration | Adds `tts` section with engine, voice, phrases, cache options |
| :gear: Default Behavior | Uses native TTS when available (macOS say) |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Add `tts.md` command doc |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `tts` section |
| `audio/player.go` | :speaker: TTS integration with audio playback |
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
# 1. Add tts section to config structure
# 2. Create internal/tts/tts.go
# 3. Implement TTSManager with Speak() method
# 4. Support multiple engines: say (macOS), piper, kokoro
# 5. Add caching for generated speech
# 6. Add tts command with configure/voices/test options
# 7. Update version in main.go
# 8. Tag and release vX.X.X
# 9. Sync version to cc-plugins
```

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| say | macOS | Native TTS | `[Yes]` |
| piper | Linux | TTS engine | `[Yes]` |
| kokoro | Linux | TTS engine | `[Yes]` |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New tts command can be added.

### Claude Code Hooks

No new hooks needed - TTS integrated into main flow.

### Audio Playback

TTS output played through audio player or native command.

### Other Findings

TTS features:
- Multiple engine support (say, piper, kokoro)
- Configurable phrases per event
- Voice selection per engine
- Caching for performance
- Works alongside or instead of sounds

## Research Sources

| Source | Description |
|--------|-------------|
| [Piper TTS - GitHub](https://github.com/rhasspy/piper) | :books: Piper TTS |
| [Kokoro-82M - Hugging Face](https://huggingface.co/hexgrad/Kokoro-82M) | :books: Kokoro TTS |
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
