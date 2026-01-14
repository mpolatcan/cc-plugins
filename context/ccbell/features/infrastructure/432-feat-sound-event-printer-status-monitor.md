# Feature: Sound Event Printer Status Monitor

Play sounds for printer status changes, job completion, and error events.

## Summary

Monitor printer status for job completion, paper jams, ink levels, and error states, playing sounds for printer events.

## Motivation

- Print job awareness
- Error detection
- Supply level alerts
- Job completion feedback
- Device status tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Printer Status Events

| Event | Description | Example |
|-------|-------------|---------|
| Job Completed | Print job done | page 1/1 |
| Job Failed | Print error | failed |
| Printer Offline | Printer down | offline |
| Low Ink | Ink below threshold | < 10% |
| Paper Jam | Jam detected | tray 1 |
| Printer Ready | Ready to print | idle |

### Configuration

```go
type PrinterStatusMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPrinters     []string          `json:"watch_printers"` // "HP_LaserJet", "*"
    InkWarning        int               `json:"ink_warning_percent"` // 10 default
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnOffline    bool              `json:"sound_on_offline"`
    SoundOnLowInk     bool              `json:"sound_on_low_ink"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:printer status              # Show printer status
/ccbell:printer add HP_LaserJet     # Add printer to watch
/ccbell:printer remove HP_LaserJet
/ccbell:printer sound complete <sound>
/ccbell:printer sound failed <sound>
/ccbell:printer test                # Test printer sounds
```

### Output

```
$ ccbell:printer status

=== Sound Event Printer Status Monitor ===

Status: Enabled
Ink Warning: 10%

Printer Status:

[1] HP_LaserJet_Pro
    Status: READY
    Model: HP LaserJet Pro M404n
    Jobs in Queue: 2
    Ink Level: 65%
    Paper: OK
    Sound: bundled:printer-hp

[2] Canon_PIXMA
    Status: PRINTING
    Model: Canon PIXMA TS9120
    Current Job: document.pdf (3/10 pages)
    Jobs in Queue: 0
    Ink Level: 12% *** WARNING ***
    Paper: OK
    Sound: bundled:printer-canon

[3] Brother_HL
    Status: OFFLINE *** OFFLINE ***
    Model: Brother HL-L2350DW
    Last Error: Paper Jam
    Jobs in Queue: 5
    Sound: bundled:printer-brother *** ERROR ***

Print Queue:

  [1] HP_LaserJet_Pro
       document.pdf (Waiting)
       Sound: bundled:printer-queue

  [2] HP_LaserJet_Pro
       report.pdf (Waiting)
       Sound: bundled:printer-queue

Recent Printer Events:
  [1] Canon_PIXMA: Ink Low (1 hour ago)
       12% remaining
       Sound: bundled:printer-low-ink
  [2] Brother_HL: Offline (3 hours ago)
       Paper jam detected
       Sound: bundled:printer-offline
  [3] HP_LaserJet_Pro: Job Completed (5 hours ago)
       Monthly report.pdf (5 pages)
       Sound: bundled:printer-complete

Printer Statistics:
  Total Printers: 3
  Ready: 1
  Printing: 1
  Offline: 1
  Jobs Today: 8

Sound Settings:
  Complete: bundled:printer-complete
  Failed: bundled:printer-failed
  Offline: bundled:printer-offline
  Low Ink: bundled:printer-low-ink

[Configure] [Add Printer] [Test All]
```

---

## Audio Player Compatibility

Printer monitoring doesn't play sounds directly:
- Monitoring feature using lpstat/cups
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Printer Status Monitor

```go
type PrinterStatusMonitor struct {
    config          *PrinterStatusMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    printerState    map[string]*PrinterInfo
    lastEventTime   map[string]time.Time
}

type PrinterInfo struct {
    Name        string
    Status      string // "ready", "printing", "offline", "error", "unknown"
    Model       string
    JobsInQueue int
    InkLevel    int
    PaperStatus string
    CurrentJob  string
    LastError   string
}

func (m *PrinterStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.printerState = make(map[string]*PrinterInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *PrinterStatusMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotPrinterState()

    for {
        select {
        case <-ticker.C:
            m.checkPrinterState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PrinterStatusMonitor) snapshotPrinterState() {
    m.checkPrinterState()
}

func (m *PrinterStatusMonitor) checkPrinterState() {
    printers := m.listPrinters()

    for _, printer := range printers {
        if !m.shouldWatchPrinter(printer.Name) {
            continue
        }
        m.processPrinterStatus(printer)
    }
}

func (m *PrinterStatusMonitor) listPrinters() []*PrinterInfo {
    var printers []*PrinterInfo

    // Use lpstat to list printers
    cmd := exec.Command("lpstat", "-p")
    output, err := cmd.Output()

    if err != nil {
        return printers
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        // Parse: printer HP_LaserJet_Pro is idle. enabled since Jan 14 2026
        re := regexp.MustEach(`printer (\S+) is (\S+)`)
        matches := re.FindStringSubmatch(line)

        if len(matches) >= 3 {
            printer := &PrinterInfo{
                Name:   matches[1],
                Status: m.parsePrinterStatus(matches[2]),
            }

            // Get printer details
            printer = m.getPrinterDetails(printer)
            printers = append(printers, printer)
        }
    }

    // Also check for printers in CUPS
    cmd = exec.Command("lpstat", "-a")
    output, err = cmd.Output()

    if err == nil {
        lines = strings.Split(string(output), "\n")
        knownPrinters := make(map[string]bool)
        for _, printer := range printers {
            knownPrinters[printer.Name] = true
        }

        for _, line := range lines {
            parts := strings.Fields(line)
            if len(parts) >= 1 {
                name := parts[0]
                if !knownPrinters[name] {
                    printer := &PrinterInfo{
                        Name:   name,
                        Status: "unknown",
                    }
                    printer = m.getPrinterDetails(printer)
                    printers = append(printers, printer)
                }
            }
        }
    }

    return printers
}

func (m *PrinterStatusMonitor) parsePrinterStatus(status string) string {
    status = strings.ToLower(status)

    switch status {
    case "idle", "ready":
        return "ready"
    case "printing":
        return "printing"
    case "disabled", "rejecting", "offline":
        return "offline"
    case "error":
        return "error"
    default:
        return "unknown"
    }
}

func (m *PrinterStatusMonitor) getPrinterDetails(printer *PrinterInfo) *PrinterInfo {
    // Get printer model and capabilities
    cmd := exec.Command("lpstat", "-W", "not-completed", "-o", printer.Name)
    output, err := cmd.Output()

    if err == nil {
        lines := strings.Split(string(output), "\n")
        count := 0
        for _, line := range lines {
            if strings.TrimSpace(line) != "" {
                count++
            }
        }
        printer.JobsInQueue = count
    }

    // Check for current job
    cmd = exec.Command("lpstat", "-W", "not-completed", "-o", printer.Name)
    output, err = cmd.Output()

    if err == nil && len(output) > 0 {
        lines := strings.Split(string(output), "\n")
        if len(lines) > 0 && strings.TrimSpace(lines[0]) != "" {
            parts := strings.Fields(lines[0])
            if len(parts) >= 1 {
                printer.CurrentJob = parts[0]
            }
        }
    }

    // Get printer device URI (to get more info)
    cmd = exec.Command("lpstat", "-v", printer.Name)
    output, err = cmd.Output()

    if err == nil {
        outputStr := string(output)
        // Parse device info
        if strings.Contains(outputStr, "laser") ||
           strings.Contains(outputStr, "Laser") {
            printer.Model = "Laser Printer"
        } else if strings.Contains(outputStr, "inkjet") ||
                  strings.Contains(outputStr, "Inkjet") {
            printer.Model = "Inkjet Printer"
        }
    }

    return printer
}

func (m *PrinterStatusMonitor) shouldWatchPrinter(name string) bool {
    if len(m.config.WatchPrinters) == 0 {
        return true
    }

    for _, p := range m.config.WatchPrinters {
        if p == "*" || name == p || strings.Contains(name, p) {
            return true
        }
    }

    return false
}

func (m *PrinterStatusMonitor) processPrinterStatus(printer *PrinterInfo) {
    lastInfo := m.printerState[printer.Name]

    if lastInfo == nil {
        m.printerState[printer.Name] = printer
        return
    }

    // Check for status changes
    if printer.Status != lastInfo.Status {
        switch printer.Status {
        case "ready":
            // Printer became ready
        case "printing":
            // Started printing
        case "offline":
            if m.config.SoundOnOffline {
                m.onPrinterOffline(printer)
            }
        case "error":
            if m.config.SoundOnFailed {
                m.onPrinterError(printer)
            }
        }
    }

    // Check for low ink (if we can detect it)
    if printer.InkLevel > 0 && printer.InkLevel < m.config.InkWarning {
        if lastInfo.InkLevel == 0 || lastInfo.InkLevel >= m.config.InkWarning {
            if m.config.SoundOnLowInk {
                m.onLowInk(printer)
            }
        }
    }

    // Check for completed jobs
    if lastInfo.CurrentJob != "" && printer.CurrentJob == "" {
        if m.config.SoundOnComplete {
            m.onJobCompleted(lastInfo)
        }
    }

    m.printerState[printer.Name] = printer
}

func (m *PrinterStatusMonitor) onPrinterOffline(printer *PrinterInfo) {
    key := fmt.Sprintf("offline:%s", printer.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["offline"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PrinterStatusMonitor) onPrinterError(printer *PrinterInfo) {
    key := fmt.Sprintf("error:%s", printer.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *PrinterStatusMonitor) onLowInk(printer *PrinterInfo) {
    key := fmt.Sprintf("lowink:%s", printer.Name)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["low_ink"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PrinterStatusMonitor) onJobCompleted(printer *PrinterInfo) {
    key := fmt.Sprintf("complete:%s", printer.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PrinterStatusMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| lpstat | System Tool | Free | CUPS status tool |
| lp | System Tool | Free | CUPS print command |

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
