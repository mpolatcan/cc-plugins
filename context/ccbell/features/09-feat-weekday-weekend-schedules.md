# Feature: Weekday/Weekend Schedules

Different quiet hours for weekdays vs weekends.

## Summary

Override default quiet hours with weekend-specific schedules.

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
