# Feature: Sound Event Systemd Timer Monitor

Play sounds for systemd timer executions, missed schedules, and next run events.

## Summary

Monitor systemd timers for scheduled execution, missed triggers, and state changes, playing sounds for timer events.

## Motivation

- Scheduled task awareness
- Missed execution detection
- Timer health monitoring
- Automation tracking
- Service reliability

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Systemd Timer Events

| Event | Description | Example |
|-------|-------------|---------|
| Timer Elapsed | Timer fired | on calendar |
| Job Started | Service started | triggered |
| Job Completed | Service finished | done |
| Missed Trigger | Timer missed | not triggered |
| Next Run | Next schedule | in 5 min |
| Timer Disabled | Timer masked | masked |

### Configuration

```go
type SystemdTimerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchTimers       []string          `json:"watch_timers"` // "*.timer", "*"
    SoundOnElapsed    bool              `json:"sound_on_elapsed"`
    SoundOnMissed     bool              `json:"sound_on_missed"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:timer status                   # Show timer status
/ccbell:timer add "backup.timer"       # Add timer to watch
/ccbell:timer remove "backup.timer"
/ccbell:timer sound elapsed <sound>
/ccbell:timer sound missed <sound>
/ccbell:timer test                     # Test timer sounds
```

### Output

```
$ ccbell:timer status

=== Sound Event Systemd Timer Monitor ===

Status: Enabled
Elapsed Sounds: Yes
Missed Sounds: Yes
Complete Sounds: Yes

Watched Timers: 4

Systemd Timers:

[1] backup.timer (Backup Service)
    Schedule: Daily at 02:00
    Last Elapsed: 2 hours ago
    Next Run: Tomorrow at 02:00
    Last Result: done
    Sound: bundled:timer-backup

[2] apt-daily.timer (APT Update)
    Schedule: Every 12 hours
    Last Elapsed: 5 hours ago
    Next Run: in 7 hours
    Last Result: done
    Sound: bundled:timer-apt

[3] fstrim.timer (SSD Trim)
    Schedule: Weekly on Sunday
    Last Elapsed: 1 day ago
    Next Run: in 6 days
    Last Result: done
    Sound: bundled:timer-fstrim

[4] custom.timer (My Script)
    Schedule: */15 * * * *
    Last Elapsed: 10 min ago
    Next Run: in 5 min
    Last Result: failed
    Sound: bundled:timer-custom *** FAILED ***

Recent Events:
  [1] custom.timer: Job Completed (10 min ago)
       Result: failed (exit code 1)
  [2] backup.timer: Timer Elapsed (2 hours ago)
       Triggered backup.service
  [3] apt-daily.timer: Missed Trigger (1 day ago)
       System was suspended

Timer Statistics:
  Timers: 15 total
  Active: 12
  Missed Today: 1
  Failed: 1

Sound Settings:
  Elapsed: bundled:timer-elapsed
  Missed: bundled:timer-missed
  Complete: bundled:timer-complete

[Configure] [Add Timer] [Test All]
```

---

## Audio Player Compatibility

Timer monitoring doesn't play sounds directly:
- Monitoring feature using systemctl list-timers
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Systemd Timer Monitor

```go
type SystemdTimerMonitor struct {
    config          *SystemdTimerMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    timerState      map[string]*TimerInfo
    lastEventTime   map[string]time.Time
}

type TimerInfo struct {
    Name       string
    Unit       string
    Schedule   string
    LastElapsed time.Time
    NextRun    time.Time
    LastResult string // "done", "failed", "none"
    Status     string // "active", "inactive"
}

func (m *SystemdTimerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.timerState = make(map[string]*TimerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemdTimerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotTimerState()

    for {
        select {
        case <-ticker.C:
            m.checkTimerState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemdTimerMonitor) snapshotTimerState() {
    m.checkTimerState()
}

func (m *SystemdTimerMonitor) checkTimerState() {
    timers := m.listTimers()
    currentTimers := make(map[string]*TimerInfo)

    for _, timer := range timers {
        currentTimers[timer.Name] = timer
    }

    // Check for timer elapsed
    for name, timer := range currentTimers {
        lastTimer := m.timerState[name]
        if lastTimer == nil {
            m.timerState[name] = timer
            continue
        }

        // Check if timer elapsed since last check
        if timer.LastElapsed.After(lastTimer.LastElapsed) {
            m.onTimerElapsed(timer)
        }

        // Check for missed triggers
        if time.Now().After(timer.NextRun) && timer.LastElapsed.Before(timer.NextRun.Add(-5*time.Minute)) {
            if lastTimer.LastElapsed.Before(timer.NextRun.Add(-5*time.Minute)) {
                m.onTimerMissed(timer)
            }
        }

        // Check result
        if timer.LastResult == "failed" && lastTimer.LastResult != "failed" {
            m.onTimerFailed(timer)
        }

        m.timerState[name] = timer
    }
}

func (m *SystemdTimerMonitor) listTimers() []*TimerInfo {
    var timers []*TimerInfo

    cmd := exec.Command("systemctl", "list-timers", "--all", "--no-pager")
    output, err := cmd.Output()
    if err != nil {
        return timers
    }

    lines := strings.Split(string(output), "\n")
    // Skip header and empty lines
    for _, line := range lines {
        if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "NEXT") {
            continue
        }

        // Parse: "backup.timer        daily      n/a  Tue 2024-01-15 02:00:00"
        re := regexp.MustCompile(`(.+?)\s+(.+?)\s+(.+?)\s+(.+?)\s+(.+)$`)
        match := re.FindStringSubmatch(line)
        if match == nil {
            continue
        }

        name := strings.TrimSpace(match[1])
        schedule := strings.TrimSpace(match[2])
        last := strings.TrimSpace(match[3])
        next := strings.TrimSpace(match[4])
        lastResult := strings.TrimSpace(match[5])

        if !m.shouldWatchTimer(name) {
            continue
        }

        timer := &TimerInfo{
            Name:       name,
            Schedule:   schedule,
            LastResult: m.parseLastResult(lastResult),
        }

        // Parse last elapsed time
        if last != "n/a" && last != "" {
            timer.LastElapsed = m.parseTime(last)
        }

        // Parse next run time
        if next != "n/a" && next != "" {
            timer.NextRun = m.parseTime(next)
        }

        timers = append(timers, timer)
    }

    return timers
}

func (m *SystemdTimerMonitor) parseLastResult(result string) string {
    result = strings.ToLower(result)
    if strings.Contains(result, "done") || strings.Contains(result, "exited") {
        return "done"
    } else if strings.Contains(result, "failed") || strings.Contains(result, "error") {
        return "failed"
    }
    return "none"
}

func (m *SystemdTimerMonitor) parseTime(timeStr string) time.Time {
    formats := []string{
        "Mon 2006-01-02 15:04:05",
        "2006-01-02 15:04:05",
        "2006-01-02 15:04",
    }

    for _, format := range formats {
        if t, err := time.Parse(format, timeStr); err == nil {
            return t
        }
    }

    return time.Now()
}

func (m *SystemdTimerMonitor) shouldWatchTimer(name string) bool {
    if len(m.config.WatchTimers) == 0 {
        return true
    }

    for _, t := range m.config.WatchTimers {
        if t == "*" || name == t || strings.HasPrefix(name, t) {
            return true
        }
    }

    return false
}

func (m *SystemdTimerMonitor) onTimerElapsed(timer *TimerInfo) {
    if !m.config.SoundOnElapsed {
        return
    }

    key := fmt.Sprintf("elapsed:%s", timer.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["elapsed"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }

    if timer.LastResult == "done" && m.config.SoundOnComplete {
        key = fmt.Sprintf("complete:%s", timer.Name)
        if m.shouldAlert(key, 1*time.Minute) {
            sound := m.config.Sounds["complete"]
            if sound != "" {
                m.player.Play(sound, 0.3)
            }
        }
    }
}

func (m *SystemdTimerMonitor) onTimerMissed(timer *TimerInfo) {
    if !m.config.SoundOnMissed {
        return
    }

    key := fmt.Sprintf("missed:%s", timer.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["missed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemdTimerMonitor) onTimerFailed(timer *TimerInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("failed:%s", timer.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemdTimerMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| systemctl | System Tool | Free | Systemd management |

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
| macOS | Not Supported | No native systemd |
| Linux | Supported | Uses systemctl list-timers |
