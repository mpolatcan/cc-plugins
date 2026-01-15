---
name: Sound Preview
description: Preview mode during configuration that lets users hear sounds before saving their selection
---

# Feature: Sound Preview

Preview sounds during configuration or testing, allowing users to hear sounds before committing to selection.

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

Preview mode enables users to hear sounds before committing to a selection. This feature has two integration points:

1. **CLI Preview** - Enhanced `/ccbell:test` command with `--preview` and `--loop` flags for testing sounds
2. **Configure Integration** - Inline sound preview during `/ccbell:configure` wizard flow

Both capabilities use the same underlying preview mechanism, allowing users to make informed decisions about sound selections.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Hear before you choose, no more config guessing |
| :memo: Use Cases | A/B testing sounds, finding perfect sound |
| :dart: Value Proposition | Faster setup, no configuration commits needed |

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
| :keyboard: Commands | Enhanced `test` command with --preview and --loop flags |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Bash, Read tools for preview playback |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Preview mode with optional infinite loop |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

### CLI Preview (Test Command)

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | `/ccbell:test stop --preview` or `/ccbell:test stop --preview --loop` |
| :wrench: Configuration | No config changes - CLI flag based |
| :gear: Default Behavior | Single playback unless --loop specified |

### Configure Integration

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | During `/ccbell:configure`, auto-play sound after selection |
| :wrench: Configuration | Uses preview flags from test command |
| :gear: Default Behavior | Optional preview - user can skip |

### Workflow Examples

```bash
# CLI: Preview once
/ccbell:test stop --preview

# CLI: Preview in loop (for volume testing)
/ccbell:test stop --preview --loop
# Press Ctrl+C to stop

# Configure: Inline preview during setup
/ccbell:configure
# 1. Select event: stop
# 2. Select sound: bundled:stop
# 3. [Auto-plays sound]
# 4. Select volume: 0.5
# 5. [Auto-plays at volume 0.5]
```

## Repository Impact

### cc-plugins

| File | Description | Impact |
|------|-------------|--------|
| `plugins/ccbell/.claude-plugin/plugin.json` | Plugin manifest (version bump) | Required |
| `plugins/ccbell/scripts/ccbell.sh` | Download script (version sync) | Required |
| `plugins/ccbell/hooks/hooks.json` | Hook definitions (no change) | None |
| `plugins/ccbell/commands/test.md` | Add preview/loop flags | Required |
| `plugins/ccbell/commands/configure.md` | Add inline preview during config | Required |
| `plugins/ccbell/sounds/` | Audio files (no change) | None |

### ccbell

| File | Description | Impact |
|------|-------------|--------|
| `main.go` | Main entry point (version bump) | Required |
| `config/config.go` | Configuration handling (no change) | None |
| `audio/player.go` | Add preview mode with loop control | Required |
| `hooks/*.go` | Hook implementations (no change) | None |

## Implementation Plan

### ccbell (Binary)

**Phase 1: Preview Core**
1. Add `--preview` and `--loop` flags to test command
2. Add preview mode to `Player.Play()` with loop control
3. Support infinite loop for volume testing
4. Update version in `main.go`
5. Tag and release vX.X.X

### cc-plugins

**Phase 1: CLI Preview**
1. Update `test.md` with preview/loop flags documentation
2. Update `plugin.json` version
3. Update `ccbell.sh` version sync

**Phase 2: Configure Integration**
1. Update `configure.md` with inline preview workflow
2. After each sound/volume selection, call `ccbell.sh <event> --preview`
3. Add "Replay" option for users who want to hear again

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | ❌ |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported (afplay) |
| ✅ | Linux supported (aplay, sox) |
| ✅ | No external dependencies (uses system commands) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. Preview flags can be added to test command.

### Claude Code Hooks

No new hooks needed - preview mode uses existing playback.

### Audio Playback

Preview mode adds loop control for volume testing scenarios.

### Preview Mode Implementation

#### Loop Control Options

**afplay (macOS)**
| :speaker: mpv/paplay/aplay/ffplay (Linux) | Linux audio players (auto-detected) |
- No native loop option
- Use `-t 0` for infinite duration with external loop control
- Alternative: run afplay in background, kill on signal

```bash
# Manual loop control
while true; do
    afplay sound.aiff
    sleep 0.5  # Pause between plays
done
```

**aplay (Linux/ALSA)**
- `-l` flag for loop count (0 = infinite)
- `aplay -l 0 sound.wav`

**sox (Cross-platform)**
- `play sound.wav repeat -1` for infinite loop
- `play sound.wav repeat 3` for 3 plays

#### Volume Testing Pattern

```go
func PreviewWithVolume(sound string, volume float64, loop bool) {
    cmd := exec.Command("afplay", "-v", fmt.Sprintf("%f", volume), sound)
    if loop {
        // Run in goroutine with interrupt handling
        go func() {
            for {
                cmd.Run()
            }
        }()
        // Wait for interrupt
        signalChan := make(chan os.Signal, 1)
        signal.Notify(signalChan, os.Interrupt)
        <-signalChan
        cmd.Process.Kill()
    } else {
        cmd.Run()
    }
}
```

### Preview Features

- `--preview` flag for single playback
- `--loop` flag for infinite loop (volume testing)
- Works with all sound sources (bundled, custom, pack)
- Volume control during preview
- Keyboard interrupt to stop loop
- Progress indicator for long sounds
- Compare mode for A/B testing

### A/B Testing Workflow

1. Preview sound A with `--preview`
2. Adjust volume if needed
3. Preview sound B with `--preview`
4. Compare and decide

```bash
# A/B comparison
/ccbell:test stop --preview --volume 0.5
/ccbell:test notification --preview --volume 0.5
```

## Research Sources

| Source | Description |
|--------|-------------|
| [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Audio player |
| [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) | :books: Implementation |
| [afplay man page](https://ss64.com/osx/afplay.html) | :books: macOS audio playback |
| [SoX play](http://sox.sourceforge.net/sox.html) | :books: Cross-platform audio tool |
| [Go exec package](https://pkg.go.dev/os/exec) | :books: Command execution |
