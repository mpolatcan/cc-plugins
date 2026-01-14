# Feature: Sound Event Cron Job Monitor

Play sounds for scheduled job execution, failures, and completion events.

## Summary

Monitor cron jobs and scheduled tasks for execution, errors, and completion, playing sounds for cron job events.

## Motivation

- Scheduled task awareness
- Job failure detection
- Automation monitoring
- Cron health checks
- Execution verification

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
| Job Started | Cron execution began | backup.sh |
| Job Completed | Task finished successfully | clean up |
| Job Failed | Exit code != 0 | error |
| Job Timeout | Exceeded time limit | > 30 min |
| Missed Schedule | Skipped execution | service down |
| Long Running | Exceeds expected time | still running |

### Configuration

```go
type CronJobMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchJobs         []string          `json:"watch_jobs"` // "backup", "*"
    WatchUsers        []string          `json:"watch_users"` // "root", "admin"
    ExpectedDuration  map[string]int    `json:"expected_duration_min"` // job -> minutes
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnTimeout    bool              `json:"sound_on_timeout"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:cron status                    # Show cron status
/ccbell:cron add backup                # Add job to watch
/ccbell:cron remove backup
/ccbell:cron duration backup 30        # Set expected duration
/ccbell:cron sound complete <sound>
/ccbell:cron sound fail <sound>
/ccbell:cron test                      # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Job Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Timeout Sounds: Yes

Watched Jobs: 4
Watched Users: 2

Recent Job Executions:

[1] backup (root)
    Schedule: 0 2 * * *
    Last Run: 2 hours ago
    Status: COMPLETED
    Duration: 15 min
    Sound: bundled:cron-backup

[2] cleanup (admin)
    Schedule: 0 4 * * *
    Last Run: 6 hours ago
    Status: COMPLETED
    Duration: 5 min
    Sound: bundled:cron-cleanup

[3] sync-data (root)
    Schedule: */15 * * * *
    Last Run: 10 min ago
    Status: RUNNING
    Duration: 25 min (expected: 10)
    Sound: bundled:cron-sync

[4] health-check (root)
    Schedule: * * * * *
    Last Run: 1 min ago
    Status: FAILED
    Exit Code: 1
    Error: Connection refused
    Sound: bundled:cron-health

Recent Events:
  [1] health-check: Job Failed (1 min ago)
       Exit code: 1
  [2] sync-data: Long Running (5 min ago)
       25 min > 10 min expected
  [3] backup: Job Completed (2 hours ago)
       Duration: 15 min

Cron Statistics:
  Jobs Today: 24
  Completed: 22
  Failed: 2
  Timeouts: 0

Sound Settings:
  Complete: bundled:cron-complete
  Fail: bundled:cron-fail
  Start: bundled:cron-start
  Timeout: bundled:cron-timeout

[Configure] [Add Job] [Test All]
```

---

## Audio Player Compatibility

Cron monitoring doesn't play sounds directly:
- Monitoring feature using grep/cut on syslog/cron logs
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
    lastCheckTime   time.Time
}

type CronJobInfo struct {
    Name       string
    User       string
    Schedule   string
    LastRun    time.Time
    Status     string // "running", "completed", "failed", "unknown"
    Duration   int    // minutes
    ExitCode   int
    Error      string
    PID        int
}

func (m *CronJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.jobState = make(map[string]*CronJobInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
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
    // Check cron logs for job executions
    m.parseCronLogs()

    // Check for running jobs that exceed expected duration
    m.checkLongRunningJobs()
}

func (m *CronJobMonitor) parseCronLogs() {
    // Read recent cron entries from syslog
    since := m.lastCheckTime.Format("2006-01-02 15:04:05")

    cmd := exec.Command("journalctl", "-u", "cron", "-t", "cron", "--since", since, "--no-pager", "-n", "50")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to grep /var/log/syslog
        cmd = exec.Command("grep", fmt.Sprintf("CRON.*%s", since[:10]), "/var/log/syslog")
        output, _ = cmd.Output()
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        m.parseCronLine(line)
    }

    m.lastCheckTime = time.Now()
}

func (m *CronJobMonitor) parseCronLine(line string) {
    // Parse: "Oct 15 02:00:01 host CRON[1234]: (root) CMD (backup.sh)"
    re := regexp.MustCompile(`CRON\[(\d+)\]: \(([^)]+)\) CMD \(([^)]+)\)`)
    match := re.FindStringSubmatch(line)
    if match == nil {
        return
    }

    pid, _ := strconv.Atoi(match[1])
    user := match[2]
    cmd := match[3]

    jobName := m.extractJobName(cmd)
    if !m.shouldWatchJob(jobName) {
        return
    }

    id := fmt.Sprintf("%s-%s", user, jobName)

    // Check if this is a new run
    lastJob := m.jobState[id]
    if lastJob != nil && lastJob.LastRun.After(m.lastCheckTime.Add(-time.Duration(m.config.PollInterval)*time.Second)) {
        return
    }

    m.jobState[id] = &CronJobInfo{
        Name:    jobName,
        User:    user,
        PID:     pid,
        LastRun: time.Now(),
        Status:  "running",
    }

    if m.config.SoundOnStart {
        key := fmt.Sprintf("start:%s", id)
        if m.shouldAlert(key, 1*time.Minute) {
            sound := m.config.Sounds["start"]
            if sound != "" {
                m.player.Play(sound, 0.3)
            }
        }
    }
}

func (m *CronJobMonitor) checkLongRunningJobs() {
    for id, job := range m.jobState {
        if job.Status != "running" {
            continue
        }

        duration := int(time.Since(job.LastRun).Minutes())
        expected := m.config.ExpectedDuration[job.Name]

        if expected > 0 && duration > expected {
            key := fmt.Sprintf("timeout:%s", id)
            if m.shouldAlert(key, 30*time.Minute) {
                if m.config.SoundOnTimeout {
                    sound := m.config.Sounds["timeout"]
                    if sound != "" {
                        m.player.Play(sound, 0.5)
                    }
                }
            }
        }

        job.Duration = duration
    }
}

func (m *CronJobMonitor) extractJobName(cmd string) string {
    // Extract job name from command
    parts := strings.Fields(cmd)
    if len(parts) > 0 {
        base := filepath.Base(parts[0])
        // Remove extension
        return strings.TrimSuffix(base, filepath.Ext(base))
    }
    return cmd
}

func (m *CronJobMonitor) shouldWatchJob(name string) bool {
    if len(m.config.WatchJobs) == 0 {
        return true
    }

    for _, j := range m.config.WatchJobs {
        if j == "*" || name == j || strings.Contains(name, j) {
            return true
        }
    }

    return false
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
| journalctl | System Tool | Free | Systemd logs |
| grep | System Tool | Free | Log filtering |
| cut | System Tool | Free | Text processing |

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
| macOS | Supported | Uses grep on system logs |
| Linux | Supported | Uses journalctl, cron logs |
