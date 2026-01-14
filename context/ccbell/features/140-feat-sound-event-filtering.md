# Feature: Sound Event Filtering

Filter events before playback.

## Summary

Filter events based on configurable rules.

## Motivation

- Selective notifications
- Remove unwanted events
- Custom event handling

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Filter Types

| Type | Description | Example |
|------|-------------|---------|
| Allow | Only allow specific | allow stop |
| Block | Block specific | block idle_prompt |
| Regex | Pattern matching | block custom:.*test.* |
| Time | Time-based filter | block 22:00-07:00 |

### Configuration

```go
type FilterConfig struct {
    Enabled       bool          `json:"enabled"`
    DefaultAction string        `json:"default_action"` // "allow", "block"
    Rules         []FilterRule  `json:"rules"`
}

type FilterRule struct {
    ID          string   `json:"id"`
    EventType   string   `json:"event_type"`   // event type or regex
    SoundPattern string  `json:"sound_pattern"` // sound regex
    Action      string   `json:"action"`       // "allow", "block"
    TimeRange   *TimeRange `json:"time_range"` // optional time filter
    Enabled     bool     `json:"enabled"`
}

type TimeRange struct {
    Start string `json:"start"` // HH:MM
    End   string `json:"end"`   // HH:MM
    Days  []int  `json:"days"`  // 0-6, empty = all days
}
```

### Commands

```bash
/ccbell:filter enable               # Enable filtering
/ccbell:filter disable              # Disable filtering
/ccbell:filter add allow stop       # Allow stop events
/ccbell:filter add block idle_prompt # Block idle_prompt
/ccbell:filter add block "22:00-07:00" # Block during night
/ccbell:filter list                 # List filters
/ccbell:filter remove <id>          # Remove filter
/ccbell:filter test stop            # Test event against filters
/ccbell:filter clear                # Clear all filters
```

### Output

```
$ ccbell:filter list

=== Sound Event Filters ===

Status: Enabled
Default: Allow All

Rules:
  [1] Allow: stop
      Status: Enabled
      [Test] [Remove]

  [2] Block: idle_prompt
      Status: Enabled
      [Test] [Remove]

  [3] Block: 10:00 PM - 7:00 AM
      Status: Enabled
      Days: All
      [Test] [Remove]

Test: stop
  Result: ALLOWED (matched rule 1)
  Reason: Explicit allow rule
```

---

## Audio Player Compatibility

Filtering doesn't play sounds:
- Controls which events play
- No player changes required

---

## Implementation

### Filter Evaluation

```go
type EventFilter struct {
    config  *FilterConfig
}

func (f *EventFilter) ShouldAllow(eventType, soundID string) (bool, string) {
    // If no rules, allow all
    if len(f.config.Rules) == 0 {
        return true, "no filters configured"
    }

    // Check each rule
    for _, rule := range f.config.Rules {
        if !rule.Enabled {
            continue
        }

        if f.matchesRule(eventType, soundID, rule) {
            if rule.Action == "allow" {
                return true, fmt.Sprintf("matched allow rule: %s", rule.ID)
            } else {
                return false, fmt.Sprintf("matched block rule: %s", rule.ID)
            }
        }
    }

    // Default action
    if f.config.DefaultAction == "allow" {
        return true, "default allow"
    }
    return false, "default block"
}

func (f *EventFilter) matchesRule(eventType, soundID string, rule FilterRule) bool {
    // Check event type match
    if rule.EventType != "" {
        if !matchPattern(eventType, rule.EventType) {
            return false
        }
    }

    // Check sound pattern match
    if rule.SoundPattern != "" {
        if !matchPattern(soundID, rule.SoundPattern) {
            return false
        }
    }

    // Check time range
    if rule.TimeRange != nil {
        if !f.isWithinTimeRange(rule.TimeRange) {
            return false
        }
    }

    return true
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event filtering point
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Filter configuration

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
