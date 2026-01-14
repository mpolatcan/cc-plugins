# Feature: Event Filtering 🔍

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Only trigger notifications when specific conditions are met (e.g., "only notify on long responses" or "notify on errors").

## Motivation

- Reduce notification fatigue from irrelevant events
- Focus on what matters most to the developer
- Support different notification strategies per workflow
- Filter out noise during focused work

---

## Benefit

- **Reduced distraction**: Only important events trigger notifications
- **Personalized workflow**: Tailor notifications to individual preferences
- **Context-aware behavior**: Different rules for different types of work
- **Improved focus**: Less interruption means deeper concentration on complex tasks

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Notification Control |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Add `filters` section to Event config |
| **Core Logic** | Add | Add `ShouldNotify(eventData) bool` function |
| **New File** | Add | `internal/filter/filter.go` with filter evaluation |
| **Main Flow** | Modify | Check filters before playing sound |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add filter configuration section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/filter/filter.go:**
```go
type FilterConfig struct {
    TokenCount    *TokenCountFilter    `json:"token_count,omitempty"`
    Pattern       *PatternFilter       `json:"pattern,omitempty"`
    Duration      *DurationFilter      `json:"duration,omitempty"`
    HasToolCalls  *bool                `json:"has_tool_calls,omitempty"`
}

type TokenCountFilter struct {
    Min *int `json:"min,omitempty"`
    Max *int `json:"max,omitempty"`
}

type PatternFilter struct {
    Include *string `json:"include,omitempty"` // Regex to match
    Exclude *string `json:"exclude,omitempty"` // Regex to exclude
}

type DurationFilter struct {
    MinSeconds *float64 `json:"min_seconds,omitempty"`
    MaxSeconds *float64 `json:"max_seconds,omitempty"`
}

func (f *FilterConfig) Evaluate(eventData map[string]interface{}) bool {
    if f == nil { return true }

    if f.TokenCount != nil && !f.evalTokenCount(eventData) { return false }
    if f.Pattern != nil && !f.evalPattern(eventData) { return false }
    if f.Duration != nil && !f.evalDuration(eventData) { return false }
    if f.HasToolCalls != nil && !f.evalToolCalls(eventData) { return false }

    return true
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cfg := config.Load(homeDir)
    eventType := os.Args[1]

    // Get event data from Claude Code environment
    eventData := parseEventData()

    // Check filters
    eventCfg := cfg.GetEventConfig(eventType)
    if eventCfg.Filters != nil {
        if !eventCfg.Filters.Evaluate(eventData) {
            log.Info("Event filtered out: %s", eventType)
            return
        }
    }
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with filter configuration |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `filters` to event config (token_count, pattern, duration, has_tool_calls)
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add filter configuration section)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Update `commands/configure.md` with filter configuration examples
- [ ] Document filter types and their usage
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## References

### Research Sources

- [Go regexp package](https://pkg.go.dev/regexp)
- [Go time package](https://pkg.go.dev/time) - For duration parsing

### ccbell Implementation Research

- [Current main.go flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point for event filtering
- [Event validation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go#L45-L51) - `ValidEvents` map pattern

---

[Back to Feature Index](index.md)
