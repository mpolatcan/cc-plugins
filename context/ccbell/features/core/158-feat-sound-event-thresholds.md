# Feature: Sound Event Thresholds

Define thresholds for event handling.

## Summary

Set configurable thresholds that affect event behavior.

## Motivation

- Prevent overload
- Enforce limits
- Control resources

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Threshold Types

| Type | Description | Default |
|------|-------------|---------|
| Max Events/Min | Maximum events per minute | 100 |
| Max Volume | Maximum volume level | 1.0 |
| Min Cooldown | Minimum cooldown | 0s |
| Max Queue | Maximum queue size | 100 |

### Configuration

```go
type ThresholdConfig struct {
    Enabled        bool              `json:"enabled"`
    Thresholds     map[string]Threshold `json:"thresholds"`
    ActionOnExceed string            `json:"action_on_exceed"` // "block", "queue", "log"
}

type Threshold struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Type        string `json:"type"` // "rate", "volume", "cooldown", "queue"
    MaxValue    float64 `json:"max_value"`
    MinValue    float64 `json:"min_value,omitempty"`
    PerEvent    map[string]float64 `json:"per_event"` // per-event overrides
    Action      string `json:"action"` // "block", "queue", "log", "reduce"
    Reduction   float64 `json:"reduction,omitempty"` // for reduce action
}
```

### Commands

```bash
/ccbell:threshold list              # List thresholds
/ccbell:threshold set max-events 100
/ccbell:threshold set max-volume 0.8
/ccbell:threshold set min-cooldown 2
/ccbell:threshold set per-event stop 50
/ccbell:threshold enable            # Enable thresholds
/ccbell:threshold disable           # Disable thresholds
/ccbell:threshold status            # Show threshold status
/ccbell:threshold test              # Test thresholds
```

### Output

```
$ ccbell:threshold list

=== Sound Event Thresholds ===

Status: Enabled
Action on exceed: queue

Thresholds:
  [1] Max Events/Minute
      Type: rate
      Max: 100/min
      Action: queue
      Current: 45/min
      Status: OK

  [2] Max Volume
      Type: volume
      Max: 0.8 (80%)
      Action: reduce
      Reduction: 0.2
      Status: OK

  [3] Min Cooldown
      Type: cooldown
      Min: 2s
      Action: block
      Status: OK

  [4] Per-Event: stop
      Max Events/Minute: 50
      Current: 15/min
      Status: OK

[Configure] [Test] [Disable]
```

---

## Audio Player Compatibility

Thresholds don't play sounds:
- Control event flow
- No player changes required

---

## Implementation

### Threshold Checking

```go
type ThresholdManager struct {
    config  *ThresholdConfig
}

func (m *ThresholdManager) Check(eventType string, value float64) (*ThresholdResult, bool) {
    result := &ThresholdResult{
        Allowed: true,
        AppliedValue: value,
    }

    for _, threshold := range m.config.Thresholds {
        if !m.appliesTo(threshold, eventType) {
            continue
        }

        switch threshold.Type {
        case "rate":
            if exceeded := m.checkRateThreshold(threshold, eventType); exceeded {
                result = m.applyAction(threshold, result)
            }
        case "volume":
            if value > threshold.MaxValue {
                result = m.applyAction(threshold, result)
            }
        case "cooldown":
            if value < threshold.MinValue {
                result.Allowed = false
                result.Reason = fmt.Sprintf("cooldown %.1f below minimum %.1f", value, threshold.MinValue)
            }
        }
    }

    return result, result.Allowed
}

func (m *ThresholdManager) applyAction(threshold Threshold, result *ThresholdResult) *ThresholdResult {
    switch threshold.Action {
    case "block":
        result.Allowed = false
        result.Reason = fmt.Sprintf("exceeded %s threshold", threshold.Name)
    case "reduce":
        result.AppliedValue = threshold.Reduction
    case "queue":
        result.ShouldQueue = true
    case "log":
        // Just log, allow through
    }
    return result
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Threshold config
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Threshold checking point

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
