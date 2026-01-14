# Feature: Event Filtering

Conditional notifications based on response length, patterns, or conditions.

## Summary

Only trigger notifications when specific conditions are met (e.g., "only notify on long responses" or "notify on errors").

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Current Architecture Analysis

The current `cmd/ccbell/main.go` checks:
- `cfg.Enabled` (global enable)
- `eventCfg.Enabled` (per-event enable)
- `cfg.IsInQuietHours()`
- `stateManager.CheckCooldown()`

**Key Finding**: Event filtering can be added as another check before playing sound.

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

---

## Feasibility Research

### Audio Player Compatibility

Event filtering doesn't interact with audio playback. It affects the decision to play sound.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `regexp` | Standard library | Free | Regex support |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Standard Go |
| Linux | ✅ Supported | Standard Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Integration Point

In `cmd/ccbell/main.go`, after event config check:

```go
// Check event filters
if eventCfg.Filters != nil {
    eventData := EventData{
        TokenCount: 0, // Would need hook to get this
        Message:    "",
    }
    if !eventCfg.Filters.ShouldNotify(eventData) {
        log.Debug("Event filtered by rules, skipping")
        return nil
    }
}
```

### Note on Token Count

Claude Code hooks don't currently provide token count in the hook context. This would require:
1. Claude Code to pass token data via environment variable or stdin
2. Or use Claude Code Extensions when available

---


---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### Research Sources

- [Go regexp package](https://pkg.go.dev/regexp)
- [Go time package](https://pkg.go.dev/time) - For duration parsing

### ccbell Implementation Research

- [Current main.go flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point for event filtering
- [Event validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - `ValidEvents` map pattern
