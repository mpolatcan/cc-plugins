# Feature: Sound Scheduling

Schedule sound playback for specific times.

## Summary

Schedule sounds to play at specific times or intervals for automation.

## Motivation

- Pomodoro timer sounds
- Break reminders
- Scheduled notifications
- Workflow automation

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
| Time-based | Play at specific time | "09:00", "14:30" |
| Interval | Play every N minutes | "every 30min" |
| Relative | Play after trigger | "5min after stop" |
| Cron | Cron expression | "0 9 * * 1-5" |

### Configuration

```go
type Schedule struct {
    ID          string          `json:"id"`
    Name        string          `json:"name"`
    Sound       string          `json:"sound"`
    Event       string          `json:"event"`         // stop, permission_prompt, etc.
    Volume      float64         `json:"volume"`
    Schedule    ScheduleConfig  `json:"schedule"`
    Enabled     bool            `json:"enabled"`
    Profile     string          `json:"profile"`
    Repeat      RepeatConfig    `json:"repeat"`
}

type ScheduleConfig struct {
    Type        string    `json:"type"`           // "time", "interval", "cron"
    Time        string    `json:"time"`           // "HH:MM"
    Interval    int       `json:"interval"`       // minutes
    Cron        string    `json:"cron"`           // cron expression
    StartDate   time.Time `json:"start_date"`
    EndDate     time.Time `json:"end_date"`
    DaysOfWeek  []int     `json:"days_of_week"`   // 0-6, Sunday=0
}

type RepeatConfig struct {
    Enabled     bool      `json:"enabled"`
    Count       int       `json:"count"`          // -1 for infinite
    Interval    int       `json:"interval"`       // minutes between repeats
}
```

### Commands

```bash
/ccbell:schedule list                 # List all schedules
/ccbell:schedule add "Morning" --time 09:00 --sound bundled:stop
/ccbell:schedule add "Break" --interval 30 --sound bundled:idle_prompt
/ccbell:schedule add "Focus" --cron "0 */30 * * 1-5" --sound bundled:subagent
/ccbell:schedule enable <id>          # Enable schedule
/ccbell:schedule disable <id>         # Disable schedule
/ccbell:schedule delete <id>          # Remove schedule
/ccbell:schedule run <id>             # Trigger now
/ccbell:schedule clear                # Remove all
```

### Output

```
$ ccbell:schedule list

=== Scheduled Sounds ===

[1] Morning Bell
    Sound: bundled:stop
    Time: 09:00, Mon-Fri
    Enabled: Yes
    Next: Jan 15, 09:00

[2] Break Reminder
    Sound: bundled:idle_prompt
    Interval: 30 minutes
    Enabled: Yes
    Next: 14:23 (in 23 min)

[3] Pomodoro End
    Sound: bundled:stop
    Cron: 0 */25 * * 1-5
    Enabled: No
    Last: Jan 14, 16:00

Showing 3 schedules
[Enable] [Edit] [Delete] [Add New]
```

---

## Audio Player Compatibility

Scheduler uses existing audio player:
- Calls `player.Play()` for scheduled sounds
- Same format support
- No player changes required

---

## Implementation

### Scheduler Engine

```go
type Scheduler struct {
    schedules map[string]*Schedule
    ticker    *time.Ticker
    running   bool
    player    *audio.Player
    config    *SchedulerConfig
}

func (s *Scheduler) Run() {
    s.running = true
    s.ticker = time.NewTicker(1 * time.Minute)

    for range s.ticker.C {
        s.checkSchedules()
    }
}

func (s *Scheduler) checkSchedules() {
    now := time.Now()

    for _, schedule := range s.schedules {
        if !schedule.Enabled {
            continue
        }

        if s.shouldTrigger(schedule, now) {
            s.trigger(schedule)
        }
    }
}

func (s *Scheduler) shouldTrigger(schedule *Schedule, now time.Time) bool {
    switch schedule.Schedule.Type {
    case "time":
        return schedule.Schedule.Time == now.Format("15:04") &&
            s.isDayMatch(schedule, now)
    case "interval":
        return s.intervalElapsed(schedule, now)
    case "cron":
        return s.cronMatch(schedule.Schedule.Cron, now)
    }
    return false
}

func (s *Scheduler) trigger(schedule *Schedule) {
    log.Debug("Triggering scheduled sound: %s", schedule.Name)

    s.player.Play(schedule.Sound, schedule.Volume)

    // Handle repeat
    if schedule.Repeat.Enabled && schedule.Repeat.Count != 0 {
        s.scheduleRepeat(schedule)
    }
}
```

### Interval Tracking

```go
func (s *Scheduler) intervalElapsed(schedule *Schedule, now time.Time) bool {
    lastTrigger, ok := s.lastTrigger[schedule.ID]
    if !ok {
        return true // First run
    }

    elapsed := now.Sub(lastTrigger)
    return elapsed >= time.Duration(schedule.Schedule.Interval)*time.Minute
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Go standard library |

---

## References

### ccbell Implementation Research

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Schedule config

### Research Sources

- [Cron expression format](https://en.wikipedia.org/wiki/Cron)
- [Go time package](https://pkg.go.dev/time)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
