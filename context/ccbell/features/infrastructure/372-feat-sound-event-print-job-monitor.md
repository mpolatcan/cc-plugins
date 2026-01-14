# Feature: Sound Event Print Job Monitor

Play sounds for print job completion, errors, and printer status changes.

## Summary

Monitor print jobs, printer status, and printing errors, playing sounds for print events.

## Motivation

- Print job awareness
- Completion feedback
- Error detection
- Printer status monitoring
- Print queue management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Print Job Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Completed | Print job finished | 10 pages printed |
| Job Failed | Print job failed | Paper jam |
| Job Canceled | Job was canceled | User canceled |
| Printer Offline | Printer disconnected | Printer down |
| Printer Ready | Printer ready | Ready to print |
| Low Ink | Ink level low | Cyan < 20% |

### Configuration

```go
type PrintJobMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPrinters     []string          `json:"watch_printers"` // "hp_laserjet", "*"
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"]
    SoundOnOffline    bool              `json:"sound_on_offline"]
    SoundOnLowInk     bool              `json:"sound_on_low_ink"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type PrintJobEvent struct {
    Printer    string
    JobID      int
    User       string
    Document   string
    Pages      int
    Status     string // "completed", "failed", "printing", "queued"
    InkLevel   int // percentage
    EventType  string // "complete", "fail", "offline", "low_ink"
}
```

### Commands

```bash
/ccbell:print status                  # Show print status
/ccbell:print add hp_laserjet         # Add printer to watch
/ccbell:print remove hp_laserjet
/ccbell:print sound complete <sound>
/ccbell:print sound fail <sound>
/ccbell:print test                    # Test print sounds
```

### Output

```
$ ccbell:print status

=== Sound Event Print Job Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes
Offline Sounds: Yes

Watched Printers: 2

[1] hp_laserjet (HP LaserJet Pro)
    Status: READY
    Jobs: 0
    Ink: 75%
    Sound: bundled:print-hp

[2] canon_pixma (Canon PIXMA)
    Status: PRINTING
    Jobs: 1
    Document: report.pdf
    Pages: 5/10
    Ink: 45%
    Sound: bundled:print-canon

Print Queue:
  [1] report.pdf (canon_pixma)
      User: admin
      Status: PRINTING
      Progress: 50%

Recent Events:
  [1] canon_pixma: Job Completed (5 min ago)
       Document: monthly_report.pdf (12 pages)
  [2] hp_laserjet: Low Ink Warning (1 hour ago)
       Cyan: 15%
  [3] canon_pixma: Job Failed (2 hours ago)
       Error: Paper jam

Print Statistics:
  Jobs Today: 25
  Completed: 23
  Failed: 2

Sound Settings:
  Complete: bundled:print-complete
  Fail: bundled:print-fail
  Offline: bundled:print-offline
  Low Ink: bundled:print-low-ink

[Configure] [Add Printer] [Test All]
```

---

## Audio Player Compatibility

Print monitoring doesn't play sounds directly:
- Monitoring feature using lpstat/cups
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Print Job Monitor

```go
type PrintJobMonitor struct {
    config          *PrintJobMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    printerState    map[string]*PrinterInfo
    jobState        map[int]*JobInfo
    lastEventTime   map[string]time.Time
}

type PrinterInfo struct {
    Name      string
    Status    string
    Jobs      int
    InkLevel  int
    Model     string
    LastCheck time.Time
}

type JobInfo struct {
    JobID     int
    Printer   string
    User      string
    Document  string
    Pages     int
    Status    string
    Submitted time.Time
}

func (m *PrintJobMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.printerState = make(map[string]*PrinterInfo)
    m.jobState = make(map[int]*JobInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *PrintJobMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotPrintState()

    for {
        select {
        case <-ticker.C:
            m.checkPrintState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PrintJobMonitor) snapshotPrintState() {
    m.checkPrintState()
}

func (m *PrintJobMonitor) checkPrintState() {
    // Get printer status
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentPrinters := m.parseLPStatOutput(string(output))

    // Get active jobs
    cmd = exec.Command("lpstat", "-W", "not-completed")
    jobOutput, _ := cmd.Output()
    currentJobs := m.parseJobsOutput(string(jobOutput))

    // Check for status changes
    for name, info := range currentPrinters {
        lastInfo := m.printerState[name]
        if lastInfo == nil {
            m.printerState[name] = info
            continue
        }

        if lastInfo.Status != info.Status {
            if info.Status == "idle" || info.Status == "ready" {
                m.onPrinterReady(name, info)
            } else if info.Status == "offline" || info.Status == "disabled" {
                m.onPrinterOffline(name, info)
            }
        }

        // Check ink levels
        if info.InkLevel < 20 && lastInfo.InkLevel >= 20 {
            m.onLowInk(name, info)
        }

        m.printerState[name] = info
    }

    // Check job changes
    for jobID, job := range currentJobs {
        lastJob, exists := m.jobState[jobID]
        if !exists {
            m.jobState[jobID] = job
            m.onJobStarted(job)
            continue
        }

        if lastJob.Status == "printing" && job.Status != "printing" {
            if job.Status == "completed" {
                m.onJobCompleted(job)
            } else if job.Status == "failed" {
                m.onJobFailed(job)
            }
        }

        m.jobState[jobID] = job
    }

    // Check for completed/canceled jobs
    for jobID, lastJob := range m.jobState {
        if _, exists := currentJobs[jobID]; !exists {
            if lastJob.Status == "printing" || lastJob.Status == "queued" {
                delete(m.jobState, jobID)
                if lastJob.Status == "printing" {
                    m.onJobCompleted(lastJob)
                }
            }
        }
    }
}

func (m *PrintJobMonitor) parseLPStatOutput(output string) map[string]*PrinterInfo {
    printers := make(map[string]*PrinterInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "printer") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                name := parts[1]
                status := "unknown"

                if strings.Contains(line, "is ready") {
                    status = "ready"
                } else if strings.Contains(line, "is idle") {
                    status = "idle"
                } else if strings.Contains(line, "disabled") {
                    status = "disabled"
                }

                if !m.shouldWatchPrinter(name) {
                    continue
                }

                printers[name] = &PrinterInfo{
                    Name:      name,
                    Status:    status,
                    LastCheck: time.Now(),
                }
            }
        }
    }

    return printers
}

func (m *PrintJobMonitor) parseJobsOutput(output string) map[int]*JobInfo {
    jobs := make(map[int]*JobInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Rank") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 5 {
            continue
        }

        jobID, _ := strconv.Atoi(parts[0])
        priority := parts[1]
        user := parts[2]
        size := parts[3]
        document := strings.Join(parts[4:], " ")

        jobs[jobID] = &JobInfo{
            JobID:    jobID,
            User:     user,
            Document: document,
            Status:   "queued",
        }
    }

    return jobs
}

func (m *PrintJobMonitor) shouldWatchPrinter(name string) bool {
    if len(m.config.WatchPrinters) == 0 {
        return true
    }

    for _, p := range m.config.WatchPrinters {
        if p == "*" || p == name {
            return true
        }
    }

    return false
}

func (m *PrintJobMonitor) onJobStarted(job *JobInfo) {
    // Optional: sound when job starts
}

func (m *PrintJobMonitor) onJobCompleted(job *JobInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%d", job.JobID)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PrintJobMonitor) onJobFailed(job *JobInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%d", job.JobID)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PrintJobMonitor) onPrinterOffline(name string, info *PrinterInfo) {
    if !m.config.SoundOnOffline {
        return
    }

    key := fmt.Sprintf("offline:%s", name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["offline"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PrintJobMonitor) onPrinterReady(name string, info *PrinterInfo) {
    // Optional: sound when printer comes back online
}

func (m *PrintJobMonitor) onLowInk(name string, info *PrinterInfo) {
    if !m.config.SoundOnLowInk {
        return
    }

    key := fmt.Sprintf("low_ink:%s", name)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["low_ink"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PrintJobMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| lpstat | System Tool | Free | CUPS status |
| CUPS | System Service | Free | Print system |

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
| macOS | Supported | Uses lpstat, CUPS |
| Linux | Supported | Uses lpstat, CUPS |
