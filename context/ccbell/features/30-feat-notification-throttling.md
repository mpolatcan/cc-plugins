# Feature: Notification Throttling

Limit maximum notifications per time period.

## Summary

Prevent notification spam by limiting the total number of notifications within a configurable time window.

## Motivation

- Prevent audio chaos during high-activity periods
- Avoid overwhelming the user with sounds
- Create breathing room between notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Throttling Configuration

```json
{
  "throttling": {
    "enabled": true,
    "max_count": 5,
    "window_minutes": 1,
    "action": "silence"  // or "merge", "queue"
  }
}
```

### Implementation

```go
type ThrottleConfig struct {
    Enabled    bool   `json:"enabled"`
    MaxCount   int    `json:"max_count"`
    WindowMins int    `json:"window_minutes"`
    Action     string `json:"action"` // "silence", "merge", "queue"
}

type ThrottleState struct {
    Count     int
    WindowEnd time.Time
}
```

### Throttle Check

```go
func (c *CCBell) isThrottled(eventType string) (bool, error) {
    if c.throttleConfig == nil || !c.throttleConfig.Enabled {
        return false, nil
    }

    now := time.Now()
    state := c.throttleState[eventType]

    // Check if window has expired
    if state.WindowEnd.Before(now) {
        // Reset window
        c.throttleState[eventType] = ThrottleState{
            Count:     0,
            WindowEnd: now.Add(time.Duration(c.throttleConfig.WindowMins) * time.Minute),
        }
        return false, nil
    }

    // Check count
    if state.Count >= c.throttleConfig.MaxCount {
        log.Debug("Throttled: %s (count: %d, max: %d)",
            eventType, state.Count, c.throttleConfig.MaxCount)
        return true, nil
    }

    // Increment count
    state.Count++
    c.throttleState[eventType] = state

    return false, nil
}
```

### Throttle Actions

| Action | Description |
|--------|-------------|
| `silence` | Skip notification when throttled |
| `merge` | Combine throttled notifications into one |
| `queue` | Queue and play later |

### Commands

```bash
/ccbell:throttle status      # Show current throttling status
/ccbell:throttle reset       # Reset all throttle windows
/ccbell:throttle configure   # Interactive setup
```

---

## Audio Player Compatibility

Throttling operates before audio player:
- Decides whether to call `player.Play()`
- Same player compatibility
- No player changes required

---

## Implementation

### State Management

```go
// Extend State struct
type State struct {
    LastPlayed     map[string]time.Time `json:"lastPlayed,omitempty"`
    Cooldowns      map[string]time.Time `json:"cooldowns,omitempty"`
    EventCounters  map[string]int       `json:"eventCounters,omitempty"`
    ThrottleState  map[string]*ThrottleState `json:"throttleState,omitempty"`
}
```

### Integration

```go
// In main.go
if c.throttleConfig.Enabled {
    throttled, err := c.isThrottled(eventType)
    if throttled {
        log.Debug("Notification throttled: %s", eventType)
        return nil
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence pattern
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Time-window pattern
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time-based throttling |
| Linux | ✅ Supported | Time-based throttling |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
