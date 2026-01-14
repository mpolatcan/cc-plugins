# Feature: Notification Throttling 🚦

## Summary

Prevent notification spam by limiting the total number of notifications within a configurable time window.

## Benefit

- **Reduced notification fatigue**: Fewer but meaningful notifications
- **Better focus during busy work**: Automatic quiet periods
- **Prevents sound fatigue**: Users don't tire of repeated sounds
- **Intelligent filtering**: System learns when to be quiet

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Notification Control |

## Technical Feasibility

### Configuration

```json
{
  "throttling": {
    "enabled": true,
    "max_count": 5,
    "window_minutes": 1,
    "action": "silence"
  }
}
```

### Implementation

```go
type ThrottleManager struct {
    events       []time.Time
    maxPerMinute int
    burstLimit   int
    mutex        sync.Mutex
}

func (t *ThrottleManager) Allow() bool {
    t.mutex.Lock()
    defer t.mutex.Unlock()

    now := time.Now()
    oneMinuteAgo := now.Add(-1 * time.Minute)

    recent := 0
    for _, eventTime := range t.events {
        if eventTime.After(oneMinuteAgo) {
            recent++
        }
    }

    if recent >= t.burstLimit || recent >= t.maxPerMinute {
        return false
    }

    t.events = append(t.events, now)
    return true
}
```

### Commands

```bash
/ccbell:throttle status      # Show current status
/ccbell:throttle reset       # Reset all throttle windows
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `throttling` section |
| **Core Logic** | Add | `ThrottleManager` with Allow() |
| **New File** | Add | `internal/throttle/throttle.go` |
| **Main Flow** | Modify | Check throttling before playing |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add throttle section |
| **commands/status.md** | Update | Add throttle status |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)

---

[Back to Feature Index](index.md)
