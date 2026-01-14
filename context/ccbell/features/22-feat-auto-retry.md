# Feature: Auto-Retry on Failure

Automatically retry playing sounds if the audio player fails.

## Summary

Handle transient audio player failures by implementing automatic retry logic with exponential backoff.

## Motivation

- Handle race conditions in audio system
- Recover from temporary audio device issues
- Improve reliability in edge cases

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Player Failure Handling

The current `internal/audio/player.go` returns errors from `Play()`:
```go
func (p *Player) playLinux(soundPath string, volume float64) error {
    for _, playerName := range linuxAudioPlayerNames {
        if _, err := exec.LookPath(playerName); err == nil {
            args := getLinuxPlayerArgs(playerName, soundPath, volume)
            cmd := exec.Command(playerName, args...)
            return cmd.Start() // Non-blocking, may fail
        }
    }
    return errors.New("no audio player found; install pulseaudio, alsa-utils, mpv, or ffmpeg")
}
```

**Key Finding**: Adding retry logic in main.go is straightforward.

### Retry Configuration

```json
{
  "retry": {
    "enabled": true,
    "max_attempts": 3,
    "initial_delay": "100ms",
    "max_delay": "2s",
    "backoff_multiplier": 2.0
  }
}
```

### Implementation

```go
func playWithRetry(player *audio.Player, soundPath string, volume float64, cfg *Config) error {
    if cfg.Retry == nil || !cfg.Retry.Enabled {
        return player.Play(soundPath, volume)
    }

    var lastErr error
    delay := time.Duration(cfg.Retry.InitialDelayMs) * time.Millisecond

    for attempt := 0; attempt <= cfg.Retry.MaxAttempts; attempt++ {
        err := player.Play(soundPath, volume)
        if err == nil {
            if attempt > 0 {
                log.Debug("Playback succeeded on attempt %d", attempt+1)
            }
            return nil
        }

        lastErr = err
        log.Warn("Playback attempt %d failed: %v", attempt+1, err)

        if attempt < cfg.Retry.MaxAttempts {
            time.Sleep(delay)
            delay = time.Duration(float64(delay) * cfg.Retry.BackoffMultiplier)
            if delay > time.Duration(cfg.Retry.MaxDelayMs)*time.Millisecond {
                delay = time.Duration(cfg.Retry.MaxDelayMs) * time.Millisecond
            }
        }
    }

    return fmt.Errorf("playback failed after %d attempts: %w", cfg.Retry.MaxAttempts+1, lastErr)
}
```

---

## Audio Player Compatibility

Retry logic wraps the existing player:
- Retries `player.Play()` calls
- Same player compatibility
- No changes to player code required

---

## Implementation

### Config Changes

```go
type RetryConfig struct {
    Enabled          bool    `json:"enabled"`
    MaxAttempts      int     `json:"max_attempts"`
    InitialDelayMs   int     `json:"initial_delay_ms"`
    MaxDelayMs       int     `json:"max_delay_ms"`
    BackoffMultiplier float64 `json:"backoff_multiplier"`
}
```

### Main Integration

```go
// In main.go
if err := playWithRetry(player, soundPath, volume, cfg); err != nil {
    log.Error("Failed to play notification: %v", err)
    return err
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Current player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Play method to retry
- [Main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [Go time package](https://pkg.go.dev/time) - For delay handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Retry afplay |
| Linux | ✅ Supported | Retry mpv/paplay/aplay/ffplay |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
