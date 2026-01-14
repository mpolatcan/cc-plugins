# Feature: Sound Event Alerts

Alert on event conditions.

## Summary

Generate alerts when specific event conditions are met.

## Motivation

- Notify on anomalies
- Critical event alerts
- Proactive monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Alert Types

| Type | Description | Example |
|------|-------------|---------|
| Threshold | Value exceeds threshold | > 100 events/hour |
| Pattern | Pattern detected | Unusual pattern |
| Failure | Failure rate | > 5% failures |
| Silence | No events for period | No events for 1 hour |

### Configuration

```go
type AlertConfig struct {
    Enabled     bool              `json:"enabled"`
    Alerts      map[string]*Alert `json:"alerts"`
    ThrottleSec int               `json:"throttle_sec"` // min time between same alert
}

type Alert struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Type        string   `json:"type"` // "threshold", "pattern", "failure", "silence"
    Condition   string   `json:"condition"` // e.g., "events > 100 in 1h"
    Threshold   int      `json:"threshold"`
    WindowMin   int      `json:"window_minutes"`
    Action      string   `json:"action"` // "notify", "log", "webhook"
    ActionConfig map[string]string `json:"action_config"`
    Enabled     bool     `json:"enabled"`
    LastTrigger time.Time `json:"last_trigger,omitempty"`
}
```

### Commands

```bash
/ccbell:alert list                  # List alerts
/ccbell:alert create "High Failures" --type failure --threshold 5
/ccbell:alert create "Busy Hour" --type threshold --threshold 100 --window 60
/ccbell:alert create "Silence" --type silence --window 60
/ccbell:alert enable <id>           # Enable alert
/ccbell:alert disable <id>          # Disable alert
/ccbell:alert test <id>             # Test alert
/ccbell:alert history               # Show alert history
/ccbell:alert delete <id>           # Remove alert
```

### Output

```
$ ccbell:alert list

=== Sound Event Alerts ===

Status: Enabled
Alerts: 3

[1] High Failure Rate
    Type: failure
    Condition: failures > 5% in 10min
    Action: notify
    Enabled: Yes
    Last: Never triggered
    [Test] [Edit] [Disable] [Delete]

[2] Busy Hour
    Type: threshold
    Condition: events > 100 in 60min
    Action: log
    Enabled: Yes
    Last: Jan 14, 2:00 PM
    [Test] [Edit] [Disable] [Delete]

[3] Long Silence
    Type: silence
    Condition: no events for 60min
    Action: notify
    Enabled: Yes
    Last: Never triggered
    [Test] [Edit] [Disable] [Delete]

[Create] [History]
```

---

## Audio Player Compatibility

Alerts don't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Alert Evaluation

```go
type AlertManager struct {
    config  *AlertConfig
    metrics *MetricsCollector
}

func (m *AlertManager) CheckAlerts() []AlertEvent {
    events := []AlertEvent{}

    metrics := m.metrics.GetMetrics()

    for _, alert := range m.config.Alerts {
        if !alert.Enabled {
            continue
        }

        if m.shouldTrigger(alert, metrics) {
            event := m.triggerAlert(alert)
            events = append(events, event)
        }
    }

    return events
}

func (m *AlertManager) shouldTrigger(alert *Alert, metrics *Metrics) bool {
    // Check throttle
    if alert.LastTrigger.Add(time.Duration(m.config.ThrottleSec) * time.Second).After(time.Now()) {
        return false
    }

    switch alert.Type {
    case "threshold":
        return m.checkThreshold(alert, metrics)
    case "failure":
        return m.checkFailure(alert, metrics)
    case "silence":
        return m.checkSilence(alert)
    }

    return false
}

func (m *AlertManager) checkThreshold(alert *Alert, metrics *Metrics) bool {
    // Get events in window
    recentEvents := m.getRecentEvents(alert.WindowMin)
    return len(recentEvents) > alert.Threshold
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

- [Metrics feature](features/156-feat-sound-event-metrics.md) - Alert data source
- [Notification feature](features/120-feat-sound-notifications.md) - Alert delivery

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
