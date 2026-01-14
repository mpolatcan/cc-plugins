# Feature: Sound Event Disk Health Monitor

Play sounds for disk health status and SMART events.

## Summary

Monitor disk health, SMART status, and disk errors, playing sounds for disk health events.

## Motivation

- Disk failure alerts
- SMART warning detection
- Bad sector warnings
- Disk degradation awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Disk Health Events

| Event | Description | Example |
|-------|-------------|---------|
| SMART Warning | SMART issue | Reallocating sectors |
| SMART Critical | SMART critical | Failing sectors |
| Bad Sector | Bad sector detected | ECC error |
| Disk Degraded | RAID degraded | Mirror missing |
| Disk Full | Space < 5% | 95% used |

### Configuration

```go
type DiskHealthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDisks        []string          `json:"watch_disks"` // "/dev/disk0", "/dev/sda"
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnCritical   bool              `json:"sound_on_critical"]
    SoundOnDegraded   bool              `json:"sound_on_degraded"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_hours"` // 6 default
}

type DiskHealthEvent struct {
    DeviceName  string
    Model       string
    SMARTStatus string // "ok", "warning", "critical", "failed"
    Temperature float64
    Reallocated int
    Pending     int
    EventType   string // "warning", "critical", "degraded"
}
```

### Commands

```bash
/ccbell:disk-health status             # Show disk health status
/ccbell:disk-health add /dev/disk0     # Add disk to watch
/ccbell:disk-health remove /dev/disk0
/ccbell:disk-health sound warning <sound>
/ccbell:disk-health sound critical <sound>
/ccbell:disk-health test               # Test disk sounds
```

### Output

```
$ ccbell:disk-health status

=== Sound Event Disk Health Monitor ===

Status: Enabled
Check Interval: 6 hours
Warning Sounds: Yes
Critical Sounds: Yes

Watched Disks: 2

[1] /dev/disk0 (Apple SSD SM0512G)
    Model: Apple SSD SM0512G
    SMART Status: VERIFIED
    Temperature: 32C
    Reallocated Sectors: 0
    Pending Sectors: 0
    Power-On Hours: 2456
    Status: OK
    Sound: bundled:stop

[2] /dev/disk1 (Samsung EVO 860)
    Model: Samsung SSD 860 EVO 500GB
    SMART Status: WARNING
    Temperature: 45C
    Reallocated Sectors: 12
    Pending Sectors: 3
    Power-On Hours: 5342
    Status: WARNING
    Sound: bundled:disk-warning

Recent Events:
  [1] /dev/disk1: SMART Warning (2 days ago)
       12 reallocated sectors
  [2] /dev/disk1: Pending Sectors (1 week ago)
       3 pending sectors
  [3] /dev/disk0: Check Passed (2 weeks ago)
       All SMART attributes OK

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Degraded: bundled:stop

[Configure] [Add Disk] [Test All]
```

---

## Audio Player Compatibility

Disk health monitoring doesn't play sounds directly:
- Monitoring feature using SMART tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk Health Monitor

```go
type DiskHealthMonitor struct {
    config         *DiskHealthMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    diskState      map[string]*DiskStatus
    lastCheckTime  map[string]time.Time
}

type DiskStatus struct {
    DeviceName   string
    Model        string
    SMARTStatus  string
    Temperature  float64
    Reallocated  int
    Pending      int
    LastCheck    time.Time
}
```

```go
func (m *DiskHealthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.diskState = make(map[string]*DiskStatus)
    m.lastCheckTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DiskHealthMonitor) monitor() {
    interval := time.Duration(m.config.PollInterval) * time.Hour
    ticker := time.NewTicker(interval)
    defer ticker.Stop()

    // Initial check
    m.checkAllDisks()

    for {
        select {
        case <-ticker.C:
            m.checkAllDisks()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DiskHealthMonitor) checkAllDisks() {
    for _, disk := range m.config.WatchDisks {
        m.checkDisk(disk)
    }
}

func (m *DiskHealthMonitor) checkDisk(device string) {
    // Use smartctl to get SMART status
    cmd := exec.Command("smartctl", "-H", "-x", device)
    output, err := cmd.Output()
    if err != nil {
        // Try without -x (limited output)
        cmd = exec.Command("smartctl", "-H", device)
        output, err = cmd.Output()
        if err != nil {
            m.onCheckFailed(device, err.Error())
            return
        }
    }

    status := m.parseSmartctlOutput(string(output), device)
    m.evaluateDiskStatus(device, status)
}

func (m *DiskHealthMonitor) parseSmartctlOutput(output string, device string) *DiskStatus {
    status := &DiskStatus{
        DeviceName: device,
        LastCheck:  time.Now(),
    }

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        // Parse model
        if strings.HasPrefix(line, "Device Model:") ||
           strings.HasPrefix(line, "Model:") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                status.Model = strings.TrimSpace(parts[1])
            }
        }

        // Parse SMART overall health
        if strings.Contains(line, "SMART overall-health") {
            if strings.Contains(line, "PASSED") || strings.Contains(line, "OK") {
                status.SMARTStatus = "ok"
            } else if strings.Contains(line, "FAILED") {
                status.SMARTStatus = "failed"
            } else {
                status.SMARTStatus = "warning"
            }
        }

        // Parse temperature
        if strings.HasPrefix(line, "Temperature Celsius") {
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                if temp, err := strconv.ParseFloat(parts[2], 64); err == nil {
                    status.Temperature = temp
                }
            }
        }

        // Parse reallocated sectors
        if strings.Contains(line, "Reallocated_Sector_Ct") {
            re := regexp.MustCompile(`(\d+)\s*$`)
            match := re.FindStringSubmatch(line)
            if len(match) >= 2 {
                status.Reallocated, _ = strconv.Atoi(match[1])
            }
        }

        // Parse pending sectors
        if strings.Contains(line, "Current_Pending_Sector") {
            re := regexp.MustCompile(`(\d+)\s*$`)
            match := re.FindStringSubmatch(line)
            if len(match) >= 2 {
                status.Pending, _ = strconv.Atoi(match[1])
            }
        }
    }

    // Determine overall status
    if status.Reallocated > 0 || status.Pending > 0 {
        status.SMARTStatus = "warning"
    }

    return status
}

func (m *DiskHealthMonitor) evaluateDiskStatus(device string, status *DiskStatus) {
    lastState := m.diskState[device]

    if lastState == nil {
        m.diskState[device] = status
        return
    }

    // Check for status changes
    if lastState.SMARTStatus != status.SMARTStatus {
        switch status.SMARTStatus {
        case "warning":
            if lastState.SMARTStatus == "ok" {
                m.onDiskWarning(device, status)
            }
        case "failed":
            if lastState.SMARTStatus != "failed" {
                m.onDiskCritical(device, status)
            }
        case "ok":
            // Disk recovered
        }
    }

    // Check for increasing bad sectors
    if status.Reallocated > lastState.Reallocated {
        m.onBadSectorIncrease(device, lastState.Reallocated, status.Reallocated)
    }

    if status.Pending > lastState.Pending {
        m.onPendingSectorIncrease(device, lastState.Pending, status.Pending)
    }

    m.diskState[device] = status
}

func (m *DiskHealthMonitor) onDiskWarning(device string, status *DiskStatus) {
    if !m.config.SoundOnWarning {
        return
    }

    // Only alert if it was recently checked
    if time.Since(m.lastCheckTime[device]) < 24*time.Hour {
        return
    }
    m.lastCheckTime[device] = time.Now()

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DiskHealthMonitor) onDiskCritical(device string, status *DiskStatus) {
    if !m.config.SoundOnCritical {
        return
    }

    // Immediate alert for critical status
    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *DiskHealthMonitor) onBadSectorIncrease(device string, oldCount int, newCount int) {
    // Significant increase in bad sectors
    if newCount-oldCount > 5 {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DiskHealthMonitor) onPendingSectorIncrease(device string, oldCount int, newCount int) {
    // Pending sectors indicate imminent failures
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *DiskHealthMonitor) onCheckFailed(device string, errorMsg string) {
    sound := m.config.Sounds["check_failed"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| smartctl | System Tool | Free | SMART monitoring |

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
| macOS | Supported | Uses smartctl |
| Linux | Supported | Uses smartctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
