# Feature: Sound Event Limits

Enforce hard limits on events.

## Summary

Set hard limits that cannot be exceeded.

## Motivation

- Hard boundaries
- Safety limits
- Prevent abuse

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Limit Types

| Type | Description | Example |
|------|-------------|---------|
| Hard Max | Absolute maximum | Max 1000 events |
| Immediate Block | Block immediately | Fail fast |
| Graceful Degrade | Degrade gracefully | Reduce quality |
| Notify Only | Notify but allow | Warning only |

### Configuration

```go
type LimitConfig struct {
    Enabled       bool              `json:"enabled"`
    Limits        map[string]*Limit `json:"limits"`
    FailBehavior  string            `json:"fail_behavior"` // "block", "queue", "degrade"
}

type Limit struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Type        string `json:"type"` // "count", "rate", "concurrent"
    MaxValue    int    `json:"max_value"`
    PerEvent    string `json:"per_event,omitempty"`
    Immediate   bool   `json:"immediate"` // fail immediately
    Notify      bool   `json:"notify"` // send notification
}
```

### Commands

```bash
/ccbell:limit list                  # List limits
/ccbell:limit set max 1000          # Hard max 1000
/ccbell:limit set rate 100          # Max 100/min
/ccbell:limit set concurrent 10     # Max 10 concurrent
/ccbell:limit set immediate         # Fail immediately
/ccbell:limit enable                # Enable limits
/ccbell:limit disable               # Disable limits
/ccbell:limit status                # Show limit status
/ccbell:limit test                  # Test limits
```

### Output

```
$ ccbell:limit status

=== Sound Event Limits ===

Status: Enabled
Fail Behavior: block

Limits:
  [1] Max Events
      Type: count
      Max: 1000
      Current: 156
      Status: OK
      Immediate: Yes
      [Edit] [Remove]

  [2] Max Rate
      Type: rate
      Max: 100/min
      Current: 45/min
      Status: OK
      Immediate: No
      [Edit] [Remove]

  [3] Max Concurrent
      Type: concurrent
      Max: 10
      Current: 1
      Status: OK
      Immediate: Yes
      [Edit] [Remove]

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Limits don't play sounds:
- Control event flow
- No player changes required

---

## Implementation

### Limit Checking

```go
type LimitManager struct {
    config  *LimitConfig
    limits  map[string]*Limit
    mutex   sync.Mutex
}

func (m *LimitManager) Check(eventType string) (bool, string) {
    if !m.config.Enabled {
        return true, ""
    }

    m.mutex.Lock()
    defer m.mutex.Unlock()

    for _, limit := range m.limits {
        if !m.appliesTo(limit, eventType) {
            continue
        }

        exceeded := false

        switch limit.Type {
        case "count":
            current := m.getCurrentCount(limit)
            if current >= limit.MaxValue {
                exceeded = true
            }
        case "rate":
            current := m.getCurrentRate(limit)
            if current >= limit.MaxValue {
                exceeded = true
            }
        case "concurrent":
            current := m.getConcurrentCount()
            if current >= limit.MaxValue {
                exceeded = true
            }
        }

        if exceeded {
            if limit.Notify {
                m.sendNotification(limit)
            }

            if limit.Immediate || m.config.FailBehavior == "block" {
                return false, fmt.Sprintf("limit exceeded: %s (%d/%d)", limit.Name, m.getCurrentValue(limit), limit.MaxValue)
            }
        }
    }

    return true, ""
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Limit checking point
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Limit tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
