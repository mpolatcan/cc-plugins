# Feature: Event Filtering 🔍

## Summary

Only trigger notifications when specific conditions are met (e.g., "only notify on long responses" or "notify on errors").

## Benefit

- **Reduced distraction**: Only important events trigger notifications
- **Personalized workflow**: Tailor notifications to individual preferences
- **Context-aware behavior**: Different rules for different work types
- **Improved focus**: Less interruption means deeper concentration

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Notification Control |

## Technical Feasibility

### Filter Types

| Filter | Description | Example |
|--------|-------------|---------|
| token_count | Min/max tokens | `{"min": 1000}` |
| pattern | Regex match | `{"regex": "error|failed"}` |
| duration | Min/max seconds | `{"min": 5}` |

### Implementation

```go
type EventFilter struct {
    TokenCount *TokenCountFilter `json:"token_count,omitempty"`
    Pattern    *PatternFilter    `json:"pattern,omitempty"`
    Duration   *DurationFilter   `json:"duration,omitempty"`
}

func (f *EventFilter) ShouldNotify(eventData EventData) bool {
    if f.TokenCount != nil && eventData.TokenCount < f.TokenCount.Min {
        return false
    }
    if f.Pattern != nil {
        matched, _ := regexp.MatchString(f.Pattern.Regex, eventData.Message)
        if !matched { return false }
    }
    return true
}
```

### Commands

No new commands - config-based filtering.

## Configuration

```json
{
  "events": {
    "stop": {
      "filters": {
        "token_count": { "min": 500 },
        "pattern": { "regex": "error|failed", "invert": true }
      }
    }
  }
}
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `filters` section to Event |
| **Core Logic** | Add | `ShouldNotify()` function |
| **New File** | Add | `internal/filter/filter.go` |
| **Main Flow** | Modify | Check filters before playing |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add filter section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Go regexp package](https://pkg.go.dev/regexp)
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [ValidEvents](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51)

---

[Back to Feature Index](index.md)
