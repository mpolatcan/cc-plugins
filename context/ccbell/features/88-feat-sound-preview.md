# Feature: Sound Preview

Preview sounds before setting them as notification.

## Summary

Listen to sounds with preview controls before applying them.

## Motivation

- Test sounds before committing
- Compare sounds side by side
- Find the right sound for each event

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Preview Controls

| Control | Description |
|---------|-------------|
| Play | Start playback |
| Stop | Stop playback |
| Loop | Repeat playback |
| Volume slider | Adjust preview volume |
| Fade in/out | Smooth transitions |
| Progress bar | Show playback position |

### Implementation

```go
type PreviewConfig struct {
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume"` // 0.0-1.0
    Loop        bool    `json:"loop"`
    FadeInMs    int     `json:"fade_in_ms"`
    FadeOutMs   int     `json:"fade_out_ms"`
    AutoStopSec int     `json:"auto_stop_sec"` // 0 = no auto-stop
}

type PreviewSession struct {
    Config      *PreviewConfig
    Player      *audio.Player
    StartTime   time.Time
    Cancel      context.CancelFunc
}
```

### Commands

```bash
/ccbell:preview bundled:stop               # Preview once
/ccbell:preview bundled:stop --loop        # Loop playback
/ccbell:preview bundled:stop --volume 0.8  # Set volume
/ccbell:preview bundled:stop --fade 500    # 500ms fade
/ccbell:preview bundled:stop --duration 5  # 5 sec auto-stop
/ccbell:preview stop                       # Stop preview
/ccbell:preview all                        # Preview all sounds
/ccbell:preview compare bundled:stop bundled:start
```

### Output

```
$ ccbell:preview bundled:stop --loop

=== Sound Preview ===

Sound: bundled:stop
Duration: 1.234s
Volume: 70%
Status: Playing ████░░░░░░

[Stop] [Loop: On] [Volume: ─────●─────] [Set as stop] [Close]
```

---

## Audio Player Compatibility

Preview uses existing audio player:
- `player.Play()` for preview
- Same format support
- Can add loop control to player

---

## Implementation

### Preview with Loop

```go
func (p *PreviewManager) Start(config *PreviewConfig) error {
    session := &PreviewSession{
        Config:    config,
        Player:    audio.NewPlayer(p.pluginRoot),
        StartTime: time.Now(),
    }

    ctx, cancel := context.WithCancel(context.Background())
    session.Cancel = cancel

    go func() {
        for {
            select {
            case <-ctx.Done():
                return
            default:
                if err := p.playWithFade(config); err != nil {
                    return
                }
                if !config.Loop {
                    return
                }
            }
        }
    }()

    p.activeSession = session
    return nil
}

func (p *PreviewManager) Stop() {
    if p.activeSession != nil {
        p.activeSession.Cancel()
        p.activeSession = nil
    }
}
```

### Fade Effect

```go
func (p *PreviewManager) playWithFade(config *PreviewConfig) error {
    path, err := p.player.ResolveSoundPath(config.Sound, "")
    if err != nil {
        return err
    }

    // Use ffmpeg for fade effects
    args := []string{}
    if config.FadeInMs > 0 {
        args = append(args, "-af", fmt.Sprintf("afade=t:in:st=0:d=%d", config.FadeInMs/1000))
    }
    if config.FadeOutMs > 0 {
        args = append(args, "-af", fmt.Sprintf("afade=t:out:st=%d:d=%d",
            config.Duration-config.FadeOutMs/1000, config.FadeOutMs/1000))
    }

    cmd := exec.Command("ffplay", append([]string{"-nodisp", "-autoexit", "-volume", fmt.Sprintf("%d", int(config.Volume*100))}, args...)...)
    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffplay | External tool | Free | Part of ffmpeg (optional for fade) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths

### Research Sources

- [ffplay options](https://ffmpeg.org/ffplay.html)
- [FFmpeg audio filters](https://ffmpeg.org/ffmpeg-filters.html#Audio-Filters)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via afplay/ffplay |
| Linux | ✅ Supported | Via ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
