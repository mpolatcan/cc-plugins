# Feature: Notification Burst Control

Prevent notification floods during high-activity periods.

## Summary

Limit how many notifications can fire in a short time period to prevent audio chaos.

## Motivation:

- Prevent audio chaos during errors
- Reduce notification fatigue
- Graceful degradation during issues

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Burst Configuration

```json
{
  "burst_control": {
    "enabled": true,
    "max_notifications": 5,
    "window_seconds": 10,
    "action": "silence",  // "silence", "merge", "throttle"
    "burst_cooldown": 30
  }
}
```

### Implementation

```go
type BurstConfig struct {
    Enabled         bool   `json:"enabled"`
    MaxNotifications int  `json:"max_notifications"`
    WindowSeconds   int   `json:"window_seconds"`
    Action          string `json:"action"` // "silence", "merge", "throttle"
    BurstCooldown   int   `json:"burst_cooldown"`
}

type BurstState struct {
    Count        int
    WindowStart  time.Time
    BurstEnd     time.Time
}
```

### Burst Detection

```go
func (c *CCBell) checkBurst(eventType string) (bool, error) {
    if c.burstConfig == nil || !c.burstConfig.Enabled {
        return false, nil
    }

    now := time.Now()
    state := c.burstState[eventType]

    // Check if burst cooldown is active
    if !state.BurstEnd.IsZero() && now.Before(state.BurstEnd) {
        log.Debug("Burst cooldown active for %s", eventType)
        return true, nil
    }

    // Check if window has expired
    windowEnd := state.WindowStart.Add(time.Duration(c.burstConfig.WindowSeconds) * time.Second)
    if now.After(windowEnd) {
        // Reset window
        state.Count = 0
        state.WindowStart = now
    }

    // Increment count
    state.Count++
    c.burstState[eventType] = state

    // Check if burst limit exceeded
    if state.Count >= c.burstConfig.MaxNotifications {
        // Trigger burst cooldown
        state.BurstEnd = now.Add(time.Duration(c.burstConfig.BurstCooldown) * time.Second)
        c.burstState[eventType] = state

        log.Warn("Burst detected for %s: %d notifications in %ds",
            eventType, state.Count, c.burstConfig.WindowSeconds)

        return true, nil
    }

    return false, nil
}
```

### Commands

```bash
/ccbell:burst status              # Show burst status
/ccbell:burst set 5/10s           # Max 5 in 10 seconds
/ccbell:burst set --action silence
/ccbell:burst disable             # Disable burst control
/ccbell:burst reset               # Reset burst state
```

### Output

```
$ ccbell:burst status

=== Burst Control ===

Status: Enabled
Limit: 5 notifications per 10 seconds
Action: silence
Burst cooldown: 30s

Current burst windows:
  stop: 3/5 (window: 8s remaining)
  permission_prompt: 1/5 (window: 10s remaining)

No active burst cooldown
```

---

## Audio Player Compatibility

Burst control operates before audio playback:
- Decides whether to call `player.Play()`
- No player changes required
- Same audio player when playing

---

## Implementation

### Burst State Management

```go
type BurstMonitor struct {
    config *BurstConfig
    state  map[string]*BurstState
    mutex  sync.Mutex
}

func (m *BurstMonitor) ShouldAllow(eventType string) (bool, time.Duration) {
    m.mutex.Lock()
    defer m.mutex.Unlock()

    // ... burst check logic ...
}
```

### Integration

```go
// In main.go
if c.burstConfig.Enabled {
    inBurst, _ := c.checkBurst(eventType)
    if inBurst {
        log.Debug("Notification blocked by burst control: %s", eventType)
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State pattern
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Time-window pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Time-based |
| Linux | ✅ Supported | Time-based |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
