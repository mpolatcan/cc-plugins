# Feature: Sound Event Time Monitor

Play sounds for time-based events and reminders.

## Summary

Monitor time-based events including hourly chimes, countdown timers, stopwatch completion, and custom time triggers.

## Motivation

- Hourly time awareness
- Pomodoro timer feedback
- Meeting countdown
- Focus session alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Time Events

| Event | Description | Example |
|-------|-------------|---------|
| Hourly Chime | Top of every hour | 9:00, 10:00 |
| Half Hour | Every 30 minutes | 9:30, 10:30 |
| Quarter Hour | Every 15 minutes | 9:15, 9:45 |
| Custom Time | User-defined time | 3:00 PM daily |
| Timer Done | Countdown finished | 25 min timer |
| Stopwatch Lap | Stopwatch lap completed | 1 km lap |

### Configuration

```go
type TimeMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    HourlyChime     bool              `json:"hourly_chime"`
    HalfHourChime   bool              `json:"half_hour_chime"`
    QuarterChime    bool              `json:"quarter_chime"`
    Timezone        string            `json:"timezone"` // "America/New_York"
    CustomTimes     []CustomTime      `json:"custom_times"`
    Timers          []Timer           `json:"timers"`
    Sounds          map[string]string `json:"sounds"`
}

type CustomTime struct {
    Time    string `json:"time"` // "15:00" for 3 PM
    Days    []int  `json:"days"` // 1=Mon, 7=Sun
    Sound   string `json:"sound"`
    Enabled bool   `json:"enabled"`
}

type Timer struct {
    Name       string  `json:"name"`
    Duration   int     `json:"duration_sec"` // 1500 for 25 min
    Repeat     bool    `json:"repeat"` // Auto-restart
    Sound      string  `json:"sound"`
    Running    bool    `json:"running"`
}
```

### Commands

```bash
/ccbell:time status               # Show time status
/ccbell:time hourly on            # Enable hourly chimes
/ccbell:time quarter on           # Enable 15-min chimes
/ccbell:time add 15:00 --days 1-5 # Add custom time
/ccbell:time timer "Pomodoro" 1500 # Start timer
/ccbell:time timer stop "Pomodoro" # Stop timer
/ccbell:time sound chime <sound>
/ccbell:time test                 # Test time sounds
```

### Output

```
$ ccbell:time status

=== Sound Event Time Monitor ===

Status: Enabled
Hourly Chime: Yes (Sound A)
Quarter Chime: Yes (Sound B)

Current Time: 10:47 AM EST
  Next Hourly: 11:00 AM (13 min)
  Next Quarter: 11:00 AM (13 min)

Custom Times: 2

[1] 3:00 PM (Weekdays)
    Sound: bundled:stop
    Status: Pending
    [Edit] [Remove]

[2] 6:00 AM (Daily)
    Sound: bundled:stop
    Status: Pending
    [Edit] [Remove]

Active Timers: 1

[1] Pomodoro
    Duration: 25 min
    Remaining: 18 min 32 sec
    Sound: bundled:stop
    [Stop] [Edit]

[Configure] [Add Time] [Add Timer] [Test All]
```

---

## Audio Player Compatibility

Time monitoring doesn't play sounds directly:
- Time-based event triggering
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Time Monitor

```go
type TimeMonitor struct {
    config       *TimeMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    timerEnd     map[string]time.Time
    lastMinute   int
}

func (m *TimeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.timerEnd = make(map[string]time.Time)
    m.lastMinute = time.Now().Minute()
    go m.monitor()
}

func (m *TimeMonitor) monitor() {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTime()
        case <-m.stopCh:
            return
        }
    }
}

func (m *TimeMonitor) checkTime() {
    now := time.Now()

    // Check minute changes for time-based events
    if now.Minute() != m.lastMinute {
        m.onMinuteChange(now)
        m.lastMinute = now.Minute()
    }

    // Check timers
    for name, endTime := range m.timerEnd {
        if time.Now().After(endTime) {
            m.onTimerComplete(name)
            delete(m.timerEnd, name)
        }
    }
}

func (m *TimeMonitor) onMinuteChange(now time.Time) {
    minute := now.Minute()

    // Hourly chime
    if m.config.HourlyChime && minute == 0 {
        m.onHourlyChime(now)
    }

    // Half hour chime
    if m.config.HalfHourChime && minute == 30 {
        m.onHalfHourChime(now)
    }

    // Quarter hour chime
    if m.config.QuarterChime && minute%15 == 0 {
        m.onQuarterChime(now)
    }

    // Custom times
    m.checkCustomTimes(now)
}

func (m *TimeMonitor) checkCustomTimes(now time.Time) {
    currentTime := now.Format("15:04")
    today := int(now.Weekday())
    if today == 0 {
        today = 7 // Convert Sunday from 0 to 7
    }

    for _, custom := range m.config.CustomTimes {
        if !custom.Enabled {
            continue
        }

        // Check day of week
        dayMatch := false
        for _, day := range custom.Days {
            if day == today {
                dayMatch = true
                break
            }
        }
        if !dayMatch && len(custom.Days) > 0 {
            continue
        }

        // Check time
        if custom.Time == currentTime {
            m.onCustomTime(custom)
        }
    }
}

func (m *TimeMonitor) onHourlyChime(now time.Time) {
    sound := m.config.Sounds["hourly"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TimeMonitor) onHalfHourChime(now time.Time) {
    sound := m.config.Sounds["half_hour"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TimeMonitor) onQuarterChime(now time.Time) {
    sound := m.config.Sounds["quarter"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TimeMonitor) onCustomTime(custom CustomTime) {
    sound := custom.Sound
    if sound == "" {
        sound = m.config.Sounds["custom"]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *TimeMonitor) startTimer(name string, duration int) error {
    _, exists := m.timerEnd[name]
    if exists {
        return fmt.Errorf("timer %s already running", name)
    }

    m.timerEnd[name] = time.Now().Add(time.Duration(duration) * time.Second)

    // Find timer config
    for _, timer := range m.config.Timers {
        if timer.Name == name {
            timer.Running = true
            break
        }
    }

    return nil
}

func (m *TimeMonitor) stopTimer(name string) {
    delete(m.timerEnd, name)

    // Update timer config
    for _, timer := range m.config.Timers {
        if timer.Name == name {
            timer.Running = false
            break
        }
    }
}

func (m *TimeMonitor) onTimerComplete(name string) {
    // Find timer config
    for _, timer := range m.config.Timers {
        if timer.Name == name {
            sound := timer.Sound
            if sound == "" {
                sound = m.config.Sounds["timer"]
            }
            if sound != "" {
                m.player.Play(sound, 0.5)
            }

            // Auto-restart if repeat enabled
            if timer.Repeat {
                m.timerEnd[name] = time.Now().Add(time.Duration(timer.Duration) * time.Second)
            }

            timer.Running = false
            break
        }
    }
}

func (m *TimeMonitor) getTimerRemaining(name string) time.Duration {
    endTime, exists := m.timerEnd[name]
    if !exists {
        return 0
    }

    remaining := time.Until(endTime)
    if remaining < 0 {
        return 0
    }

    return remaining
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| time | Go Stdlib | Free | Time operations |
| timezone | System | Free | Timezone data |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses Go time package |
| Linux | Supported | Uses Go time package |
| Windows | Not Supported | ccbell only supports macOS/Linux |
