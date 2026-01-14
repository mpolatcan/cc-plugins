# Feature: Sound Randomization 🎲

## Summary

Instead of a single sound per event, allow users to define multiple sounds that are randomly selected when an event triggers. This adds variety and helps users recognize different events.

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

## Technical Feasibility

### Configuration

```json
{
  "events": {
    "stop": {
      "sounds": [
        "bundled:stop",
        "bundled:stop_alt1",
        "custom:/path/to/custom1.wav"
      ],
      "weights": [1, 1, 1]
    }
  }
}
```

### Implementation

```go
type Event struct {
    Enabled   *bool     `json:"enabled,omitempty"`
    Sounds    []string  `json:"sounds,omitempty"`
    Weights   []float64 `json:"weights,omitempty"`
    Volume    *float64  `json:"volume,omitempty"`
    Cooldown  *int      `json:"cooldown,omitempty"`
}

func SelectRandomSound(eventCfg *Event) string {
    if len(eventCfg.Sounds) == 0 {
        return ""
    }
    if len(eventCfg.Sounds) == 1 {
        return eventCfg.Sounds[0]
    }

    if len(eventCfg.Weights) == len(eventCfg.Sounds) {
        return selectWeighted(eventCfg.Sounds, eventCfg.Weights)
    }

    randIndex := rand.Intn(len(eventCfg.Sounds))
    return eventCfg.Sounds[randIndex]
}

func selectWeighted(items []string, weights []float64) string {
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

### Commands

```bash
/ccbell:configure randomize stop     # Add randomization to stop event
/ccbell:test stop --random           # Test random sound selection
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Change `Sound` (string) to `Sounds` ([]string), add `Weights` ([]float64) |
| **Core Logic** | Add | Add `SelectRandomSound(event string) string` function |
| **Config Loading** | Modify | Handle both `sound` and `sounds` for backward compatibility |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add sound randomization configuration |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Current config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)
- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [Config loading](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go)

---

[Back to Feature Index](index.md)
