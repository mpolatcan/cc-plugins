# Feature: Sound Event Cron Job Monitor

Play sounds for cron job completion, failures, and missed schedules.

## Summary

Monitor scheduled cron jobs for execution status, failures, and timing issues, playing sounds for cron job events.

## Motivation

- Job awareness
- Failure detection
- Schedule adherence
- Automation feedback
- Job completion confirmation

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
| Job Completed | Successful execution | exit 0 |
| Job Failed | Execution failed | exit 1 |
| Job Started | Execution began | started |
| Job Missed | Schedule missed | missed |
| Job Long Running | Taking too long | > threshold |
| Job Dependency | Failed dependency | dependency |

### Configuration

```go
type CronJobMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchJobs       []string          `json:"watch_jobs"` // cron names or "*" for all
    LongRunThreshold int              `json:"long_run_threshold_min"` // 60 default
    SoundOnComplete bool              `json:"sound_on_complete"`
    SoundOnFailed   bool              `json:"sound_on_failed"`
    SoundOnStarted  bool              `json:"sound_on_started"`
    SoundOnMissed   bool              `json:"sound_on_missed"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:cron status                 # Show cron job status
/ccbell:cron add "backup"           # Add cron job to watch
/ccbell:cron sound complete <sound>
/ccbell:cron test                   # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Job Monitor ===

Status: Enabled
Long Running Threshold: 60 min

Cron Job Status:

[1] backup (0 2 * * *)
    Status: COMPLETED
    Last Run: Jan 14 02:00
    Duration: 15m
    Exit Code: 0
    Next Run: Jan 15 02:00
    Sound: bundled:cron-backup

[2] cleanup (0 3 * * 0)
    Status: FAILED *** FAILED ***
    Last Run: Jan 14 03:00
    Duration: 5m
    Exit Code: 1
    Error: rm: cannot remove
    Sound: bundled:cron-cleanup *** FAILED ***

[3] sync (*/5 * * * *)
    Status: RUNNING *** RUNNING ***
    Started: Jan 14 10:00
    Duration: 8m
    Expected: 5m
    Sound: bundled:cron-sync *** WARNING ***

[4] reports (0 8 1 * *)
    Status: SCHEDULED
    Last Run: Jan 1 08:00
    Next Run: Feb 1 08:00
    Sound: bundled:cron-reports

Recent Events:

[1] cleanup: Job Failed (5 min ago)
       Exit code 1
       Sound: bundled:cron-failed
  [2] sync: Long Running (10 min ago)
       8m > 5m threshold
       Sound: bundled:cron-long
  [3] backup: Job Completed (8 hours ago)
       Duration: 15m
       Sound: bundled:cron-complete

Cron Job Statistics:
  Total Jobs: 4
  Completed Today: 2
  Failed Today: 1
  Running: 1

Sound Settings:
  Complete: bundled:cron-complete
  Failed: bundled:cron-failed
  Started: bundled:cron-started
  Missed: bundled:cron-missed

[Configure] [Add Job] [Test All]
```

---

## Audio Player Compatibility

Cron job monitoring doesn't play sounds directly:
- Monitoring feature using crontab, ps, logs
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Cron Job Monitor

```go
type CronJobMonitor struct {
    config        *CronJobMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    jobState      map[string]*CronJobInfo
    lastEventTime map[string]time.Time
}

type CronJobInfo struct {
    Name         string
    Schedule     string
    Status       string // "scheduled", "running", "completed", "failed", "missed"
    LastRun      time.Time
    Duration     time.Duration
    ExitCode     int
    Output       string
    PID          int
}

func (m *CronJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.jobState = make(map[string]*CronJobInfo)
    m.lastEventTime = make(map[string]time.Time)
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
    m.checkJobState()
}

func (m *CronJobMonitor) checkJobState() {
    for _, jobName := range m.config.WatchJobs {
        info := m.getJobInfo(jobName)
        if info != nil {
            m.processJobStatus(info)
        }
    }
}

func (m *CronJobMonitor) getJobInfo(jobName string) *CronJobInfo {
    info := &CronJobInfo{
        Name:     jobName,
        Schedule: m.getSchedule(jobName),
    }

    // Check if job is currently running
    info.PID = m.getJobPID(jobName)
    if info.PID > 0 {
        info.Status = "running"
        info.Duration = time.Since(m.getJobStartTime(info.PID))
        return info
    }

    // Check last run status from logs
    lastRunInfo := m.getLastRunInfo(jobName)
    if lastRunInfo != nil {
        info.LastRun = lastRunInfo.LastRun
        info.Status = lastRunInfo.Status
        info.ExitCode = lastRunInfo.ExitCode
        info.Duration = lastRunInfo.Duration
        return info
    }

    info.Status = "scheduled"
    return info
}

func (m *CronJobMonitor) getSchedule(jobName string) string {
    cmd := exec.Command("crontab", "-l")
    output, err := cmd.Output()
    if err != nil {
        return ""
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, jobName) {
            parts := strings.Fields(line)
            if len(parts) >= 5 {
                return strings.Join(parts[0:5], " ")
            }
        }
    }
    return ""
}

func (m *CronJobMonitor) getJobPID(jobName string) int {
    // Look for running cron job processes
    cmd := exec.Command("ps", "aux")
    output, _ := cmd.Output()

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, jobName) && !strings.Contains(line, "grep") {
            fields := strings.Fields(line)
            if len(fields) >= 2 {
                pid, _ := strconv.Atoi(fields[1])
                return pid
            }
        }
    }
    return 0
}

func (m *CronJobMonitor) getJobStartTime(pid int) time.Time {
    cmd := exec.Command("ps", "-o", "lstart=", "-p", strconv.Itoa(pid))
    output, err := cmd.Output()
    if err != nil {
        return time.Now()
    }

    t, _ := time.Parse("Mon Jan 2 15:04:05 2006", strings.TrimSpace(string(output)))
    return t
}

func (m *CronJobMonitor) getLastRunInfo(jobName string) *CronJobInfo {
    info := &CronJobInfo{
        Name: jobName,
    }

    // Check syslog for cron execution
    cmd := exec.Command("grep", fmt.Sprintf("CRON.*%s", jobName), "/var/log/syslog")
    output, err := cmd.Output()
    if err != nil {
        // Try alternative log locations
        cmd = exec.Command("journalctl", "-u", "cron", "--since=-24h")
        output, err = cmd.Output()
    }

    if err == nil {
        lines := strings.Split(string(output), "\n")
        for i := len(lines) - 1; i >= 0; i-- {
            line := lines[i]
            if strings.Contains(line, jobName) && strings.Contains(line, "CMD") {
                // Found execution
                info.LastRun = m.parseLogTime(line)

                // Check for exit status in subsequent lines
                if i+1 < len(lines) {
                    nextLine := lines[i+1]
                    if strings.Contains(nextLine, "CRON") {
                        info.Status = "completed"
                        return info
                    }
                }

                // Look for error indicators
                if strings.Contains(strings.ToLower(line), "error") ||
                   strings.Contains(strings.ToLower(line), "failed") {
                    info.Status = "failed"
                    info.ExitCode = 1
                    return info
                }

                info.Status = "completed"
                info.ExitCode = 0
                return info
            }
        }
    }

    // Check cron log for exit codes
    logPath := "/var/log/cron.log"
    if _, err := os.Stat(logPath); err == nil {
        data, _ := os.ReadFile(logPath)
        lines := strings.Split(string(data), "\n")
        for i := len(lines) - 1; i >= 0; i-- {
            line := lines[i]
            if strings.Contains(line, jobName) {
                info.LastRun = m.parseLogTime(line)
                if strings.Contains(line, "(exit") {
                    exitRe := regexp.MustEach(`exit (\d+)`)
                    matches := exitRe.FindStringSubmatch(line)
                    if len(matches) >= 2 {
                        info.ExitCode, _ = strconv.Atoi(matches[1])
                        if info.ExitCode == 0 {
                            info.Status = "completed"
                        } else {
                            info.Status = "failed"
                        }
                        return info
                    }
                }
            }
        }
    }

    return nil
}

func (m *CronJobMonitor) parseLogTime(line string) time.Time {
    // Try to parse timestamp from various log formats
    formats := []string{
        "Jan 14 10:00:00",
        "2026-01-14T10:00:00",
        "06/01/14 10:00:00",
    }

    for _, format := range formats {
        if t, err := time.Parse(format, strings.Fields(line)[0]); err == nil {
            return t
        }
    }

    return time.Now()
}

func (m *CronJobMonitor) processJobStatus(info *CronJobInfo) {
    lastInfo := m.jobState[info.Name]

    if lastInfo == nil {
        m.jobState[info.Name] = info
        if info.Status == "running" && m.config.SoundOnStarted {
            m.onJobStarted(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "completed":
            if lastInfo.Status == "running" {
                if m.config.SoundOnComplete {
                    m.onJobCompleted(info)
                }
            }
        case "failed":
            if lastInfo.Status == "running" || lastInfo.Status == "scheduled" {
                if m.config.SoundOnFailed {
                    m.onJobFailed(info)
                }
            }
        case "running":
            if lastInfo.Status == "scheduled" || lastInfo.Status == "completed" {
                if m.config.SoundOnStarted {
                    m.onJobStarted(info)
                }
            }
        case "missed":
            if m.config.SoundOnMissed {
                m.onJobMissed(info)
            }
        }
    }

    // Check for long running jobs
    if info.Status == "running" && info.Duration > time.Duration(m.config.LongRunThreshold)*time.Minute {
        if m.shouldAlert(info.Name+"long", 10*time.Minute) {
            m.onLongRunningJob(info)
        }
    }

    m.jobState[info.Name] = info
}

func (m *CronJobMonitor) onJobCompleted(info *CronJobInfo) {
    key := fmt.Sprintf("complete:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CronJobMonitor) onJobFailed(info *CronJobInfo) {
    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CronJobMonitor) onJobStarted(info *CronJobInfo) {
    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *CronJobMonitor) onJobMissed(info *CronJobInfo) {
    sound := m.config.Sounds["missed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *CronJobMonitor) onLongRunningJob(info *CronJobInfo) {
    sound := m.config.Sounds["long"]
    if sound != "" {
        m.player.Play(sound, 0.4)
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
| crontab | System Tool | Free | Cron table management |
| ps | System Tool | Free | Process status |
| grep | System Tool | Free | Log searching |

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
| macOS | Supported | Uses crontab, syslog |
| Linux | Supported | Uses crontab, journalctl, syslog |
