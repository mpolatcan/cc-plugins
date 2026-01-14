# Feature: Weekday/Weekend Schedules 📅

## Summary

Override default quiet hours with weekend-specific schedules.

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

## Technical Feasibility

### Configuration

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

### Implementation

```go
type TimeWindow struct {
    Start string `json:"start"`
    End   string `json:"end"`
}

type QuietHoursConfig struct {
    Enabled  *bool        `json:"enabled,omitempty"`
    Default  *TimeWindow  `json:"default,omitempty"`
    Weekday  *TimeWindow  `json:"weekday,omitempty"`
    Weekend  *TimeWindow  `json:"weekend,omitempty"`
    Timezone *string      `json:"timezone,omitempty"`
}

func IsInQuietHours(cfg *QuietHoursConfig) bool {
    if !cfg.Enabled() {
        return false
    }

    now := time.Now()
    isWeekend := now.Weekday() == time.Saturday || now.Weekday() == time.Sunday

    var window *TimeWindow
    if isWeekend && cfg.Weekend != nil {
        window = cfg.Weekend
    } else if !isWeekend && cfg.Weekday != nil {
        window = cfg.Weekday
    } else {
        window = cfg.Default
    }

    if window == nil {
        return false
    }

    return isInTimeWindow(now, window.Start, window.End)
}

func isInTimeWindow(now time.Time, start, end string) bool {
    startParts := strings.Split(start, ":")
    endParts := strings.Split(end, ":")
    startH, _ := strconv.Atoi(startParts[0])
    startM, _ := strconv.Atoi(startParts[1])
    endH, _ := strconv.Atoi(endParts[0])
    endM, _ := strconv.Atoi(endParts[1])

    currentMinutes := now.Hour()*60 + now.Minute()
    startMinutes := startH*60 + startM
    endMinutes := endH*60 + endM

    if startMinutes <= endMinutes {
        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
    return currentMinutes >= startMinutes || currentMinutes < endMinutes
}
```

### Commands

```bash
/ccbell:quiet hours --weekday 22:00-07:00
/ccbell:quiet hours --weekend 23:00-09:00
/ccbell:quiet hours status
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Modify | Extend `QuietHours` with `weekday` and `weekend` TimeWindow |
| **Core Logic** | Modify | Extend `IsInQuietHours()` with weekday/weekend logic |
| **Config Loading** | No change | Uses existing config loading |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/configure.md** | Update | Add weekday/weekend schedule options |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Go time package](https://pkg.go.dev/time)
- [Current quiet hours implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go)
- [Time parsing](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go)

---

[Back to Feature Index](index.md)
