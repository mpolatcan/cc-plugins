# Feature: Sound Event Systemd Timer Monitor

Play sounds for systemd timer events, missed schedules, and execution status.

## Summary

Monitor systemd timers for execution status, missed schedules, and completion events, playing sounds for timer events.

## Motivation

- Timer awareness
- Schedule monitoring
- Execution alerts
- Missed job detection
- Automation tracking

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
| Timer Elapsed | Timer triggered | elapsed |
| Job Started | Service started | started |
| Job Completed | Service finished | completed |
| Job Failed | Service failed | failed |
| Missed Schedule | Schedule missed | missed |
| Next Run | Next scheduled | in 5 min |

### Configuration

```go
type SystemdTimerMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchTimers    []string          `json:"watch_timers"` // "*" for all
    SoundOnElapsed bool              `json:"sound_on_elapsed"`
    SoundOnFailed  bool              `json:"sound_on_failed"`
    SoundOnMissed  bool              `json:"sound_on_missed"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:timer status                # Show timer status
/ccbell:timer add backup.timer      # Add timer to watch
/ccbell:timer sound elapsed <sound>
/ccbell:timer test                  # Test timer sounds
```

### Output

```
$ ccbell:timer status

=== Sound Event Systemd Timer Monitor ===

Status: Enabled
Watch Timers: all

Timer Status:

[1] backup.timer
    Status: ACTIVE
    Last Run: Jan 14 02:00
    Next Run: Jan 15 02:00
    Schedule: Daily at 02:00
    Last Result: done
    Sound: bundled:timer-backup

[2] apt-daily.timer
    Status: ACTIVE
    Last Run: Jan 14 06:00
    Next Run: Jan 14 07:00
    Schedule: Hourly
    Last Result: done
    Sound: bundled:timer-apt

[3] logrotate.timer
    Status: ELAPSED *** JUST RUN ***
    Last Run: Jan 14 10:30
    Next Run: Jan 14 11:30
    Schedule: Hourly
    Sound: bundled:timer-logrotate *** ACTIVE ***

Recent Events:

[1] logrotate.timer: Timer Elapsed (5 min ago)
       logrotate.service started
       Sound: bundled:timer-elapsed
  [2] backup.timer: Job Completed (8 hours ago)
       backup.service completed successfully
       Sound: bundled:timer-complete
  [3] apt-daily.timer: Next Run (12 hours ago)
       Next scheduled run in 1 hour
       Sound: bundled:timer-next

Timer Statistics:
  Total Timers: 3
  Active: 3
  Inactive: 0
  Missed Today: 0

Sound Settings:
  Elapsed: bundled:timer-elapsed
  Complete: bundled:timer-complete
  Failed: bundled:timer-failed
  Missed: bundled:timer-missed

[Configure] [Add Timer] [Test All]
```

---

## Audio Player Compatibility

Timer monitoring doesn't play sounds directly:
- Monitoring feature using systemctl list-timers
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS - N/A) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Systemd Timer Monitor

```go
type SystemdTimerMonitor struct {
    config        *SystemdTimerMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    timerState    map[string]*TimerInfo
    lastEventTime map[string]time.Time
}

type TimerInfo struct {
    Name       string
    Status     string // "active", "inactive", "elapsed"
    LastRun    time.Time
    NextRun    time.Time
    Schedule   string
    LastResult string // "done", "failed", "running"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| systemctl | System Tool | Free | Systemd control |

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
| macOS | Not Supported | systemd not available |
| Linux | Supported | Uses systemctl |
