# Feature: Volume Limiting

Cap maximum volume to prevent accidentally loud notifications.

## Summary

Set a maximum volume cap that prevents sounds from playing above a certain level.

## Motivation

- Prevent surprise loud sounds
- Protect hearing
- Safe defaults for new users

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Volume Cap Logic

Current volume range is 0.0-1.0.

**Key Finding**: Adding a maximum cap is simple clamping.

### Configuration

```json
{
  "volume_limit": {
    "enabled": true,
    "max_volume": 0.7,
    "warn_above": 0.5,
    "per_event_max": {
      "stop": 0.8,
      "permission_prompt": 0.6
    }
  }
}
```

### Implementation

```go
type VolumeLimitConfig struct {
    Enabled      bool             `json:"enabled"`
    MaxVolume    float64          `json:"max_volume"`
    WarnAbove    float64          `json:"warn_above"`
    PerEventMax  map[string]float64 `json:"per_event_max,omitempty"`
}

func (c *CCBell) applyVolumeLimit(eventType string, volume float64) (float64, bool) {
    if c.volumeLimit == nil || !c.volumeLimit.Enabled {
        return volume, false
    }

    // Check per-event limit
    if eventMax, ok := c.volumeLimit.PerEventMax[eventType]; ok {
        if volume > eventMax {
            log.Warn("Volume %.2f capped to %.2f for %s", volume, eventMax, eventType)
            return eventMax, true
        }
    }

    // Check global limit
    if volume > c.volumeLimit.MaxVolume {
        if volume > c.volumeLimit.WarnAbove {
            log.Warn("Volume %.2f exceeds warn level %.2f", volume, c.volumeLimit.WarnAbove)
        }
        log.Warn("Volume %.2f capped to global max %.2f", volume, c.volumeLimit.MaxVolume)
        return c.volumeLimit.MaxVolume, true
    }

    return volume, false
}
```

### Commands

```bash
/ccbell:limit set 0.7              # Set global max volume
/ccbell:limit set stop 0.8         # Set event-specific max
/ccbell:limit disable              # Disable volume limiting
/ccbell:limit status               # Show current limits
/ccbell:test stop --volume 0.9     # Will show warning if capped
```

### Warning Output

```
$ ccbell test stop --volume 0.9

Warning: Volume 0.90 capped to 0.70 (max_volume)
Playing at 0.70
```

---

## Audio Player Compatibility

Volume limiting clamps values before playback:
- Works with all audio players
- No player changes required
- Affects volume parameter only

---

## Implementation

### Clamping Function

```go
func clampVolume(volume, maxVolume float64) float64 {
    if volume > maxVolume {
        return maxVolume
    }
    if volume < 0 {
        return 0
    }
    return volume
}
```

### Integration

```go
// In main.go
effectiveVolume := *eventCfg.Volume
if c.volumeLimit != nil && c.volumeLimit.Enabled {
    effectiveVolume, capped := c.applyVolumeLimit(eventType, effectiveVolume)
    if capped {
        log.Debug("Volume capped for %s: %.2f", eventType, effectiveVolume)
    }
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

- [Volume handling](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L49) - Volume conversion
- [Config validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L127-L175) - Volume validation
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Volume parameter

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Volume clamping |
| Linux | ✅ Supported | Volume clamping |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
