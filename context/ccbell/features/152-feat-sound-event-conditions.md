# Feature: Sound Event Conditions

Conditional event handling.

## Summary

Define conditions that affect event processing.

## Motivation

- Conditional logic
- Dynamic handling
- Context-aware behavior

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Condition Types

| Type | Description | Example |
|------|-------------|---------|
| Time | Time-based | 09:00-17:00 |
| Day | Day of week | Mon-Fri |
| Volume | Volume threshold | volume > 0.5 |
| EventCount | Recent count | > 3 in 1min |

### Configuration

```go
type ConditionConfig struct {
    Enabled     bool        `json:"enabled"`
    Conditions  []Condition `json:"conditions"`
}

type Condition struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Type        string   `json:"type"` // "time", "day", "volume", "count"
    Operator    string   `json:"operator"` // "eq", "gt", "lt", "between", "in"
    Value       string   `json:"value"`
    Secondary   string   `json:"secondary,omitempty"` // for "between"
    Action      string   `json:"action"` // "allow", "block", "modify"
    Modifier    map[string]string `json:"modifier,omitempty"` // for modify
    Enabled     bool     `json:"enabled"`
}
```

### Commands

```bash
/ccbell:condition list              # List conditions
/ccbell:condition add "Work Hours" --type time --value "09:00-17:00"
/ccbell:condition add "Weekday" --type day --value "1-5"
/ccbell:condition add "High Volume" --type volume --value ">0.7"
/ccbell:condition add "Burst" --type count --value ">5/min"
/ccbell:condition enable <id>       # Enable condition
/ccbell:condition disable <id>      # Disable condition
/ccbell:condition test stop volume=0.8 # Test condition
/ccbell:condition delete <id>       # Remove condition
```

### Output

```
$ ccbell:condition list

=== Sound Event Conditions ===

Status: Enabled
Conditions: 4

[1] Work Hours
    Type: time
    Value: 09:00-17:00
    Action: allow (default)
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[2] Weekday
    Type: day
    Value: 1-5 (Mon-Fri)
    Action: allow (default)
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[3] High Volume
    Type: volume
    Value: > 0.7
    Action: modify (volume=0.5)
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[4] Burst Prevention
    Type: count
    Value: > 5/min
    Action: block
    Enabled: Yes
    [Test] [Edit] [Disable] [Delete]

[Add] [Import] [Export]
```

---

## Audio Player Compatibility

Conditions work with existing audio player:
- Modifies event handling
- Same format support
- No player changes required

---

## Implementation

### Condition Evaluation

```go
type ConditionManager struct {
    config  *ConditionConfig
}

func (m *ConditionManager) Evaluate(eventType string, volume float64) (*ConditionResult, error) {
    result := &ConditionResult{
        Action: "allow",
        Modifiers: make(map[string]string),
    }

    now := time.Now()

    for _, cond := range m.config.Conditions {
        if !cond.Enabled {
            continue
        }

        matches := false

        switch cond.Type {
        case "time":
            matches = m.matchesTime(cond, now)
        case "day":
            matches = m.matchesDay(cond, now)
        case "volume":
            matches = m.matchesVolume(cond, volume)
        case "count":
            matches = m.matchesCount(cond, eventType)
        }

        if matches {
            result.Action = cond.Action
            for k, v := range cond.Modifier {
                result.Modifiers[k] = v
            }
        }
    }

    return result, nil
}

func (m *ConditionManager) matchesTime(cond Condition, now time.Time) bool {
    start, _ := parseTime(cond.Value)
    end, _ := parseTime(cond.Secondary)

    current := float64(now.Hour()) + float64(now.Minute())/60.0
    startVal := float64(start.Hour()) + float64(start.Minute())/60.0
    endVal := float64(end.Hour()) + float64(end.Minute())/60.0

    return current >= startVal && current < endVal
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

- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Condition config
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event evaluation

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
