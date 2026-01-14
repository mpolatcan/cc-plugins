# Feature: Sound Event Scheduling

Schedule events to play at specific times.

## Summary

Schedule sounds to play at specific times or intervals.

## Motivation

- Time-based notifications
- Scheduled alerts
- Automated sounds

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Schedule Types

| Type | Description | Example |
|------|-------------|---------|
| Time | At specific time | 09:00 |
| Interval | Every N minutes | every 30min |
| Cron | Cron expression | 0 9 * * 1-5 |
| Relative | After event | 5min after stop |

### Configuration

```go
type ScheduleConfig struct {
    Enabled     bool              `json:"enabled"`
    Schedules   map[string]*Schedule `json:"schedules"`
    Timezone    string            `json:"timezone"` // "local", "UTC"
}

type Schedule struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    EventType   string   `json:"event_type"`
    Sound       string   `json:"sound"`
    Volume      float64  `json:"volume"`
    Schedule    string   `json:"schedule"` // "09:00", "*/30", "0 9 * * 1-5"
    ScheduleType string  `json:"schedule_type"` // "time", "interval", "cron"
    DaysOfWeek  []int    `json:"days_of_week"` // 0-6
    Enabled     bool     `json:"enabled"`
    LastRun     time.Time `json:"last_run,omitempty"`
    NextRun     time.Time `json:"next_run,omitempty"`
}
```

### Commands

```bash
/ccbell:schedule add "Morning" --time 09:00 --sound bundled:stop
/ccbell:schedule add "Break" --interval 30 --sound bundled:idle_prompt
/ccbell:schedule add "Focus" --cron "0 */30 * * 1-5" --sound bundled:subagent
/ccbell:schedule list                # List schedules
/ccbell:schedule enable <id>         # Enable schedule
/ccbell:schedule disable <id>        # Disable schedule
/ccbell:schedule delete <id>         # Remove schedule
/ccbell:schedule run <id>            # Run now
/ccbell:schedule status              # Show status
```

### Output

```
$ ccbell:schedule list

=== Sound Schedules ===

Status: Enabled
Timezone: Local

[1] Morning Bell
    Event: (manual trigger)
    Time: 09:00
    Days: Mon-Fri
    Enabled: Yes
    Next: Jan 16, 09:00 AM

[2] Break Reminder
    Event: (manual trigger)
    Interval: 30 minutes
    Enabled: Yes
    Next: 14 min

[3] Focus Timer
    Event: (manual trigger)
    Cron: 0 */30 * * 1-5
    Enabled: Yes
    Next: 14:30

[Add] [Edit] [Delete] [Run Now]
```

---

## Audio Player Compatibility

Scheduling uses existing audio player:
- Triggers `player.Play()` at scheduled times
- Same format support
- No player changes required

---

## Implementation

### Schedule Execution

```go
type Scheduler struct {
    config  *ScheduleConfig
    ticker  *time.Ticker
    running bool
}

func (s *Scheduler) Run() {
    s.running = true

    // Check every minute
    s.ticker = time.NewTicker(1 * time.Minute)

    for range s.ticker.C {
        s.checkSchedules()
    }
}

func (s *Scheduler) checkSchedules() {
    now := time.Now()

    for _, schedule := range s.config.Schedules {
        if !schedule.Enabled {
            continue
        }

        if s.shouldRun(schedule, now) {
            s.runSchedule(schedule)
        }
    }
}

func (s *Scheduler) shouldRun(schedule *Schedule, now time.Time) bool {
    switch schedule.ScheduleType {
    case "time":
        return schedule.Schedule == now.Format("15:04") &&
            s.isDayMatch(schedule, now)
    case "interval":
        return s.intervalElapsed(schedule, now)
    case "cron":
        return s.cronMatch(schedule.Schedule, now)
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go (cron parsing) |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Scheduled playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Schedule state

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
