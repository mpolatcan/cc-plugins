# Feature: Sound Event Quotas

Enforce usage quotas.

## Summary

Set usage quotas for sound events.

## Motivation

- Limit usage
- Resource management
- Cost control

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Quota Types

| Type | Description | Default |
|------|-------------|---------|
| Daily | Max events per day | 1000 |
| Hourly | Max events per hour | 100 |
| Per Event | Max per event type | 500 |
| Volume | Max total volume | N/A |

### Configuration

```go
type QuotaConfig struct {
    Enabled       bool            `json:"enabled"`
    Quotas        map[string]*Quota `json:"quotas"`
    Period        string          `json:"period"` // "hour", "day", "week"
    ActionOnExceed string         `json:"action_on_exceed"` // "block", "queue", "notify"
    ResetTime    string           `json:"reset_time"` // HH:MM for daily reset
}

type Quota struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Type        string `json:"type"` // "daily", "hourly", "per_event"
    MaxValue    int    `json:"max_value"`
    PerEvent    string `json:"per_event,omitempty"` // for per-event quota
    Used        int    `json:"used"`
    ResetAt     time.Time `json:"reset_at"`
}
```

### Commands

```bash
/ccbell:quota list                  # List quotas
/ccbell:quota set daily 1000        # Daily max 1000
/ccbell:quota set hourly 100        # Hourly max 100
/ccbell:quota set per-event stop 500
/ccbell:quota status                # Show quota status
/ccbell:quota reset                 # Reset all quotas
/ccbell:quota reset stop            # Reset stop quota
/ccbell:quota enable                # Enable quotas
/ccbell:quota disable               # Disable quotas
```

### Output

```
$ ccbell:quota status

=== Sound Event Quotas ===

Status: Enabled
Period: Daily
Reset at: 00:00

Quota Usage (Jan 15):
  Daily: 456 / 1000 (45%)
  Hourly: 23 / 100 (23%)
  Per-Event:
    stop: 156 / 500 (31%)
    subagent: 134 / 500 (27%)
    permission_prompt: 98 / 500 (20%)
    idle_prompt: 68 / 500 (14%)

Reset in: 13h 45m

[Configure] [Reset All] [Disable]
```

---

## Audio Player Compatibility

Quotas don't play sounds:
- Control event flow
- No player changes required

---

## Implementation

### Quota Checking

```go
type QuotaManager struct {
    config  *QuotaConfig
    quotas  map[string]*Quota
    mutex   sync.Mutex
}

func (m *QuotaManager) Check(eventType string) (bool, string) {
    if !m.config.Enabled {
        return true, ""
    }

    m.mutex.Lock()
    defer m.mutex.Unlock()

    // Check daily quota
    if quota, ok := m.quotas["daily"]; ok {
        if quota.Used >= quota.MaxValue {
            return m.handleExceed("daily", quota)
        }
    }

    // Check hourly quota
    if quota, ok := m.quotas["hourly"]; ok {
        if quota.Used >= quota.MaxValue {
            return m.handleExceed("hourly", quota)
        }
    }

    // Check per-event quota
    eventQuotaKey := fmt.Sprintf("per_event:%s", eventType)
    if quota, ok := m.quotas[eventQuotaKey]; ok {
        if quota.Used >= quota.MaxValue {
            return m.handleExceed(eventType, quota)
        }
    }

    return true, ""
}

func (m *QuotaManager) Increment(eventType string) {
    m.mutex.Lock()
    defer m.mutex.Unlock()

    // Increment all applicable quotas
    m.quotas["daily"].Used++
    m.quotas["hourly"].Used++

    eventQuotaKey := fmt.Sprintf("per_event:%s", eventType)
    if quota, ok := m.quotas[eventQuotaKey]; ok {
        quota.Used++
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Quota storage
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Quota checking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
