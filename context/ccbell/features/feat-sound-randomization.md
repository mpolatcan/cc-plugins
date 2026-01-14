# Feature: Sound Randomization 🎲

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

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. This adds variety and helps users recognize different events even without looking.

## Motivation

- Prevent notification fatigue from repetitive sounds
- Add variety to the notification experience
- Make different events more distinguishable
- Create a more dynamic working environment

---

## Benefit

- **Reduced monotony**: Fresh sounds keep notifications feeling new
- **Better recognition**: Distinct sounds per event without manual switching
- **Customizable variety**: Choose how many sounds to cycle through
- **More engaging experience**: Notifications feel less mechanical and repetitive

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Low |
| **Category** | Audio |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Change `Sound` (string) to `Sounds` ([]string), add `Weights` ([]float64) |
| **Core Logic** | Add | Add `SelectRandomSound(event string) string` function |
| **Config Loading** | Modify | Handle both `sound` and `sounds` for backward compatibility |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add sound randomization configuration |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/config.go:**
```go
type Event struct {
    Enabled   *bool     `json:"enabled,omitempty"`
    Sounds    []string  `json:"sounds,omitempty"` // Array for randomization
    Weights   []float64 `json:"weights,omitempty"` // Optional weights
    Volume    *float64  `json:"volume,omitempty"`
    Cooldown  *int      `json:"cooldown,omitempty"`
}

func (c *CCBell) SelectRandomSound(event string) string {
    eventCfg := c.config.Events[event]
    if eventCfg == nil || len(eventCfg.Sounds) == 0 {
        return ""
    }

    if len(eventCfg.Sounds) == 1 {
        return eventCfg.Sounds[0]
    }

    // Use weights if provided, otherwise uniform distribution
    if len(eventCfg.Weights) == len(eventCfg.Sounds) {
        return c.selectWeighted(eventCfg.Sounds, eventCfg.Weights)
    }

    // Uniform random
    randIndex := rand.Intn(len(eventCfg.Sounds))
    return eventCfg.Sounds[randIndex]
}

func (c *CCBell) selectWeighted(items []string, weights []float64) string {
    total := 0.0
    for _, w := range weights {
        total += w
    }

    r := rand.Float64() * total
    cumulative := 0.0

    for i, w := range weights {
        cumulative += w
        if r <= cumulative {
            return items[i]
        }
    }

    return items[len(items)-1]
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cfg := config.Load(homeDir)
    ccbell := NewCCBell(cfg)

    eventType := os.Args[1]
    sound := ccbell.SelectRandomSound(eventType)

    eventCfg := cfg.GetEventConfig(eventType)
    player := audio.NewPlayer()
    player.Play(sound, *eventCfg.Volume)
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with sound randomization |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Changes `sound` (string) to `sounds` (array) with optional `weights`
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add sound randomization configuration)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag
- **Backward Compatible**: Supports both `sound` (single) and `sounds` (array) formats

### Implementation Checklist

- [ ] Update `commands/configure.md` with sound array selection
- [ ] Document weighted random configuration
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

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
