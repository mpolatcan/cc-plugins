# Feature: Sound Delay

Add configurable delay before playing notification sounds.

## Summary

Insert a delay between event trigger and sound playback for flexible timing control.

## Motivation

- Sync notifications with visual cues
- Allow time for user to switch context
- Create echo-like effects with multiple sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Architecture

The current `cmd/ccbell/main.go` processes events synchronously.

**Key Finding**: Adding delay is a simple `time.Sleep()` before playback.

### Implementation

```go
type DelayConfig struct {
    Enabled      bool    `json:"enabled"`
    DefaultDelay string  `json:"default_delay"`  // Parseable duration
    PerEvent     map[string]string `json:"per_event"`  // Event-specific delays
}
```

### Configuration

```json
{
  "delay": {
    "enabled": true,
    "default_delay": "100ms",
    "per_event": {
      "stop": "50ms",
      "permission_prompt": "200ms",
      "idle_prompt": "0ms",
      "subagent": "100ms"
    }
  }
}
```

### Implementation

```go
func (c *CCBell) playWithDelay(eventType string, soundPath string, volume float64) error {
    delay := c.getDelayForEvent(eventType)

    if delay > 0 {
        log.Debug("Waiting %v before playing sound", delay)
        time.Sleep(delay)
    }

    return c.player.Play(soundPath, volume)
}

func (c *CCBell) getDelayForEvent(eventType string) time.Duration {
    if c.delayConfig == nil || !c.delayConfig.Enabled {
        return 0
    }

    // Check per-event delay
    if delayStr, ok := c.delayConfig.PerEvent[eventType]; ok {
        if delay, err := time.ParseDuration(delayStr); err == nil {
            return delay
        }
    }

    // Default delay
    if c.delayConfig.DefaultDelay != "" {
        if delay, err := time.ParseDuration(c.delayConfig.DefaultDelay); err == nil {
            return delay
        }
    }

    return 0
}
```

### Commands

```bash
/ccbell:delay set 100ms              # Set default delay
/ccbell:delay set stop 50ms          # Set event-specific delay
/ccbell:delay reset                  # Reset to no delay
/ccbell:delay status                 # Show current delays
/ccbell:test stop --delay 200ms      # Test with specific delay
```

---

## Audio Player Compatibility

Sound delay uses Go's time package:
- `time.Sleep()` before calling player
- Works with all audio players
- No player changes required

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go time package |

---

## References

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback timing
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Delay config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | time.Sleep |
| Linux | ✅ Supported | time.Sleep |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
