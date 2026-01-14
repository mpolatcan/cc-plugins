# Feature: Sound Event Cron Job Monitor

Play sounds for scheduled task and cron job events.

## Summary

Monitor cron jobs, scheduled tasks, and automated job executions, playing sounds for scheduled task events.

## Motivation

- Scheduled task feedback
- Backup completion alerts
- Automation awareness
- Task failure warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cron Job Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Started | Cron job began | Backup script |
| Job Completed | Job finished | Exit 0 |
| Job Failed | Job errored | Exit > 0 |
| Job Skipped | Job skipped | Already running |
| Daily Summary | Daily report | 5 jobs run |

### Configuration

```go
type CronJobMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchJobs     []string          `json:"watch_jobs"` // Job names
    SoundOnStart  bool              `json:"sound_on_start"`
    SoundOnFail   bool              `json:"sound_on_fail"`
    SoundOnComplete bool            `json:"sound_on_complete"`
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 60 default
}

type CronJobEvent struct {
    JobName    string
    EventType  string // "started", "completed", "failed", "skipped"
    ExitCode   int
    Output     string
    Duration   time.Duration
}
```

### Commands

```bash
/ccbell:cron-job status           # Show cron status
/ccbell:cron-job add "backup"     # Add job to watch
/ccbell:cron-job remove "backup"  # Remove job
/ccbell:cron-job sound start <sound>
/ccbell:cron-job sound failed <sound>
/ccbell:cron-job test             # Test cron sounds
```

### Output

```
$ ccbell:cron-job status

=== Sound Event Cron Job Monitor ===

Status: Enabled
Start Sounds: Yes
Fail Sounds: Yes

Watched Jobs: 4

[1] daily-backup
    Schedule: 0 3 * * *
    Last Run: 5 hours ago
    Status: COMPLETED (exit 0)
    Duration: 15 min
    Sound: bundled:stop
    [Edit] [Remove]

[2] cleanup-logs
    Schedule: 0 2 * * 0
    Last Run: 1 day ago
    Status: FAILED (exit 1)
    Duration: 2 sec
    Error: Permission denied
    Sound: bundled:stop
    [Edit] [Remove]

[3] sync-files
    Schedule: */15 * * * *
    Last Run: 30 min ago
    Status: RUNNING
    Duration: 5 min
    Sound: bundled:stop
    [Edit] [Remove]

[4] update-index
    Schedule: 0 * * * *
    Last Run: 1 hour ago
    Status: COMPLETED (exit 0)
    Duration: 30 sec
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] daily-backup: Completed (5 hours ago)
  [2] cleanup-logs: Failed (1 day ago)
  [3] sync-files: Started (30 min ago)

Sound Settings:
  Started: bundled:stop
  Completed: bundled:stop
  Failed: bundled:stop

[Configure] [Add Job] [Test All]
```

---

## Audio Player Compatibility

Cron job monitoring doesn't play sounds directly:
- Monitoring feature using cron log parsing
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cron Job Monitor

```go
type CronJobMonitor struct {
    config      *CronJobMonitorConfig
    player      *audio.Player
    running     bool
    stopCh      chan struct{}
    lastJobs    map[string]*CronJobState
}

type CronJobState struct {
    LastRun     time.Time
    Status      string
    ExitCode    int
    Duration    time.Duration
}

func (m *CronJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastJobs = make(map[string]*CronJobState)
    go m.monitor()
}

func (m *CronJobMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkCronJobs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CronJobMonitor) checkCronJobs() {
    events := m.parseCronLog()

    for _, event := range events {
        m.evaluateEvent(event)
    }
}

func (m *CronJobMonitor) parseCronLog() []*CronJobEvent {
    var events []*CronJobEvent

    // Read system log for cron messages
    logPaths := []string{
        "/var/log/syslog",
        "/var/log/cron.log",
        "/var/log/messages",
        "/var/log/system.log",
    }

    var logData []byte
    for _, path := range logPaths {
        if data, err := os.ReadFile(path); err == nil {
            logData = data
            break
        }
    }

    if logData == nil {
        return events
    }

    lines := strings.Split(string(logData), "\n")
    for _, line := range lines {
        if !strings.Contains(line, "CRON") && !strings.Contains(line, "cron") {
            continue
        }

        event := m.parseCronLine(line)
        if event != nil {
            events = append(events, event)
        }
    }

    return events
}

func (m *CronJobMonitor) parseCronLine(line string) *CronJobEvent {
    event := &CronJobEvent{}

    // Parse timestamp
    parts := strings.Fields(line)
    if len(parts) < 6 {
        return nil
    }

    // Look for command pattern
    cmdIdx := -1
    for i, part := range parts {
        if part == "CMD" {
            cmdIdx = i + 1
            break
        }
    }

    if cmdIdx == -1 || cmdIdx >= len(parts) {
        return nil
    }

    command := strings.Join(parts[cmdIdx:], " ")

    // Match against watched jobs
    for _, job := range m.config.WatchJobs {
        if strings.Contains(command, job) {
            event.JobName = job
            event.EventType = "started"
            return event
        }
    }

    return nil
}

func (m *CronJobMonitor) evaluateEvent(event *CronJobEvent) {
    lastState := m.lastJobs[event.JobName]

    if lastState != nil {
        // Check if this is a new run
        if event.EventType == "started" && lastState.Status == "completed" {
            m.onJobStarted(event.JobName)
        }

        // Update state
        lastState.Status = event.EventType
        lastState.LastRun = event.Timestamp
        lastState.ExitCode = event.ExitCode
        lastState.Duration = event.Duration
    }
}

func (m *CronJobMonitor) onJobStarted(jobName string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CronJobMonitor) onJobCompleted(jobName string) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["completed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CronJobMonitor) onJobFailed(jobName string) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /var/log/syslog | File | Free | System logging |
| /var/log/cron.log | File | Free | Cron logging |
| cron | System Tool | Free | Scheduler daemon |

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
| macOS | Supported | Uses /var/log/system.log |
| Linux | Supported | Uses /var/log/syslog |
| Windows | Not Supported | ccbell only supports macOS/Linux |
