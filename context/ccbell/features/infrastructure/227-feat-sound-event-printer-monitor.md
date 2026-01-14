# Feature: Sound Event Printer Monitor

Play sounds for printer and print job events.

## Summary

Monitor printer status and print jobs, playing sounds for print completion, paper jams, low ink alerts, and printer offline events.

## Motivation

- Print job completion awareness
- Printer error alerts
- Low ink warnings
- Paper jam detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Printer Events

| Event | Description | Example |
|-------|-------------|---------|
| Print Started | Print job began | Document sent |
| Print Complete | Print job finished | All pages printed |
| Print Failed | Print job errored | Paper jam |
| Low Ink | Ink below threshold | < 20% remaining |
| Paper Jam | Paper stuck | Jam detected |
| Printer Offline | Printer disconnected | Network issue |

### Configuration

```go
type PrinterMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchPrinters []string          `json:"watch_printers"` // Printer names
    InkThresholds map[string]int    `json:"ink_thresholds"` // color -> percentage
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 30 default
}

type PrinterEvent struct {
    Printer    string
    JobName    string
    EventType  string // "started", "completed", "failed", "low_ink", "jam", "offline"
       Status Pages      int
     string
}
```

### Commands

```bash
/ccbell:printer status            # Show printer status
/ccbell:printer add "OfficePrinter"
/ccbell:printer remove "OfficePrinter"
/ccbell:printer ink_threshold 20
/ccbell:printer sound complete <sound>
/ccbell:printer sound failed <sound>
/ccbell:printer test              # Test printer sounds
```

### Output

```
$ ccbell:printer status

=== Sound Event Printer Monitor ===

Status: Enabled
Poll Interval: 30s

Monitored Printers: 2

[1] OfficePrinter
    Status: Online
    Jobs: 0 pending
    Ink Levels: C:45% M:32% Y:45% K:78%
    Status: OK
    Sound: bundled:stop
    [Edit] [Remove]

[2] HomePrinter
    Status: Offline
    Last Active: 2 days ago
    Status: OFFLINE
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] OfficePrinter: Print Complete (5 min ago)
       Document: "report.pdf" (12 pages)
  [2] HomePrinter: Printer Offline (1 day ago)
  [3] OfficePrinter: Low Cyan Ink (2 days ago)

Sound Settings:
  Complete: bundled:stop
  Failed: bundled:stop
  Low Ink: bundled:stop

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Printer monitoring doesn't play sounds directly:
- Monitoring feature using printer APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Printer Monitor

```go
type PrinterMonitor struct {
    config       *PrinterMonitorConfig
    player       *audio.Player
    running      bool
    stopCh       chan struct{}
    lastJobs     map[string]int
    lastInk      map[string]map[string]int
}

func (m *PrinterMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastJobs = make(map[string]int)
    m.lastInk = make(map[string]map[string]int)
    go m.monitor()
}

func (m *PrinterMonitor) monitor() {
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

func (m *PrinterMonitor) checkPrinters() {
    printers := m.getPrinters()

    for _, printer := range printers {
        if m.shouldWatch(printer) {
            m.checkPrinter(printer)
        }
    }
}

func (m *PrinterMonitor) getPrinters() []string {
    var printers []string

    if runtime.GOOS == "darwin" {
        printers = m.getMacOSPrinters()
    } else if runtime.GOOS == "linux" {
        printers = m.getLinuxPrinters()
    }

    return printers
}

func (m *PrinterMonitor) getMacOSPrinters() []string {
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    var printers []string
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "printer ") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                printers = append(printers, parts[1])
            }
        }
    }

    return printers
}

func (m *PrinterMonitor) getLinuxPrinters() []string {
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()
    if err != nil {
        // Try cups
        cmd = exec.Command("lpstat", "-a")
        output, _ = cmd.Output()
    }

    var printers []string
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.Fields(line)
        if len(parts) >= 1 {
            printers = append(printers, parts[0])
        }
    }

    return printers
}

func (m *PrinterMonitor) shouldWatch(printer string) bool {
    if len(m.config.WatchPrinters) == 0 {
        return true
    }

    for _, p := range m.config.WatchPrinters {
        if p == printer {
            return true
        }
    }

    return false
}

func (m *PrinterMonitor) checkPrinter(printer string) {
    status := m.getPrinterStatus(printer)
    jobs := m.getPrintJobs(printer)

    // Check for new jobs
    if len(jobs) > m.lastJobs[printer] {
        m.onPrintStarted(printer)
    }
    m.lastJobs[printer] = len(jobs)

    // Check printer status
    switch status.State {
    case "offline":
        m.onPrinterOffline(printer)
    case "error", "stopped":
        m.onPrinterError(printer, status.State)
    }

    // Check ink levels
    m.checkInkLevels(printer, status.InkLevels)
}

func (m *PrinterMonitor) getPrinterStatus(printer string) PrinterStatus {
    status := PrinterStatus{Name: printer}

    if runtime.GOOS == "darwin" {
        return m.getMacOSPrinterStatus(printer, status)
    }
    if runtime.GOOS == "linux" {
        return m.getLinuxPrinterStatus(printer, status)
    }

    return status
}

func (m *PrinterMonitor) getMacOSPrinterStatus(printer string, status PrinterStatus) PrinterStatus {
    cmd := exec.Command("lpstat", "-p", printer, "-v")
    output, err := cmd.Output()
    if err != nil {
        status.State = "unknown"
        return status
    }

    if strings.Contains(string(output), "idle") {
        status.State = "idle"
    } else if strings.Contains(string(output), "printing") {
        status.State = "printing"
    } else if strings.Contains(string(output), "offline") {
        status.State = "offline"
    }

    return status
}

func (m *PrinterMonitor) getLinuxPrinterStatus(printer string, status PrinterStatus) PrinterStatus {
    cmd := exec.Command("lpstat", "-W", "not-completed", "-p", printer)
    output, err := cmd.Output()
    if err != nil {
        status.State = "unknown"
        return status
    }

    if strings.Contains(string(output), "Warning") {
        status.State = "warning"
    } else if len(output) > 0 {
        status.State = "jobs"
    } else {
        status.State = "idle"
    }

    return status
}

func (m *PrinterMonitor) getPrintJobs(printer string) []PrintJob {
    var jobs []PrintJob

    cmd := exec.Command("lpstat", "-o", printer)
    output, err := cmd.Output()
    if err != nil {
        return jobs
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        job := PrintJob{Printer: printer}
        parts := strings.Fields(line)
        if len(parts) >= 4 {
            job.Name = parts[0]
            job.Pages, _ = strconv.Atoi(parts[2])
        }
        jobs = append(jobs, job)
    }

    return jobs
}

func (m *PrinterMonitor) checkInkLevels(printer string, inkLevels map[string]int) {
    lastInk := m.lastInk[printer]
    if lastInk == nil {
        lastInk = make(map[string]int)
    }

    for color, level := range inkLevels {
        lastLevel := lastInk[color]
        threshold := m.config.InkThresholds[color]
        if threshold == 0 {
            threshold = 20
        }

        if level <= threshold && lastLevel > threshold {
            m.onLowInk(printer, color, level)
        }
    }

    m.lastInk[printer] = inkLevels
}

func (m *PrinterMonitor) onPrintStarted(printer string) {
    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *PrinterMonitor) onPrintComplete(printer string) {
    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *PrinterMonitor) onPrintFailed(printer string) {
    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *PrinterMonitor) onPrinterOffline(printer string) {
    sound := m.config.Sounds["offline"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *PrinterMonitor) onPrinterError(printer string, errorType string) {
    sound := m.config.Sounds["error"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *PrinterMonitor) onLowInk(printer string, color string, level int) {
    sound := m.config.Sounds["low_ink"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

type PrinterStatus struct {
    Name      string
    State     string
    InkLevels map[string]int
}

type PrintJob struct {
    Printer string
    Name    string
    Pages   int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| lpstat | CUPS | Free | Printer status |
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
