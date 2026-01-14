# Feature: Sound Event Cron Monitor

Play sounds for scheduled task events.

## Summary

Play sounds when cron jobs or scheduled tasks run, complete, or fail.

## Motivation

- Task completion alerts
- Cron job monitoring
- Scheduled backup notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cron Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Started | Cron job begins | Backup started |
| Job Completed | Cron job finished | Backup done |
| Job Failed | Cron job errored | Backup failed |
| Job Skipped | Cron job skipped | Already running |

### Configuration

```go
type CronMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchJobs     []*CronJobWatch  `json:"watch_jobs"`
    LogPath       string            `json:"log_path"` // /var/log/syslog or custom
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int              `json:"poll_interval_sec"` // 30 default
}

type CronJobWatch struct {
    Name         string  `json:"name"`
    Command      string  `json:"command,omitempty"` // Match by command
    Schedule     string  `json:"schedule,omitempty"` // Match by schedule
    Sound        string  `json:"sound"`
    Enabled      bool    `json:"enabled"`
}

type CronEvent struct {
    JobName     string
    Command     string
    Status      string // "started", "completed", "failed", "skipped"
    ExitCode    int
    Duration    time.Duration
    Timestamp   time.Time
    Output      string
}
```

### Commands

```bash
/ccbell:cron status                 # Show cron status
/ccbell:cron add "Backup" --command "/usr/local/bin/backup.sh"
/ccbell:cron add "Cleanup" --schedule "0 2 * * *"
/ccbell:cron sound started <sound>
/ccbell:cron sound completed <sound>
/ccbell:cron sound failed <sound>
/ccbell:cron remove "Backup"
/ccbell:cron test                   # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Monitor ===

Status: Enabled
Poll Interval: 30s

Watched Jobs: 3

[1] Backup
    Command: /usr/local/bin/backup.sh
    Schedule: 0 3 * * *
    Last Run: 3 hours ago
    Status: Completed (exit 0)
    Duration: 45s
    Sound: bundled:stop
    [Edit] [Remove]

[2] Cleanup
    Command: /usr/local/bin/cleanup.sh
    Schedule: 0 2 * * *
    Last Run: Yesterday 2 AM
    Status: Completed (exit 0)
    Duration: 120s
    Sound: bundled:stop
    [Edit] [Remove]

[3] Sync
    Command: /usr/local/bin/sync.sh
    Schedule: */15 * * * *
    Last Run: 10 min ago
    Status: Failed (exit 1)
    Duration: 5s
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] Backup: Completed (3 hours ago)
  [2] Sync: Failed (1 hour ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Cron monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Cron Monitor

```go
type CronMonitor struct {
    config   *CronMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStates map[string]*CronJobState
}

type CronJobState struct {
    LastRun     time.Time
    Status      string
    ExitCode    int
    Duration    time.Duration
}

func (m *CronMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStates = make(map[string]*CronJobState)
    go m.monitor()
}

func (m *CronMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkJobs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CronMonitor) checkJobs() {
    events := m.parseCronLog()

    for _, event := range events {
        m.evaluateEvent(event)
    }
}

func (m *CronMonitor) parseCronLog() []*CronEvent {
    var events []*CronEvent

    // Read cron log
    logPaths := []string{
        "/var/log/syslog",
        "/var/log/cron.log",
        "/var/log/messages",
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
        if !strings.Contains(line, "CRON") {
            continue
        }

        // Parse cron line
        // Example: Jan 15 03:00:00 hostname CRON[12345]: (root) CMD (/usr/local/bin/backup.sh)
        event := m.parseCronLine(line)
        if event != nil {
            events = append(events, event)
        }
    }

    return events
}

func (m *CronMonitor) parseCronLine(line string) *CronEvent {
    // Extract timestamp
    parts := strings.Fields(line)
    if len(parts) < 8 {
        return nil
    }

    // Parse time
    timestampStr := fmt.Sprintf("%s %s %s", parts[0], parts[1], parts[2])
    timestamp, err := time.Parse("Jan 2 15:04:05", timestampStr)
    if err != nil {
        return nil
    }
    timestamp = timestamp.AddDate(time.Now().Year(), 0, 0)

    // Extract command (everything between CMD and end)
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
        if !job.Enabled {
            continue
        }

        if job.Command != "" && strings.Contains(command, job.Command) {
            return &CronEvent{
                JobName:  job.Name,
                Command:  command,
                Timestamp: timestamp,
            }
        }
    }

    return nil
}

func (m *CronMonitor) evaluateEvent(event *CronEvent) {
    jobName := event.JobName
    lastState := m.lastStates[jobName]

    // Check if this is a new run
    if lastState != nil && !event.Timestamp.After(lastState.LastRun) {
        return
    }

    // Determine event type based on log
    // This is a simplified version - real implementation would check exit codes

    event.Status = "started"

    if lastState != nil {
        if lastState.Status == "started" {
            // Previous job completed
            if lastState.ExitCode == 0 {
                event.Status = "completed"
            } else {
                event.Status = "failed"
            }
            event.ExitCode = lastState.ExitCode
            event.Duration = lastState.Duration
        }
    }

    // Update state
    m.lastStates[jobName] = &CronJobState{
        LastRun:  event.Timestamp,
        Status:   event.Status,
        ExitCode: event.ExitCode,
        Duration: event.Duration,
    }

    // Play sound
    sound := m.findSoundForJob(jobName, event.Status)
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CronMonitor) findSoundForJob(jobName, status string) string {
    for _, job := range m.config.WatchJobs {
        if job.Name == jobName {
            switch status {
            case "completed":
                return job.Sounds["completed"]
            case "failed":
                return job.Sounds["failed"]
            case "started":
                return job.Sounds["started"]
            }
        }
    }
    return m.config.Sounds[status]
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| /var/log/syslog | File | Free | Cron logging |
| /var/log/cron.log | File | Free | Cron logging |

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
| macOS | ✅ Supported | Uses system log |
| Linux | ✅ Supported | Uses /var/log/syslog |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
