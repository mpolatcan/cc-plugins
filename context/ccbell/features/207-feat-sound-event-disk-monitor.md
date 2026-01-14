# Feature: Sound Event Disk Monitor

Play sounds for disk space and health events.

## Summary

Monitor disk usage, available space, and disk health, playing sounds when thresholds are exceeded or issues are detected.

## Motivation

- Prevent disk full emergencies
- Monitor SSD health
- Backup notification awareness
- Storage capacity alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Disk Events

| Event | Description | Example |
|-------|-------------|---------|
| Low Space | Disk below threshold | Below 10% free |
| Warning Space | Disk warning level | Below 20% free |
| Disk Full | Disk completely full | 0% free |
| Read Error | Disk read failure | SMART warning |
| Write Error | Disk write failure | I/O error |

### Configuration

```go
type DiskMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchPaths    []string          `json:"watch_paths"` // "/" or custom
    LowThreshold  int               `json:"low_threshold"` // 10 default
    WarningThreshold int            `json:"warning_threshold"` // 20 default
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 300 default
    CheckSMART    bool              `json:"check_smart"` // Check disk health
}

type DiskStatus struct {
    Path        string
    Total       uint64
    Used        uint64
    Available   uint64
    Percentage  float64
    SMARTStatus string // "ok", "warning", "failed"
}
```

### Commands

```bash
/ccbell:disk status               # Show disk status
/ccbell:disk add /path            # Add path to watch
/ccbell:disk remove /path         # Remove path
/ccbell:disk low <percent>        # Set low threshold
/ccbell:disk warning <percent>    # Set warning threshold
/ccbell:disk sound low <sound>
/ccbell:disk sound warning <sound>
/ccbell:disk test                 # Test disk sounds
```

### Output

```
$ ccbell:disk status

=== Sound Event Disk Monitor ===

Status: Enabled
Low Threshold: 10%
Warning Threshold: 20%
Poll Interval: 300s

Monitored Paths: 3

[1] /
  Total: 500 GB
  Used: 425 GB (85%)
  Available: 75 GB (15%)
  Status: WARNING
  Sound: bundled:stop

[2] /Users
  Total: 250 GB
  Used: 200 GB (80%)
  Available: 50 GB (20%)
  Status: OK
  Sound: bundled:stop

[3] /var
  Total: 100 GB
  Used: 95 GB (95%)
  Available: 5 GB (5%)
  Status: LOW
  Sound: bundled:stop

[Configure] [Test All] [Add Path]
```

---

## Audio Player Compatibility

Disk monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk Monitor

```go
type DiskMonitor struct {
    config     *DiskMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastStatus map[string]*DiskStatus
}

func (m *DiskMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStatus = make(map[string]*DiskStatus)
    go m.monitor()
}

func (m *DiskMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDisks()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DiskMonitor) checkDisks() {
    for _, path := range m.config.WatchPaths {
        status := m.getDiskStatus(path)
        if status != nil {
            m.evaluateDisk(path, status)
        }
    }
}

func (m *DiskMonitor) getDiskStatus(path string) *DiskStatus {
    status := &DiskStatus{Path: path}

    // Get disk usage
    var stat syscall.Statfs_t
    if err := syscall.Statfs(path, &stat); err != nil {
        return nil
    }

    total := stat.Blocks * uint64(stat.Bsize)
    available := stat.Bavail * uint64(stat.Bsize)
    used := total - available

    status.Total = total
    status.Available = available
    status.Used = used
    status.Percentage = float64(used) / float64(total) * 100

    // Check SMART if enabled
    if m.config.CheckSMART {
        status.SMARTStatus = m.checkSMART(path)
    }

    return status
}

func (m *DiskMonitor) checkSMART(path string) string {
    // macOS: diskutil info disk0 | grep SMART
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("diskutil", "info", "disk0")
        output, err := cmd.Output()
        if err != nil {
            return "unknown"
        }
        if strings.Contains(string(output), "SMART Status: Verified") {
            return "ok"
        }
        if strings.Contains(string(output), "SMART Status: Failing") {
            return "failed"
        }
    }

    // Linux: smartctl
    if runtime.GOOS == "linux" {
        cmd := exec.Command("smartctl", "-H", path)
        output, err := cmd.Output()
        if err != nil {
            return "unknown"
        }
        if strings.Contains(string(output), "PASSED") {
            return "ok"
        }
        if strings.Contains(string(output), "FAILED") {
            return "failed"
        }
    }

    return "unknown"
}

func (m *DiskMonitor) evaluateDisk(path string, status *DiskStatus) {
    lastStatus := m.lastStatus[path]
    m.lastStatus[path] = status

    // Check disk full
    if status.Percentage >= 100 - float64(m.config.LowThreshold) {
        if lastStatus == nil || lastStatus.Percentage < 100-float64(m.config.LowThreshold) {
            m.playSound("low")
        }
    }

    // Check warning level
    if status.Percentage >= 100-float64(m.config.WarningThreshold) &&
       status.Percentage < 100-float64(m.config.LowThreshold) {
        if lastStatus == nil || lastStatus.Percentage < 100-float64(m.config.WarningThreshold) {
            m.playSound("warning")
        }
    }

    // Check SMART status
    if status.SMARTStatus == "failed" {
        if lastStatus == nil || lastStatus.SMARTStatus != "failed" {
            m.playSound("smart_failed")
        }
    } else if status.SMARTStatus == "warning" {
        if lastStatus == nil || lastStatus.SMARTStatus == "ok" {
            m.playSound("smart_warning")
        }
    }
}

func (m *DiskMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| syscall | Go Stdlib | Free | Disk statistics |
| diskutil | System Tool | Free | macOS disk info |
| smartctl | APT/DMG | Free | SMART disk health |

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
| macOS | Supported | Uses diskutil and syscall |
| Linux | Supported | Uses syscall and smartctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
