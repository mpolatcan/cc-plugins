# Feature: Event Filtering

Conditional notifications based on response length, patterns, or conditions.

## Summary

Only trigger notifications when specific conditions are met (e.g., "only notify on long responses" or "notify on errors").

## Technical Feasibility

### Filter Types

| Filter | Description | Example |
|--------|-------------|---------|
| token_count | Min/max tokens | `{"min": 1000}` |
| pattern | Regex match | `{"pattern": "error|failed"}` |
| duration | Min/max seconds | `{"min": 5}` |
| has_tool_calls | Tool usage detected | `{"enabled": true}` |

### Implementation

```go
type EventFilter struct {
    TokenCount   *TokenCountFilter   `json:"token_count,omitempty"`
    Pattern      *PatternFilter      `json:"pattern,omitempty"`
    Duration     *DurationFilter     `json:"duration,omitempty"`
    HasToolCalls *bool               `json:"has_tool_calls,omitempty"`
}

func (f *EventFilter) ShouldNotify(eventData EventData) bool {
    if f.TokenCount != nil {
        if eventData.TokenCount < f.TokenCount.Min {
            return false
        }
    }
    if f.Pattern != nil {
        matched, _ := regexp.MatchString(f.Pattern.Regex, eventData.Message)
        if !matched != f.Pattern.Invert { // XOR for invert
            return false
        }
    }
    return true
}
```

## Configuration

```json
{
  "events": {
    "stop": {
      "filters": {
        "token_count": { "min": 500 },
        "pattern": { "regex": "error|failed|exception", "invert": true }
      }
    },
    "permission_prompt": {
      "filters": {
        "pattern": { "regex": "dangerous|delete|rm", "invert": false }
      }
    }
  }
}
```
