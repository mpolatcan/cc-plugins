# Feature: Sound Event Cron Job Monitor

Play sounds for cron job completions, failures, and schedule changes.

## Summary

Monitor cron job executions, completion status, and failure events, playing sounds for cron job events.

## Motivation

- Job completion awareness
- Backup notification
- Script failure alerts
- Scheduled task feedback
- Maintenance alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Cron Job Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Completed | Cron job finished successfully | backup.sh completed |
| Job Failed | Cron job exited with error | rsync failed |
| Job Started | Cron job execution began | cleanup.sh started |
| Job Too Long | Job exceeded time limit | exceeded 1h limit |
| Cron Reloaded | Crontab reloaded | New cron installed |

### Configuration

```go
type CronJobMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchJobs          []string          `json:"watch_jobs"` // "backup", "sync", "*"
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnFail        bool              `json:"sound_on_fail"`
    SoundOnLong        bool              `json:"sound_on_long"`
    SoundOnReload      bool              `json:"sound_on_reload"`
    MaxJobDuration     int               `json:"max_job_duration_minutes"` // 60 default
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 60 default
}

type CronJobEvent struct {
    Job       string
    Command   string
    ExitCode  int
    Duration  int // seconds
    Output    string
    Scheduled string // "*/5 * * * *"
    EventType string // "complete", "fail", "start", "long", "reload"
}
```

### Commands

```bash
/ccbell:cron status                   # Show cron job status
/ccbell:cron add backup               # Add job to watch
/ccbell:cron remove backup
/ccbell:cron sound complete <sound>
/ccbell:cron sound fail <sound>
/ccbell:cron test                     # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Job Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Long Job Sounds: Yes

Watched Jobs: 3

[1] backup
    Schedule: 0 2 * * *
    Last Run: 2 hours ago
    Status: SUCCESS (exit 0)
    Duration: 45 min
    Sound: bundled:cron-backup

[2] sync
    Schedule: */5 * * * *
    Last Run: 5 min ago
    Status: SUCCESS (exit 0)
    Duration: 30 sec
    Sound: bundled:cron-sync

[3] cleanup
    Schedule: 0 3 * * 0
    Last Run: 1 day ago
    Status: FAILED (exit 1)
    Duration: 2 min
    Sound: bundled:cron-cleanup

Recent Events:
  [1] sync: Job Completed (5 min ago)
       Files synchronized successfully
  [2] backup: Job Completed (2 hours ago)
       Backup completed in 45 min
  [3] cleanup: Job Failed (1 day ago)
       Error: Permission denied

Cron Job Statistics:
  Jobs watched: 3
  Completed today: 28
  Failed: 1

Sound Settings:
  Complete: bundled:cron-success
  Fail: bundled:cron-fail
  Long: bundled:cron-long

[Configure] [Add Job] [Test All]
```

---

## Audio Player Compatibility

Cron job monitoring doesn't play sounds directly:
- Monitoring feature using crontab and log parsing
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cron Job Monitor

```go
type CronJobMonitor struct {
    config          *CronJobMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    jobState        map[string]*CronJobInfo
    lastEventTime   map[string]time.Time
    lastRunTime     map[string]time.Time
}

type CronJobInfo struct {
    Name        string
    Command     string
    Schedule    string
    LastRun     time.Time
    LastStatus  string // "success", "failed", "running"
    ExitCode    int
    Duration    int // seconds
    Output      string
}

func (m *CronJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.jobState = make(map[string]*CronJobInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastRunTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CronJobMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotJobState()

    for {
        select {
        case <-ticker.C:
            m.checkJobState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *CronJobMonitor) snapshotJobState() {
    m.readCrontab()
}

func (m *CronJobMonitor) checkJobState() {
    // Read cron logs
    m.readCronLogs()

    // Check for long-running jobs
    m.checkLongRunningJobs()
}

func (m *CronJobMonitor) readCrontab() {
    cmd := exec.Command("crontab", "-l")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }

        // Parse: "*/5 * * * * /path/to/script.sh"
        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        schedule := strings.Join(parts[:5], " ")
        command := strings.Join(parts[5:], " ")

        // Extract job name from command
        name := m.extractJobName(command)
        if !m.shouldWatchJob(name) {
            continue
        }

        if m.jobState[name] == nil {
            m.jobState[name] = &CronJobInfo{
                Name:     name,
                Command:  command,
                Schedule: schedule,
            }
        }
    }
}

func (m *CronJobMonitor) readCronLogs() {
    // Try different log locations
    logPaths := []string{
        "/var/log/syslog",
        "/var/log/cron.log",
        "/var/log/messages",
    }

    for _, logPath := range logPaths {
        if _, err := os.Stat(logPath); err == nil {
            m.parseCronLog(logPath)
            break
        }
    }
}

func (m *CronJobMonitor) parseCronLog(logPath string) {
    // Read last N lines
    cmd := exec.Command("tail", "-100", logPath)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if !strings.Contains(line, "CRON") && !strings.Contains(line, "cron") {
            continue
        }

        // Parse cron log entry
        // Format varies by system
        m.parseCronEntry(line)
    }
}

func (m *CronJobMonitor) parseCronEntry(line string) {
    // Look for job execution patterns
    // Example: "(root) CMD (/usr/local/bin/backup.sh)"

    cmdRe := regexp.MustCompile(`CMD \(([^)]+)\)`)
    match := cmdRe.FindStringSubmatch(line)
    if match == nil {
        return
    }

    command := match[1]
    name := m.extractJobName(command)

    if !m.shouldWatchJob(name) {
        return
    }

    job := m.jobState[name]
    if job == nil {
        job = &CronJobInfo{Name: name, Command: command}
        m.jobState[name] = job
    }

    // Check if this is a new run
    lastRun, exists := m.lastRunTime[name]
    if !exists || time.Since(lastRun) > time.Duration(m.config.PollInterval)*time.Second {
        job.LastRun = time.Now()
        job.LastStatus = "running"
        m.lastRunTime[name] = job.LastRun

        // Set timeout for completion
        go m.waitForJobCompletion(name)
    }
}

func (m *CronJobMonitor) waitForJobCompletion(name string) {
    time.Sleep(10 * time.Second) // Give job time to complete

    job := m.jobState[name]
    if job == nil {
        return
    }

    // Check exit status from logs
    // This is a simplified approach
    job.LastStatus = "success"
    m.onJobCompleted(job)
}

func (m *CronJobMonitor) checkLongRunningJobs() {
    for name, job := range m.jobState {
        if job.LastStatus == "running" && job.LastRun.Add(time.Duration(m.config.MaxJobDuration)*time.Minute).Before(time.Now()) {
            job.LastStatus = "long"
            m.onJobTooLong(job)
        }
    }
}

func (m *CronJobMonitor) extractJobName(command string) string {
    // Try to extract a meaningful name from command
    // e.g., "/usr/local/bin/backup.sh" -> "backup"
    parts := strings.Split(command, "/")
    last := parts[len(parts)-1]

    // Remove extension
    if idx := strings.LastIndex(last, "."); idx != -1 {
        last = last[:idx]
    }

    return last
}

func (m *CronJobMonitor) shouldWatchJob(name string) bool {
    if len(m.config.WatchJobs) == 0 {
        return true
    }

    for _, j := range m.config.WatchJobs {
        if j == "*" || strings.Contains(name, j) {
            return true
        }
    }

    return false
}

func (m *CronJobMonitor) onJobCompleted(job *CronJobInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", job.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CronJobMonitor) onJobFailed(job *CronJobInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", job.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *CronJobMonitor) onJobTooLong(job *CronJobInfo) {
    if !m.config.SoundOnLong {
        return
    }

    key := fmt.Sprintf("long:%s", job.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["long"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CronJobMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| crontab | System Tool | Free | Cron management |
| /var/log/cron.log | File | Free | Cron logs |
| /var/log/syslog | File | Free | System logs |

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
| macOS | Supported | Uses crontab, system log |
| Linux | Supported | Uses crontab, syslog |
