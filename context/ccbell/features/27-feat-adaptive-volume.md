# Feature: Adaptive Volume

Automatically adjust volume based on time of day.

## Summary

Lower notification volume during night hours and gradually increase during the day, respecting user-defined schedules.

## Motivation

- Avoid loud notifications at night
- Automatically adapt to different environments
- Reduce notification fatigue during work hours

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Volume Schedule Configuration

```json
{
  "adaptive_volume": {
    "enabled": true,
    "schedule": {
      "night": {
        "start": "22:00",
        "end": "07:00",
        "volume": 0.2
      },
      "morning": {
        "start": "07:00",
        "end": "09:00",
        "volume": 0.4
      },
      "day": {
        "start": "09:00",
        "end": "18:00",
        "volume": 0.6
      },
      "evening": {
        "start": "18:00",
        "end": "22:00",
        "volume": 0.5
      }
    }
  }
}
```

### Implementation

```go
func getAdaptiveVolume(cfg *Config, baseVolume float64) float64 {
    if cfg.AdaptiveVolume == nil || !cfg.AdaptiveVolume.Enabled {
        return baseVolume
    }

    now := time.Now()
    currentTime := now.Format("15:04")

    for period, schedule := range cfg.AdaptiveVolume.Schedule {
        if isTimeInRange(currentTime, schedule.Start, schedule.End) {
            return schedule.Volume
        }
    }

    return baseVolume // Fallback to configured volume
}

func isTimeInRange(current, start, end string) bool {
    // Parse times and compare
    // Handle overnight ranges (e.g., 22:00-07:00)
}
```

### Volume Gradient Between Periods

```go
// Optional: gradual volume transition
func getGradualVolume(targetVolume float64, transitionMinutes int) float64 {
    // Interpolate volume based on time since period start
}
```

---

## Audio Player Compatibility

Adaptive volume modifies volume before passing to player:
- Uses existing volume handling (0.0-1.0)
- Works with all players (afplay, mpv, ffplay)
- No player changes required

---

## Implementation

### Config Changes

```go
type AdaptiveVolume struct {
    Enabled   bool                   `json:"enabled"`
    Schedule  map[string]*VolumePeriod `json:"schedule"`
}

type VolumePeriod struct {
    Start   string  `json:"start"`   // HH:MM
    End     string  `json:"end"`     // HH:MM
    Volume  float64 `json:"volume"`  // 0.0-1.0
}
```

### Integration

```go
// In main.go, when getting volume
effectiveVolume := *eventCfg.Volume

if cfg.AdaptiveVolume != nil && cfg.AdaptiveVolume.Enabled {
    adaptiveVol := getAdaptiveVolume(cfg, effectiveVolume)
    if adaptiveVol != effectiveVolume {
        log.Debug("Adaptive volume: %.2f -> %.2f", effectiveVolume, adaptiveVol)
        effectiveVolume = adaptiveVol
    }
}

player.Play(soundPath, effectiveVolume)
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### Research Sources

- [Go time parsing](https://pkg.go.dev/time)
- [Time range comparison](https://stackoverflow.com/questions/55262995/how-to-check-if-current-time-is-in-a-time-range-in-golang)

### ccbell Implementation Research

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For adaptive volume config
- [Volume handling](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49) - Volume conversion
- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Time-based logic pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time-based only |
| Linux | ✅ Supported | Time-based only |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
