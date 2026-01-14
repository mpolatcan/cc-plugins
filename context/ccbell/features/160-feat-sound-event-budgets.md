# Feature: Sound Event Budgets

Manage event budgets over time.

## Summary

Track and manage event budgets for controlled usage.

## Motivation

- Usage budgeting
- Cost management
- Planning

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Budget Types

| Type | Description | Example |
|------|-------------|---------|
| Daily Budget | Events per day | 500 events/day |
| Weekly Budget | Events per week | 3000/week |
| Monthly Budget | Events per month | 10000/month |
| Event Budget | Per-event budget | 200 stop/day |

### Configuration

```go
type BudgetConfig struct {
    Enabled       bool              `json:"enabled"`
    Budgets       map[string]*Budget `json:"budgets"`
    Period        string            `json:"period"` // "day", "week", "month"
    ResetTime     string            `json:"reset_time"` // HH:MM
    Rollover      bool              `json:"rollover"` // unused rolls to next period
    WarningPercent float64          `json:"warning_percent"` // 80% warning
}

type Budget struct {
    ID          string    `json:"id"`
    Name        string    `json:"name"`
    Type        string    `json:"type"` // "daily", "weekly", "monthly", "event"
    MaxValue    int       `json:"max_value"`
    Used        int       `json:"used"`
    Remaining   int       `json:"remaining"`
    EventType   string    `json:"event_type,omitempty"` // for per-event budget
    PeriodStart time.Time `json:"period_start"`
}
```

### Commands

```bash
/ccbell:budget list                 # List budgets
/ccbell:budget set daily 500        # Daily budget 500
/ccbell:budget set weekly 3000      # Weekly budget 3000
/ccbell:budget set monthly 10000    # Monthly budget 10000
/ccbell:budget set event stop 200   # Stop event budget
/ccbell:budget status               # Show budget status
/ccbell:budget reset                # Reset all budgets
/ccbell:budget enable rollover      # Enable rollover
/ccbell:budget disable              # Disable budgets
```

### Output

```
$ ccbell:budget status

=== Sound Event Budgets ===

Status: Enabled
Period: Daily
Rollover: Enabled

Budgets (Jan 15):

Daily: 500 events
  Used: 156 (31%)
  Remaining: 344
  Warning: 80% (400) - Not reached
  Rollover: 0 from yesterday
  [Reset]

Weekly: 3000 events
  Used: 1,234 (41%)
  Remaining: 1,766
  [Reset]

Per-Event:
  stop: 200/500 (40%)
  subagent: 200/500 (40%)
  permission_prompt: 200/500 (40%)
  idle_prompt: 200/500 (40%)

[Configure] [Reset All]
```

---

## Audio Player Compatibility

Budgets don't play sounds:
- Control event flow
- No player changes required

---

## Implementation

### Budget Management

```go
type BudgetManager struct {
    config  *BudgetConfig
    budgets map[string]*Budget
    mutex   sync.Mutex
}

func (m *BudgetManager) Consume(eventType string, count int) (bool, string) {
    if !m.config.Enabled {
        return true, ""
    }

    m.mutex.Lock()
    defer m.mutex.Unlock()

    // Check daily budget
    daily := m.budgets["daily"]
    if daily.Used+count > daily.MaxValue {
        return false, fmt.Sprintf("daily budget exceeded: %d/%d", daily.Used, daily.MaxValue)
    }

    // Check weekly budget
    weekly := m.budgets["weekly"]
    if weekly.Used+count > weekly.MaxValue {
        return false, fmt.Sprintf("weekly budget exceeded: %d/%d", weekly.Used, weekly.MaxValue)
    }

    // Check per-event budget
    eventKey := fmt.Sprintf("event:%s", eventType)
    if eventBudget, ok := m.budgets[eventKey]; ok {
        if eventBudget.Used+count > eventBudget.MaxValue {
            return false, fmt.Sprintf("%s budget exceeded: %d/%d", eventType, eventBudget.Used, eventBudget.MaxValue)
        }
        eventBudget.Used += count
    }

    // Consume budgets
    daily.Used += count
    weekly.Used += count

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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Budget storage
- [Quota feature](features/159-feat-sound-event-quotas.md) - Related to budgets

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
