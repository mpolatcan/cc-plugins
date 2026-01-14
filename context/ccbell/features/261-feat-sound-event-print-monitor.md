# Feature: Sound Event Print Monitor

Play sounds for print job status and printer events.

## Summary

Monitor print jobs, printer status, and printing completion, playing sounds for print events.

## Motivation

- Print completion alerts
- Printer offline warnings
- Job queue feedback
- Ink level warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Print Events

| Event | Description | Example |
|-------|-------------|---------|
| Print Started | Job sent to printer | Document printing |
| Print Complete | Job finished | 5 pages printed |
| Print Failed | Job errored | Paper jam |
| Printer Offline | Printer disconnected | Printer not found |
| Low Ink | Ink below threshold | Cyan < 20% |

### Configuration

```go
type PrintMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPrinters    []string          `json:"watch_printers"`
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnComplete  bool              `json:"sound_on_complete"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    SoundOnOffline   bool              `json:"sound_on_offline"`
    InkThreshold     int               `json:"ink_threshold_percent"` // 20 default
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}

type PrintEvent struct {
    PrinterName string
    JobID       int
    EventType   string // "started", "complete", "failed", "offline"
    PagesPrinted int
    JobName     string
}
```

### Commands

```bash
/ccbell:print status                # Show print status
/ccbell:print add "HP LaserJet"     # Add printer to watch
/ccbell:print remove "HP LaserJet"
/ccbell:print sound complete <sound>
/ccbell:print sound failed <sound>
/ccbell:print test                  # Test print sounds
```

### Output

```
$ ccbell:print status

=== Sound Event Print Monitor ===

Status: Enabled
Complete Sounds: Yes
Fail Sounds: Yes

Current Jobs: 1

[1] HP LaserJet Pro
    Status: Printing
    Job: "document.pdf" (5/10 pages)
    Started: 2 min ago
    Sound: bundled:stop

Printers: 2

[1] HP LaserJet Pro
    Status: Online
    Ink Levels: BK: 45%, C: 32%, M: 28%, Y: 55%
    Sound: bundled:stop

[2] Canon Pixma
    Status: Offline
    Last Seen: 1 hour ago
    Sound: bundled:stop

Recent Events:
  [1] document.pdf: Print Complete (1 hour ago)
       10 pages printed
  [2] HP LaserJet Pro: Offline (2 hours ago)
  [3] report.docx: Print Failed (3 hours ago)
       Paper jam

Sound Settings:
  Started: bundled:stop
  Complete: bundled:stop
  Failed: bundled:stop
  Offline: bundled:stop

[Configure] [Add Printer] [Test All]
```

---

## Audio Player Compatibility

Print monitoring doesn't play sounds directly:
- Monitoring feature using print system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Print Monitor

```go
type PrintMonitor struct {
    config         *PrintMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    printerState   map[string]*PrinterStatus
    activeJobs     map[int]*PrintJob
}

type PrinterStatus struct {
    Name        string
    Online      bool
    InkLevels   map[string]int // color -> percentage
    LastSeen    time.Time
}

type PrintJob struct {
    ID           int
    PrinterName  string
    DocumentName string
    PagesTotal   int
    PagesPrinted int
    StartTime    time.Time
}
```

```go
func (m *PrintMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.printerState = make(map[string]*PrinterStatus)
    m.activeJobs = make(map[int]*PrintJob)
    go m.monitor()
}

func (m *PrintMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkPrinters()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PrintMonitor) checkPrinters() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinPrinters()
    } else {
        m.checkLinuxPrinters()
    }
}

func (m *PrintMonitor) checkDarwinPrinters() {
    // Use lpstat to get printer status
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "printer ") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                printerName := parts[1]
                status := m.getPrinterStatus(printerName)
                m.evaluatePrinter(printerName, status)
            }
        }
    }

    // Check active jobs
    m.checkPrintJobs()
}

func (m *PrintMonitor) checkLinuxPrinters() {
    // Use lpstat or cups
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()
    if err != nil {
        // Try lpstat alternative
        cmd = exec.Command("lpstat", "-t")
        output, err = cmd.Output()
        if err != nil {
            return
        }
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "printer ") || strings.HasPrefix(line, "device for ") {
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                printerName := parts[1]
                if !strings.HasPrefix(printerName, "device") {
                    status := m.getPrinterStatus(printerName)
                    m.evaluatePrinter(printerName, status)
                }
            }
        }
    }

    m.checkPrintJobs()
}

func (m *PrintMonitor) getPrinterStatus(printerName string) *PrinterStatus {
    status := &PrinterStatus{
        Name:      printerName,
        InkLevels: make(map[string]int),
        LastSeen:  time.Now(),
    }

    // Get printer state
    cmd := exec.Command("lpstat", "-p", printerName, "-W", "not-completed")
    output, err := cmd.Output()

    if err == nil && len(output) > 0 {
        status.Online = true
    } else {
        status.Online = false
    }

    return status
}

func (m *PrintMonitor) checkPrintJobs() {
    cmd := exec.Command("lpstat", "-o")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse job info: "printer-123  user  size  date  time  title"
        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        // Extract job ID from queue-name-number format
        jobQueue := parts[0]
        parts2 := strings.Split(jobQueue, "-")
        if len(parts2) < 2 {
            continue
        }

        jobID, err := strconv.Atoi(parts2[len(parts2)-1])
        if err != nil {
            continue
        }

        printerName := strings.Join(parts2[:len(parts2)-1], "-")

        job := &PrintJob{
            ID:          jobID,
            PrinterName: printerName,
            DocumentName: parts[4],
            StartTime:   time.Now(),
        }

        m.evaluateJob(job)
    }
}

func (m *PrintMonitor) evaluatePrinter(name string, status *PrinterStatus) {
    lastState := m.printerState[name]

    if lastState == nil {
        m.printerState[name] = status
        return
    }

    // Detect offline/online changes
    if lastState.Online && !status.Online {
        m.onPrinterOffline(name)
    } else if !lastState.Online && status.Online {
        m.onPrinterOnline(name)
    }

    m.printerState[name] = status
}

func (m *PrintMonitor) evaluateJob(job *PrintJob) {
    if m.activeJobs[job.ID] == nil {
        // New job
        m.activeJobs[job.ID] = job
        m.onPrintStarted(job)
    }
}

func (m *PrintMonitor) onPrintStarted(job *PrintJob) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *PrintMonitor) onPrintComplete(job *PrintJob) {
    if !m.config.SoundOnComplete {
        return
    }

    delete(m.activeJobs, job.ID)

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *PrintMonitor) onPrintFailed(job *PrintJob, reason string) {
    if !m.config.SoundOnFail {
        return
    }

    delete(m.activeJobs, job.ID)

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *PrintMonitor) onPrinterOffline(name string) {
    if !m.config.SoundOnOffline {
        return
    }

    sound := m.config.Sounds["offline"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *PrintMonitor) onPrinterOnline(name string) {
    sound := m.config.Sounds["online"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lpstat | System Tool | Free | CUPS print status |
| CUPS | Service | Free | Print system |

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
| macOS | Supported | Uses lpstat (CUPS) |
| Linux | Supported | Uses lpstat (CUPS) |
| Windows | Not Supported | ccbell only supports macOS/Linux |
