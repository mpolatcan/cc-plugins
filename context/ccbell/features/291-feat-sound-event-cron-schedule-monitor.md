# Feature: Sound Event Cron Schedule Monitor

Play sounds for cron job execution and schedule changes.

## Summary

Monitor cron job schedules, execution status, and timing, playing sounds for cron events.

## Motivation

- Scheduled task awareness
- Job execution feedback
- Schedule change alerts
- Missed job detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Cron Schedule Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Started | Cron executed | backup.sh |
| Job Completed | Job finished | Exit 0 |
| Job Failed | Job errored | Exit 1 |
| Schedule Changed | Crontab updated | New entry |

### Configuration

```go
type CronScheduleMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchUsers       []string          `json:"watch_users"` // "root", "user"
    WatchPatterns    []string          `json:"watch_patterns"` // "backup", "sync"
    SoundOnStart     bool              `json:"sound_on_start"]
    SoundOnComplete  bool              `json:"sound_on_complete"]
    SoundOnFail      bool              `json:"sound_on_fail"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 30 default
}

type CronScheduleEvent struct {
    User      string
    Command   string
    Schedule  string
    ExitCode  int
    EventType string // "start", "complete", "fail", "schedule_change"
}
```

### Commands

```bash
/ccbell:cron status                  # Show cron status
/ccbell:cron add root                # Add user to watch
/ccbell:cron remove root
/ccbell:cron sound start <sound>
/ccbell:cron sound fail <sound>
/ccbell:cron test                    # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Schedule Monitor ===

Status: Enabled
Start Sounds: Yes
Fail Sounds: Yes

Watched Users: 2

[1] root
    Jobs: 15
    Last Run: 5 min ago
    Status: OK
    Sound: bundled:stop

[2] user
    Jobs: 8
    Last Run: 10 min ago
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] root: backup.sh Completed (5 min ago)
       Exit: 0, Duration: 2 min
  [2] root: cleanup.log Failed (1 hour ago)
       Exit: 1, Error: file not found
  [3] user: sync.sh Started (2 hours ago)
       */15 * * * *

Upcoming Jobs:
  - root: health check in 5 min
  - user: cleanup in 10 min

Sound Settings:
  Start: bundled:stop
  Complete: bundled:stop
  Fail: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

Cron schedule monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cron Schedule Monitor

```go
type CronScheduleMonitor struct {
    config         *CronScheduleMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    cronState      map[string][]*CronJob
    lastRunTime    map[string]time.Time
}

type CronJob struct {
    User     string
    Schedule string
    Command  string
}
```

```go
func (m *CronScheduleMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.cronState = make(map[string][]*CronJob)
    m.lastRunTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CronScheduleMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Snapshot current crontabs
    m.snapshotCrontabs()

    for {
        select {
        case <-ticker.C:
            m.checkCronJobs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CronScheduleMonitor) snapshotCrontabs() {
    // Get crontabs for watched users
    users := m.config.WatchUsers
    if len(users) == 0 {
        users = []string{"root", os.Getenv("USER")}
    }

    for _, user := range users {
        jobs := m.getCrontab(user)
        m.cronState[user] = jobs
    }
}

func (m *CronScheduleMonitor) getCrontab(user string) []*CronJob {
    var jobs []*CronJob

    cmd := exec.Command("crontab", "-u", user, "-l")
    output, err := cmd.Output()

    if err != nil {
        // Try current user
        cmd = exec.Command("crontab", "-l")
        output, err = cmd.Output()
        if err != nil {
            return jobs
        }
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }

        job := m.parseCronLine(line, user)
        if job != nil {
            jobs = append(jobs, job)
        }
    }

    return jobs
}

func (m *CronScheduleMonitor) parseCronLine(line string, user string) *CronJob {
    // Parse crontab line: "min hour day month weekday command"
    parts := strings.Fields(line)
    if len(parts) < 6 {
        return nil
    }

    schedule := strings.Join(parts[:5], " ")
    command := strings.Join(parts[5:], " ")

    // Check pattern filter
    if len(m.config.WatchPatterns) > 0 {
        found := false
        for _, pattern := range m.config.WatchPatterns {
            if strings.Contains(command, pattern) {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    return &CronJob{
        User:     user,
        Schedule: schedule,
        Command:  command,
    }
}

func (m *CronScheduleMonitor) checkCronJobs() {
    // Check cron logs for executed jobs
    if runtime.GOOS == "darwin" {
        m.checkDarwinCronLogs()
    } else {
        m.checkLinuxCronLogs()
    }

    // Check for schedule changes
    m.checkScheduleChanges()
}

func (m *CronScheduleMonitor) checkDarwinCronLogs() {
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'cron' || eventMessage CONTAINS 'CRON'",
        "--last", "5m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseCronLogOutput(string(output))
}

func (m *CronScheduleMonitor) checkLinuxCronLogs() {
    data, err := os.ReadFile("/var/log/syslog")
    if err != nil {
        data, err = os.ReadFile("/var/log/cron.log")
    }
    if err != nil {
        return
    }

    m.parseCronLog(string(data))
}

func (m *CronScheduleMonitor) parseCronLogOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "CMD") {
            event := &CronScheduleEvent{
                EventType: "start",
                Timestamp: time.Now(),
            }
            m.onCronJobStarted(event)
        }
    }
}

func (m *CronScheduleMonitor) parseCronLog(log string) {
    lines := strings.Split(log, "\n")
    for _, line := range lines {
        if strings.Contains(line, "CRON") && strings.Contains(line, "CMD") {
            event := &CronScheduleEvent{
                EventType: "start",
                Timestamp: time.Now(),
            }
            m.onCronJobStarted(event)
        }
    }
}

func (m *CronScheduleMonitor) checkScheduleChanges() {
    users := m.config.WatchUsers
    if len(users) == 0 {
        users = []string{"root", os.Getenv("USER")}
    }

    for _, user := range users {
        currentJobs := m.getCrontab(user)
        lastJobs := m.cronState[user]

        if len(currentJobs) != len(lastJobs) {
            // Schedule changed
            m.onScheduleChanged(user)
        }

        m.cronState[user] = currentJobs
    }
}

func (m *CronScheduleMonitor) onCronJobStarted(event *CronScheduleEvent) {
    if !m.config.SoundOnStart {
        return
    }

    key := fmt.Sprintf("cron:%s", event.Command)
    if time.Since(m.lastRunTime[key]) < 1*time.Minute {
        return
    }
    m.lastRunTime[key] = time.Now()

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *CronScheduleMonitor) onCronJobCompleted(event *CronScheduleEvent) {
    if !m.config.SoundOnComplete {
        return
    }

    if event.ExitCode == 0 {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CronScheduleMonitor) onCronJobFailed(event *CronScheduleEvent) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["fail"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *CronScheduleMonitor) onScheduleChanged(user string) {
    sound := m.config.Sounds["schedule_change"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| crontab | System Tool | Free | Cron management |
| log | System Tool | Free | macOS logging |
| /var/log/syslog | File | Free | Linux logging |

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
| macOS | Supported | Uses crontab, log |
| Linux | Supported | Uses crontab, /var/log/syslog |
| Windows | Not Supported | ccbell only supports macOS/Linux |
