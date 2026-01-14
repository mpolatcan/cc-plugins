# Feature: Sound Event Cron Schedule Monitor

Play sounds for cron job execution, missed schedules, and job failures.

## Summary

Monitor cron schedules for job execution, missed runs, and failures, playing sounds for cron events.

## Motivation

- Scheduled task awareness
- Missed job detection
- Job failure alerts
- Backup completion alerts
- Automation feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Cron Schedule Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Started | Cron job began execution | backup |
| Job Completed | Finished successfully | done |
| Job Failed | Error occurred | exit 1 |
| Missed Schedule | Didn't run on time | skipped |
| Long Running | Exceeded expected time | > 1 hour |
| No Cron | No crontab found | empty |

### Configuration

```go
type CronScheduleMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchJobs         []string          `json:"watch_jobs"` // "backup", "*"
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnMissed     bool              `json:"sound_on_missed"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
    MaxRuntime        int               `json:"max_runtime_minutes"` // 60 default
}
```

### Commands

```bash
/ccbell:cron status                  # Show cron status
/ccbell:cron add backup              # Add job to watch
/ccbell:cron remove backup
/ccbell:cron sound start <sound>
/ccbell:cron sound complete <sound>
/ccbell:cron test                    # Test cron sounds
```

### Output

```
$ ccbell:cron status

=== Sound Event Cron Schedule Monitor ===

Status: Enabled
Start Sounds: Yes
Complete Sounds: Yes
Fail Sounds: Yes
Missed Sounds: Yes

Watched Jobs: 5

Scheduled Jobs:

[1] backup
    Schedule: 0 2 * * *
    Last Run: Jan 14, 2026 02:00:00
    Status: COMPLETED
    Duration: 45 min
    Exit Code: 0
    Next Run: Jan 15, 2026 02:00:00
    Sound: bundled:cron-backup

[2] system-update
    Schedule: 0 3 * * 0
    Last Run: Jan 12, 2026 03:00:00
    Status: COMPLETED
    Duration: 30 min
    Exit Code: 0
    Next Run: Jan 19, 2026 03:00:00
    Sound: bundled:cron-update

[3] database-cleanup
    Schedule: 0 4 * * *
    Last Run: Jan 14, 2026 04:00:00
    Status: COMPLETED
    Duration: 5 min
    Exit Code: 0
    Next Run: Jan 15, 2026 04:00:00
    Sound: bundled:cron-db

[4] log-rotate
    Schedule: 0 0 * * *
    Last Run: Jan 14, 2026 00:00:00
    Status: FAILED
    Duration: 2 min
    Exit Code: 1 *** FAILED ***
    Error: Permission denied
    Sound: bundled:cron-log *** FAILED ***

[5] health-check
    Schedule: * * * * *
    Last Run: Jan 14, 2026 08:31:00
    Status: RUNNING
    Duration: 30 sec
    Next Run: Jan 14, 2026 08:32:00
    Sound: bundled:cron-health

Missed Jobs: 0

Recent Events:
  [1] log-rotate: Job Failed (1 hour ago)
       Exit code: 1 (Permission denied)
  [2] backup: Job Completed (6 hours ago)
       45 min duration
  [3] health-check: Job Started (30 seconds ago)
       Running every minute

Cron Statistics:
  Total Jobs: 5
  Completed Today: 20
  Failed Today: 1
  Missed: 0

Sound Settings:
  Start: bundled:cron-start
  Complete: bundled:cron-complete
  Fail: bundled:cron-fail
  Missed: bundled:cron-missed

[Configure] [Add Job] [Test All]
```

---

## Audio Player Compatibility

Cron monitoring doesn't play sounds directly:
- Monitoring feature using crontab, ps, at
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Cron Schedule Monitor

```go
type CronScheduleMonitor struct {
    config          *CronScheduleMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    jobState        map[string]*CronJobInfo
    lastEventTime   map[string]time.Time
}

type CronJobInfo struct {
    Name       string
    Schedule   string
    Command    string
    Status     string // "pending", "running", "completed", "failed", "missed"
    LastRun    time.Time
    NextRun    time.Time
    Duration   time.Duration
    ExitCode   int
    Error      string
    PID        int
}

func (m *CronScheduleMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.jobState = make(map[string]*CronJobInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *CronScheduleMonitor) monitor() {
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

func (m *CronScheduleMonitor) snapshotJobState() {
    m.checkJobState()
}

func (m *CronScheduleMonitor) checkJobState() {
    jobs := m.listCronJobs()

    for _, job := range jobs {
        if !m.shouldWatchJob(job.Name) {
            continue
        }
        m.processJobStatus(job)
    }
}

func (m *CronScheduleMonitor) listCronJobs() []*CronJobInfo {
    var jobs []*CronJobInfo

    // Get user crontab
    cmd := exec.Command("crontab", "-l")
    output, err := cmd.Output()

    if err != nil {
        // No crontab or error
        return jobs
    }

    lines := strings.Split(string(output), "\n")
    currentJob := ""

    for _, line := range lines {
        line = strings.TrimSpace(line)

        // Skip comments and empty lines
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }

        // Parse crontab line
        // Format: minute hour day month weekday command
        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        schedule := strings.Join(parts[:5], " ")
        command := strings.Join(parts[5:], " ")

        // Extract job name from command if possible
        name := m.extractJobName(command)
        if name == "" {
            name = fmt.Sprintf("job-%d", len(jobs)+1)
        }

        job := &CronJobInfo{
            Name:     name,
            Schedule: schedule,
            Command:  command,
            Status:   "pending",
        }

        // Calculate next run time
        job.NextRun = m.calculateNextRun(schedule)

        jobs = append(jobs, job)
    }

    // Also check for running cron jobs
    runningJobs := m.getRunningCronJobs()
    for _, running := range runningJobs {
        for _, job := range jobs {
            if strings.Contains(job.Command, running.Command) ||
               job.Name == running.Name {
                job.Status = "running"
                job.PID = running.PID
                job.LastRun = running.LastRun
                break
            }
        }
    }

    return jobs
}

func (m *CronScheduleMonitor) extractJobName(command string) string {
    // Try to extract name from common patterns
    // e.g., "/usr/local/bin/backup.sh" -> "backup"
    // e.g., "python /app/main.py" -> "main"

    parts := strings.Fields(command)
    if len(parts) == 0 {
        return ""
    }

    // Check for script paths
    for _, part := range parts {
        if strings.HasPrefix(part, "/") {
            base := filepath.Base(part)
            ext := filepath.Ext(base)
            name := strings.TrimSuffix(base, ext)
            if name != "" && name != "sh" && name != "py" && name != "bash" {
                return name
            }
        }
    }

    return ""
}

func (m *CronScheduleMonitor) getRunningCronJobs() []*CronJobInfo {
    var jobs []*CronJobInfo

    // Get all running processes
    cmd := exec.Command("ps", "-eo", "pid,etime,comm,args")
    output, err := cmd.Output()
    if err != nil {
        return jobs
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" || strings.HasPrefix(line, "PID") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        pid, _ := strconv.Atoi(parts[0])
        elapsed := parts[1]
        command := strings.Join(parts[2:], " ")

        // Skip system processes
        if m.isSystemProcess(command) {
            continue
        }

        job := &CronJobInfo{
            PID:     pid,
            Command: command,
            Status:  "running",
        }

        // Parse elapsed time (format: [[dd-]hh:]mm:ss)
        job.LastRun = m.parseElapsedTime(elapsed)

        jobs = append(jobs, job)
    }

    return jobs
}

func (m *CronScheduleMonitor) isSystemProcess(command string) bool {
    systemProcs := []string{"systemd", "cron", "atd", "bash", "sh", "ps", "grep", "awk"}
    for _, sys := range systemProcs {
        if strings.HasPrefix(command, sys) {
            return true
        }
    }
    return false
}

func (m *CronScheduleMonitor) parseElapsedTime(elapsed string) time.Time {
    // Parse elapsed time format: [[dd-]hh:]mm:ss or [dd:]hh:mm:ss
    now := time.Now()

    parts := strings.Split(elapsed, ":")
    if len(parts) < 3 {
        return now
    }

    var duration time.Duration

    if len(parts) == 3 {
        // mm:ss or hh:mm:ss
        seconds, _ := strconv.Atoi(parts[len(parts)-1])
        minutes, _ := strconv.Atoi(parts[len(parts)-2])

        duration = time.Duration(minutes)*time.Minute + time.Duration(seconds)*time.Second

        if len(parts) == 3 {
            hours, _ := strconv.Atoi(parts[0])
            duration += time.Duration(hours) * time.Hour
        }
    } else if len(parts) == 4 {
        // dd-hh:mm:ss
        days, _ := strconv.Atoi(parts[0])
        hours, _ := strconv.Atoi(parts[1])
        minutes, _ := strconv.Atoi(parts[2])
        seconds, _ := strconv.Atoi(parts[3])

        duration = time.Duration(days)*24*time.Hour +
                   time.Duration(hours)*time.Hour +
                   time.Duration(minutes)*time.Minute +
                   time.Duration(seconds)*time.Second
    }

    return now.Add(-duration)
}

func (m *CronScheduleMonitor) calculateNextRun(schedule string) time.Time {
    // Simple next run calculation for common schedules
    // A full implementation would use a cron parser library
    now := time.Now()

    parts := strings.Fields(schedule)
    if len(parts) != 5 {
        return now
    }

    minute, _ := strconv.Atoi(parts[0])
    hour, _ := strconv.Atoi(parts[1])
    day, _ := strconv.Atoi(parts[2])
    month, _ := strconv.Atoi(parts[3])
    weekday, _ := strconv.Atoi(parts[4])

    next := now.Truncate(time.Minute)

    // Handle wildcard and ranges
    if minute == 0 && hour == 0 && day == 0 && month == 0 && weekday == 0 {
        return next
    }

    // This is a simplified calculation
    // A production implementation should use a proper cron library
    return next.Add(time.Hour)
}

func (m *CronScheduleMonitor) processJobStatus(job *CronJobInfo) {
    lastInfo := m.jobState[job.Name]

    if lastInfo == nil {
        m.jobState[job.Name] = job
        return
    }

    // Check for status transitions
    if lastInfo.Status == "pending" && job.Status == "running" {
        if m.config.SoundOnStart {
            m.onJobStarted(job)
        }
    }

    if lastInfo.Status == "running" && job.Status == "pending" {
        // Job completed - check exit code if available
        if lastInfo.ExitCode != 0 {
            if m.config.SoundOnFail {
                m.onJobFailed(lastInfo)
            }
        } else {
            if m.config.SoundOnComplete {
                m.onJobCompleted(lastInfo)
            }
        }
    }

    // Check for missed jobs
    if time.Since(job.NextRun) > 0 && job.Status == "pending" {
        if lastInfo.Status == "pending" {
            m.onJobMissed(job)
        }
    }

    // Check for long-running jobs
    if job.Status == "running" {
        runtime := time.Since(job.LastRun)
        if runtime > time.Duration(m.config.MaxRuntime)*time.Minute {
            // Job is taking too long
        }
    }

    m.jobState[job.Name] = job
}

func (m *CronScheduleMonitor) shouldWatchJob(name string) bool {
    if len(m.config.WatchJobs) == 0 {
        return true
    }

    for _, j := range m.config.WatchJobs {
        if j == "*" || name == j || strings.Contains(strings.ToLower(name), strings.ToLower(j)) {
            return true
        }
    }

    return false
}

func (m *CronScheduleMonitor) onJobStarted(job *CronJobInfo) {
    key := fmt.Sprintf("start:%s", job.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *CronScheduleMonitor) onJobCompleted(job *CronJobInfo) {
    key := fmt.Sprintf("complete:%s", job.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *CronScheduleMonitor) onJobFailed(job *CronJobInfo) {
    key := fmt.Sprintf("fail:%s", job.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CronScheduleMonitor) onJobMissed(job *CronJobInfo) {
    if !m.config.SoundOnMissed {
        return
    }

    key := fmt.Sprintf("missed:%s", job.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["missed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *CronScheduleMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| at | System Tool | Free | Job scheduling (at command) |

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
| macOS | Supported | Uses crontab, ps |
| Linux | Supported | Uses crontab, ps |
