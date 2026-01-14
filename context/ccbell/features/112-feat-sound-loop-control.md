# Feature: Sound Loop Control

Control loop behavior for sounds.

## Summary

Control how sounds loop during playback.

## Motivation

- Continuous notifications
- Ambient sounds
- Repeated alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Loop Options

| Option | Description | Example |
|--------|-------------|---------|
| Count | Loop N times | loop 3 |
| Infinite | Loop forever | loop -1 |
| Until | Loop until event | until stopped |
| Interval | Loop with gap | interval 500ms |

### Configuration

```go
type LoopConfig struct {
    Enabled     bool    `json:"enabled"`
    DefaultCount int    `json:"default_count"`  // -1 = infinite
    IntervalMs  int     `json:"interval_ms"`    // gap between loops
    PerEvent    map[string]LoopSettings `json:"per_event"`
    FadeBetween bool    `json:"fade_between"`  // crossfade loops
    FadeMs      int     `json:"fade_ms"`       // crossfade duration
}

type LoopSettings struct {
    Count       int     `json:"count"`
    IntervalMs  int     `json:"interval_ms"`
    FadeBetween bool    `json:"fade_between"`
    MaxDuration int     `json:"max_duration_ms"` // stop after duration
}
```

### Commands

```bash
/ccbell:loop enable                   # Enable looping
/ccbell:loop disable                  # Disable looping
/ccbell:loop set 3                    # Loop 3 times
/ccbell:loop set infinite             # Loop forever
/ccbell:loop set interval 500         # 500ms between loops
/ccbell:loop set event stop 5         # Stop event: 5 loops
/ccbell:loop set fade 100             # 100ms crossfade
/ccbell:loop test                     # Test loop
```

### Output

```
$ ccbell:loop set 3

=== Sound Loop Control ===

Status: Enabled
Default: 3 loops
Interval: 0ms (immediate)
Fade Between: No

Per-Event Settings:
  stop: 3 loops
  permission_prompt: 1 loop
  idle_prompt: infinite

Preview:
  [██████████|██████████|██████████]
   Play 1      Play 2      Play 3

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Loop control works with existing audio player:
- Multiple `player.Play()` calls
- Same format support
- Can use ffplay loop option

---

## Implementation

### Loop Playback

```go
func (l *LoopManager) Play(soundPath string, volume float64, eventType string) error {
    settings := l.getSettings(eventType)
    player := audio.NewPlayer(l.pluginRoot)

    if settings.Count == -1 {
        // Infinite loop
        for {
            if err := player.Play(soundPath, volume); err != nil {
                return err
            }
            if settings.IntervalMs > 0 {
                time.Sleep(time.Duration(settings.IntervalMs) * time.Millisecond)
            }
        }
    }

    // Fixed count
    for i := 0; i < settings.Count; i++ {
        if err := player.Play(soundPath, volume); err != nil {
            return err
        }

        // Interval between loops
        if i < settings.Count-1 && settings.IntervalMs > 0 {
            time.Sleep(time.Duration(settings.IntervalMs) * time.Millisecond)
        }
    }

    return nil
}
```

### FFplay Loop Option

```go
func (l *LoopManager) playWithFFplay(soundPath string, volume float64, count int) error {
    loopArg := -1
    if count > 0 {
        loopArg = count - 1 // ffplay loop N means play N+1 times
    }

    cmd := exec.Command("ffplay", "-nodisp", "-autoexit",
        "-loop", fmt.Sprintf("%d", loopArg),
        "-volume", fmt.Sprintf("%d", int(volume*100)),
        soundPath)

    return cmd.Start()
}
```

### Fade Between Loops

```go
func (l *LoopManager) playWithFade(soundPath string, volume float64, count int, fadeMs int) error {
    player := audio.NewPlayer(l.pluginRoot)

    for i := 0; i < count; i++ {
        // Play with fade in
        if i > 0 && fadeMs > 0 {
            l.playWithFadeIn(soundPath, volume, fadeMs)
        } else {
            player.Play(soundPath, volume)
        }

        // Wait for sound duration minus fade
        duration := getSoundDuration(soundPath)
        time.Sleep(duration - time.Duration(fadeMs)*time.Millisecond)

        // Fade out
        if i < count-1 && fadeMs > 0 {
            l.playFadeOut(soundPath, volume, fadeMs)
        }
    }

    return nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (multiple plays) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Loop calls
- [ffplay loop](https://ffmpeg.org/ffplay.html) - ffplay loop option

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
