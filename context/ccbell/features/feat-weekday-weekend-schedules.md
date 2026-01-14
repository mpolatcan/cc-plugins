# Feature: Weekday/Weekend Schedules 📅

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

Override default quiet hours with weekend-specific schedules.

## Motivation

- Different work patterns on weekends
- Longer quiet hours for weekend rest
- Family time without interruptions
- Flexible schedules for different days

---

## Benefit

- **Work-life balance**: Respects different schedules for weekdays vs. weekends
- **Automated adaptation**: No manual schedule changes needed
- **Family-friendly**: Quieter notifications when family is around
- **Personalized rhythms**: Match notification behavior to personal routines

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Category** | Scheduling |

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

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Extend `QuietHours` with `weekday` and `weekend` TimeWindow |
| **Core Logic** | Modify | Extend `IsInQuietHours()` with weekday/weekend logic |
| **Config Loading** | No change | Uses existing config loading |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add weekday/weekend schedule options |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/config/quiethours.go:**
```go
type TimeWindow struct {
    Start string `json:"start"` // HH:MM format
    End   string `json:"end"`
}

type QuietHoursConfig struct {
    Enabled  *bool                 `json:"enabled,omitempty"`
    Default  *TimeWindow           `json:"default,omitempty"`
    Weekday  *TimeWindow           `json:"weekday,omitempty"`  // Mon-Fri
    Weekend  *TimeWindow           `json:"weekend,omitempty"`  // Sat-Sun
    Timezone *string               `json:"timezone,omitempty"`
}

func (c *CCBell) IsInQuietHours() bool {
    if !c.config.QuietHours.Enabled() {
        return false
    }

    now := time.Now()
    weekday := now.Weekday()
    isWeekend := weekday == time.Saturday || weekday == time.Sunday

    var window *TimeWindow
    if isWeekend && c.config.QuietHours.Weekend != nil {
        window = c.config.QuietHours.Weekend
    } else if !isWeekend && c.config.QuietHours.Weekday != nil {
        window = c.config.QuietHours.Weekday
    } else {
        window = c.config.QuietHours.Default
    }

    if window == nil {
        return false
    }

    return c.isInTimeWindow(now, window.Start, window.End)
}

func (c *CCBell) isInTimeWindow(now time.Time, start, end string) bool {
    startParts := strings.Split(start, ":")
    endParts := strings.Split(end, ":")

    startH := mustParseInt(startParts[0])
    startM := mustParseInt(startParts[1])
    endH := mustParseInt(endParts[0])
    endM := mustParseInt(endParts[1])

    currentMinutes := now.Hour()*60 + now.Minute()
    startMinutes := startH*60 + startM
    endMinutes := endH*60 + endM

    if startMinutes <= endMinutes {
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
    // Overnight (e.g., 22:00 - 07:00)
    return currentMinutes >= startMinutes || currentMinutes < endMinutes
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | Documentation update | Enhance `commands/configure.md` with weekday/weekend schedules |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Extends `quiet_hours` with `weekday` and `weekend` TimeWindow overrides
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/configure.md` (add weekday/weekend schedule options)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Update `commands/configure.md` with weekday/weekend schedule configuration
- [ ] Document time window override behavior
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## References

### Research Sources

- [Go time package](https://pkg.go.dev/time) - For weekday/weekend detection

### ccbell Implementation Research

- [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Base to extend with weekday/weekend schedules
- [Time parsing](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - HH:MM format parsing pattern
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - For quiet hours config

---

[Back to Feature Index](index.md)
