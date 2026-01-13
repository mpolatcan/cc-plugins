# Feature: Sound Preview

Hear sound before confirming selection in configure.

## Summary

Preview mode during configuration that lets users hear sounds before saving their selection.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

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

## References

- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
