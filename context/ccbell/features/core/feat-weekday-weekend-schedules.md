# Feature: Weekday/Weekend Schedules

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Override default quiet hours with weekend-specific schedules.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Current Quiet Hours Analysis

The current `internal/config/quiethours.go` has:
- `Start` and `End` fields (HH:MM format)
- `IsInQuietHours()` method

**Key Finding**: Weekday/weekend schedules extend the existing quiet hours struct with optional weekday/weekend overrides.

## Configuration

```json
{
  "quiet_hours": {
    "enabled": true,
    "default": {
      "start": "22:00",
      "end": "07:00"
    },
    "weekday": {
      "start": "22:00",
      "end": "07:00"
    },
    "weekend": {
      "start": "23:00",
      "end": "09:00"
    }
  }
}
```

## Implementation

```go
func (c *CCBell) isInQuietHours() bool {
    if !c.config.QuietHours.Enabled {
        return false
    }

    now := time.Now()
    isWeekend := now.Weekday() == time.Saturday || now.Weekday() == time.Sunday

    schedule := c.config.QuietHours.Default
    if isWeekend && c.config.QuietHours.Weekend != nil {
        schedule = c.config.QuietHours.Weekend
    } else if !isWeekend && c.config.QuietHours.Weekday != nil {
        schedule = c.config.QuietHours.Weekday
    }

    return c.isTimeInRange(now, schedule.Start, schedule.End)
}
```

## Commands

```bash
/ccbell:quiet hours --weekday 22:00-07:00
/ccbell:quiet hours --weekend 23:00-09:00
/ccbell:quiet hours status
```

---

## Feasibility Research

### Audio Player Compatibility

Weekday/weekend schedules don't interact with audio playback. They extend the quiet hours logic.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Works with current architecture |
| Linux | ✅ Supported | Works with current architecture |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

## Implementation Notes

### Config Changes

Extend `internal/config/quiethours.go`:

```go
type QuietHours struct {
    Enabled  bool         `json:"enabled"`
    Start    string       `json:"start"` // HH:MM
    End      string       `json:"end"`   // HH:MM
    Weekday  *TimeWindow  `json:"weekday,omitempty"`
    Weekend  *TimeWindow  `json:"weekend,omitempty"`
}

type TimeWindow struct {
    Start string `json:"start"` // HH:MM
    End   string `json:"end"`   // HH:MM
}
```

### Integration

The existing `IsInQuietHours()` method can be extended with a parameter or a new method.

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

- [Go time package](https://pkg.go.dev/time) - For weekday/weekend detection

### ccbell Implementation Research

- [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Base to extend with weekday/weekend schedules
- [Time parsing](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - HH:MM format parsing pattern
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For quiet hours config

---

[Back to Feature Index](../index.md)
