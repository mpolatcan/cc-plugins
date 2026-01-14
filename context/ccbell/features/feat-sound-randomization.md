# Feature: Sound Randomization 🎲

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. This adds variety and helps users recognize different events even without looking.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Current State

ccbell already supports per-event sounds:
```json
{
  "events": {
    "stop": "bundled:stop"
  }
}
```

**Key Finding**: Sound randomization extends the config schema from single sound to array of sounds.

### Required Changes

| Component | Change |
|-----------|--------|
| Config Schema | Change `sound` to `sounds` (array) for each event |
| Selection Logic | Random index from array when event triggers |
| UI/Config | Multi-select sound picker in configure command |

### Config Change

```json
{
  "events": {
    "stop": {
      "sounds": [
        "bundled:stop",
        "bundled:stop_alt1",
        "custom:/path/to/custom1.wav",
        "custom:/path/to/custom2.mp3"
      ],
      "weight": [1, 1, 1, 1]  // Optional: weighted random
    }
  }
}
```

### Random Selection Logic

```go
func (c *CCBell) playRandomSound(event string) error {
    eventConfig := c.config.Events[event]
    if len(eventConfig.Sounds) == 0 {
        return fmt.Errorf("no sounds configured for %s", event)
    }

    // Simple random
    idx := rand.Intn(len(eventConfig.Sounds))

    // Weighted random (if weights configured)
    if len(eventConfig.Weights) > 0 {
        idx = weightedRandom(eventConfig.Weights)
    }

    sound := eventConfig.Sounds[idx]
    return c.playSound(sound)
}
```

### Weighted Random

```go
func weightedRandom(weights []int) int {
    total := 0
    for _, w := range weights {
        total += w
    }
    r := rand.Intn(total)
    cumulative := 0
    for i, w := range weights {
        cumulative += w
        if r < cumulative {
            return i
        }
    }
    return len(weights) - 1
}
```

---

## Feasibility Research

### Audio Player Compatibility

Sound randomization uses the existing audio player:
- Select random sound from pool
- Pass to existing `Player.Play()` method
- No changes to audio playback

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `math/rand` | Standard library | Free | Random selection |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Works with current player |
| Linux | ✅ Supported | Works with current player |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Config Schema Change

Extend `internal/config/config.go`:

```go
type Event struct {
    Enabled  *bool     `json:"enabled,omitempty"`
    Sound    string    `json:"sound,omitempty"`    // Legacy: single sound
    Sounds   []string  `json:"sounds,omitempty"`   // New: sound pool
    Volume   *float64  `json:"volume,omitempty"`
    Cooldown *int      `json:"cooldown,omitempty"`
    Weights  []int     `json:"weights,omitempty"`  // For weighted random
}
```

### Backward Compatibility

Handle both `sound` (single) and `sounds` (array) in config loading.

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

## References

### Research Sources

- [Go math/rand](https://pkg.go.dev/math/rand) - For random selection

### ccbell Implementation Research

- [Current config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event struct to extend with sound array
- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - `Play()` method for playing selected sound
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For backward compatibility handling

---

[Back to Feature Index](index.md)
