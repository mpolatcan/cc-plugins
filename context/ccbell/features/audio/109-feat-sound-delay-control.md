# Feature: Sound Delay Control

Control playback delay for sounds.

## Summary

Add configurable delay before playing sounds.

## Motivation

- Sync with visual cues
- Delayed notifications
- Scheduling sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Delay Types

| Type | Description | Example |
|------|-------------|---------|
| Fixed | Fixed delay | 500ms |
| Random | Random range | 100-500ms |
| Progressive | Increasing delay | 100, 200, 300ms |

### Configuration

```go
type DelayConfig struct {
    Enabled     bool    `json:"enabled"`
    DefaultMs   int     `json:"default_ms"`     // default delay
    PerEvent    map[string]int `json:"per_event"` // event -> delay
    RandomMin   int     `json:"random_min_ms"`  // random min
    RandomMax   int     `json:"random_max_ms"`  // random max
    UseRandom   bool    `json:"use_random"`     // enable random
    Progressive bool    `json:"progressive"`    // increasing delay
    MaxDelay    int     `json:"max_delay_ms"`   // maximum delay
}

type DelayState struct {
    CurrentDelay int       `json:"current_delay"`
    LastPlayTime time.Time `json:"last_play_time"`
}
```

### Commands

```bash
/ccbell:delay set 500                   # Set default 500ms
/ccbell:delay set stop 200              # Stop event: 200ms
/ccbell:delay random 100 500            # Random 100-500ms
/ccbell:delay progressive 100 50        # Start 100ms, +50ms each
/ccbell:delay disable                   # Disable delay
/ccbell:delay status                    # Show delay status
/ccbell:delay test                      # Test delay
```

### Output

```
$ ccbell:delay status

=== Sound Delay Control ===

Status: Enabled
Default: 500ms

Per-Event Delays:
  stop: 200ms
  permission_prompt: 100ms
  idle_prompt: 500ms
  subagent: 300ms

Random Mode: Disabled
  Range: -

Progressive: Disabled

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Delay control works with existing audio player:
- Adds delay before `player.Play()`
- Same format support
- No player changes required

---

## Implementation

### Delay Execution

```go
func (d *DelayManager) Play(soundPath string, volume float64) error {
    delay := d.calculateDelay()

    if delay > 0 {
        log.Debug("Delaying playback by %dms", delay)
        time.Sleep(time.Duration(delay) * time.Millisecond)
    }

    player := audio.NewPlayer(d.pluginRoot)
    return player.Play(soundPath, volume)
}

func (d *DelayManager) calculateDelay() int {
    if !d.config.Enabled {
        return 0
    }

    if d.config.UseRandom && d.config.RandomMin > 0 {
        // Random delay within range
        rand.Seed(time.Now().UnixNano())
        return rand.Intn(d.config.RandomMax-d.config.RandomMin) + d.config.RandomMin
    }

    return d.config.DefaultMs
}
```

### Progressive Delay

```go
func (d *DelayManager) calculateProgressiveDelay(eventType string) int {
    if !d.config.Progressive {
        return d.config.DefaultMs
    }

    state := d.getState(eventType)
    baseDelay := d.config.DefaultMs
    increment := d.config.MaxDelay / 10 // progressive steps

    delay := baseDelay + (state.CurrentDelay * increment)
    d.state[eventType].CurrentDelay++

    // Cap at max delay
    if delay > d.config.MaxDelay {
        delay = d.config.MaxDelay
    }

    return delay
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go standard library |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Playback with delay
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
