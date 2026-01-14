# Feature: Sound Preview 👂

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Preview mode during configuration that lets users hear sounds before saving their selection.

## Motivation

- Hear sounds before committing to them
- Compare different sounds easily
- Test volume levels
- Make informed configuration choices

---

## Benefit

- **Informed decisions**: Hear before you choose, no more config guessing
- **Easier comparison**: A/B test sounds side by side
- **No configuration commits**: Preview without saving to config
- **Faster setup**: Find the perfect sound faster with instant feedback

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Audio |

---

## Technical Feasibility

### Current Audio Player Analysis

The current `internal/audio/player.go` has a `Play()` method that:
- Takes sound path and volume
- Uses native players (afplay, mpv, etc.)
- Non-blocking playback

**Key Finding**: Sound preview is a minimal extension of the existing Play functionality.

### Preview Command

```bash
/ccbell:test stop --preview
# Plays sound once without triggering notification logic

/ccbell:test stop --preview --loop
# Loops sound for volume testing
```

### Configure Flow

```
Select sound for 'stop':
  [1] bundled:stop [test]
  [2] custom:/path/sound.wav [test] [remove]

Select [1-2] or [t] test: t
Playing bundled:stop...
[Plays sound]

  [1] bundled:stop [test] [* selected]
  [2] custom:/path/sound.wav [test] [remove]

Select [1-2] or [d] done: d
Saved: bundled:stop
```

## Implementation

```go
func (c *CCBell) previewSound(soundRef string, loop bool) error {
    path, err := c.resolveSoundPath(soundRef)
    if err != nil {
        return err
    }

    player := c.newPlayer()
    defer player.Close()

    if loop {
        return player.PlayLoop(path)
    }
    return player.Play(path)
}
```

---

## Feasibility Research

### Audio Player Compatibility

Sound preview uses the existing audio player infrastructure:
- Same `Player.Play()` method
- Same format support
- Same volume control

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Uses existing audio player |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses afplay |
| Linux | ✅ Supported | Uses mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Loop Support

For loop preview, use FFmpeg or SoX:

```bash
# With FFmpeg (if available)
ffplay -nodisp -loop 0 -volume 50 sound.aiff

# Stop with SIGINT
```

### Preview Duration

For non-loop preview, rely on the sound file's natural length. Current players (afplay, ffplay) stop automatically.

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Commands** | Modify | Add `--preview` and `--loop` flags to `test` command |
| **Core Logic** | Modify | Add preview mode to `Player.Play()` with loop control |
| **Player** | Modify | Extend to support infinite loop for preview |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add preview capability |
| **commands/test.md** | Update | Add --preview flag documentation |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    preview := flag.Bool("preview", false, "Preview sound without saving")
    loop := flag.Bool("loop", false, "Loop preview until interrupted")
    flag.Parse()

    eventType := os.Args[len(os.Args)-1]
    eventCfg := cfg.GetEventConfig(eventType)

    player := audio.NewPlayer()

    if *preview {
        if *loop {
            fmt.Printf("Playing %s on loop (Ctrl+C to stop)...\n", *eventCfg.Sound)
            player.Play(*eventCfg.Sound, *eventCfg.Volume, audio.InfiniteLoop)
        } else {
            fmt.Printf("Previewing %s...\n", *eventCfg.Sound)
            player.Play(*eventCfg.Sound, *eventCfg.Volume)
        }
        return
    }
    // Normal test behavior
}
```

**ccbell - internal/audio/player.go:**
```go
type LoopMode int

const (
    NoLoop LoopMode = iota
    InfiniteLoop
)

func (p *Player) Play(sound string, volume float64, loopMode ...LoopMode) error {
    loop := NoLoop
    if len(loopMode) > 0 {
        loop = loopMode[0]
    }

    args := p.getBaseArgs(sound, volume)

    switch loop {
    case InfiniteLoop:
        switch p.playerType {
        case "ffplay":
            args = append([]string{"-loop", "-1"}, args...)
        case "mpv":
            args = append([]string{"--loop=inf"}, args...)
        }
    }

    cmd := exec.Command(p.command, args...)
    return cmd.Run()
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with preview capability |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.2.31+
- **Config Schema Change**: No schema change, adds `--preview` flag to test command
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add preview option during sound selection)
  - `plugins/ccbell/commands/test.md` (add --preview flag documentation)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Update `commands/configure.md` with preview capability during setup
- [ ] Update `commands/test.md` with --preview flag
- [ ] When ccbell v0.2.31+ releases, sync version to cc-plugins

---

## References

### ccbell Implementation Research

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - `Play()` method to use for preview
- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Shows non-blocking playback via `cmd.Start()`
- [ffplay loop option](https://ffmpeg.org/ffplay.html) - For loop preview functionality

---

[Back to Feature Index](index.md)
