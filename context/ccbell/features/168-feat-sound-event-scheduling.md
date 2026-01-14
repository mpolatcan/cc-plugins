# Feature: Sound Event Scheduling

Schedule sounds for specific times or events.

## Summary

Schedule sound notifications to play at specific times or when specific conditions are met.

## Motivation

- Time-based notifications
- Meeting reminders
- Task reminders

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Schedule Types

| Type | Description | Example |
|------|-------------|---------|
| Time-based | Specific time each day | 9:00 AM daily |
| Interval | Every N minutes/hours | Every 30 minutes |
| Event-based | After other events | 5 min after stop |
| Calendar | Sync with calendar | Meeting start |

### Configuration

```go
type ScheduleConfig struct {
    Enabled     bool              `json:"enabled"`
    Schedules   map[string]*Schedule `json:"schedules"`
    Timezone    string            `json:"timezone"` // Local or UTC
}

type Schedule struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Type        string   `json:"type"` // "time", "interval", "event", "calendar"
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume"`
    Enabled     bool     `json:"enabled"`
    // Time-based
    Time        string   `json:"time,omitempty"` // HH:MM
    Days        []string `json:"days,omitempty"` // ["mon", "tue", ...]
    // Interval
    IntervalMin int      `json:"interval_minutes,omitempty"`
    // Event-based
    TriggerEvent string  `json:"trigger_event,omitempty"`
    DelayMin     int     `json:"delay_minutes,omitempty"`
    MaxTriggers  int     `json:"max_triggers,omitempty"` // Per day
}
```

### Commands

```bash
/ccbell:schedule list               # List schedules
/ccbell:schedule create "Morning" --time 09:00 --sound bundled:stop --days mon,tue,wed,thu,fri
/ccbell:schedule create "Break" --interval 30 --sound bundled:stop
/ccbell:schedule create "Reminder" --event stop --delay 5
/ccbell:schedule enable <id>        # Enable schedule
/ccbell:schedule disable <id>       # Disable schedule
/ccbell:schedule delete <id>        # Remove schedule
/ccbell:schedule test <id>          # Test schedule
```

### Output

```
$ ccbell:schedule list

=== Sound Event Schedules ===

Status: Enabled
Timezone: Local

Schedules: 3

[1] Morning
    Type: Time-based
    Time: 09:00 AM
    Days: Mon, Tue, Wed, Thu, Fri
    Sound: bundled:stop
    Status: Active
    Next: Jan 16, 09:00 AM
    [Edit] [Disable] [Delete]

[2] Break Reminder
    Type: Interval
    Interval: 30 minutes
    Sound: bundled:stop
    Status: Active
    Next: 30 min
    Triggers today: 2/8
    [Edit] [Disable] [Delete]

[3] Post-Work
    Type: Event-based
    Trigger: stop
    Delay: 5 min
    Sound: bundled:stop
    Status: Active
    [Edit] [Disable] [Delete]

[Configure] [Create] [Test All]
```

---

## Audio Player Compatibility

Scheduling doesn't play sounds:
- Background scheduler
- No player changes required

---

## Implementation

### Schedule Runner

```go
type ScheduleManager struct {
    config   *ScheduleConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
}

func (m *ScheduleManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})

    go m.runScheduler()
}

func (m *ScheduleManager) runScheduler() {
    ticker := time.NewTicker(1 * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSchedules()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ScheduleManager) checkSchedules() {
    now := time.Now()

    for _, sched := range m.config.Schedules {
        if !sched.Enabled {
            continue
        }

        switch sched.Type {
        case "time":
            m.checkTimeSchedule(sched, now)
        case "interval":
            m.checkIntervalSchedule(sched)
        case "event":
            m.checkEventSchedule(sched)
        }
    }
}

func (m *ScheduleManager) checkTimeSchedule(sched *Schedule, now time.Time) {
    currentTime := now.Format("15:04")
    if currentTime != sched.Time {
        return
    }

    // Check day of week
    today := now.Weekday().String()[:3]
    if !contains(sched.Days, today) {
        return
    }

    m.playScheduledSound(sched)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go time package |

---

## References

### ccbell Implementation Research

- [Quiet hours](https://github.com/mpolatcan/ccbell/blob/main/internal/config/quiethours.go) - Time-based logic
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Trigger tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go scheduler |
| Linux | ✅ Supported | Pure Go scheduler |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
