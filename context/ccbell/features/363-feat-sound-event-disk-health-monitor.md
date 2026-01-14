# Feature: Sound Event Disk Health Monitor

Play sounds for disk SMART status changes and disk error events.

## Summary

Monitor disk health status, SMART attributes, and disk errors, playing sounds for disk health events.

## Motivation

- Disk failure prevention
- SMART status awareness
- Bad sector detection
- Disk temperature alerts
- Predictive failure warnings

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Disk Health Events

| Event | Description | Example |
|-------|-------------|---------|
| SMART Warning | SMART attribute warning | Reallocated sectors |
| SMART Critical | SMART attribute critical | Pending sectors |
| Disk Temperature | Temperature threshold | 55C -> 60C |
| Bad Sector | Bad sector detected | CRC error |
| Disk Failing | Disk predicted to fail | SMART failure |
| Disk Resilver | RAID resilver started | Rebuilding array |

### Configuration

```go
type DiskHealthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDisks        []string          `json:"watch_disks"` // "sda", "nvme0", "*"
    TempWarning       int               `json:"temp_warning"` // 50 default
    TempCritical      int               `json:"temp_critical"` // 60 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"]
    SoundOnFail       bool              `json:"sound_on_fail"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 3600 default
}

type DiskHealthEvent struct {
    Disk        string
    Model       string
    Serial      string
    SMARTStatus string // "OK", "WARNING", "CRITICAL"
    Temperature int // Celsius
    Attribute   string
    AttributeValue int
    EventType   string // "warning", "critical", "temp", "bad_sector", "fail"
}
```

### Commands

```bash
/ccbell:diskhealth status             # Show disk health status
/ccbell:diskhealth add sda            # Add disk to watch
/ccbell:diskhealth remove sda
/ccbell:diskhealth temp 50            # Set temperature warning
/ccbell:diskhealth sound warning <sound>
/ccbell:diskhealth test               # Test disk health sounds
```

### Output

```
$ ccbell:diskhealth status

=== Sound Event Disk Health Monitor ===

Status: Enabled
Temperature Warning: 50C
Temperature Critical: 60C
Warning Sounds: Yes
Critical Sounds: Yes

Monitored Disks: 2

[1] sda (Samsung SSD 860 EVO)
    SMART Status: OK
    Temperature: 42C
    Serial: S3Y0N0A123456
    Health: 100%
    Sound: bundled:disk-ssd

[2] sdb (WDC WD40EZRX-00S)
    SMART Status: WARNING
    Temperature: 55C
    Reallocated Sectors: 45
    Pending Sectors: 5
    CRC Errors: 12
    Sound: bundled:disk-hdd

SMART Attributes:
  [1] Reallocated Sectors: 45 (Warning)
  [2] Pending Sectors: 5 (Warning)
  [3] Temperature: 55C (Warning)

Recent Events:
  [1] sdb: SMART Warning (5 min ago)
       Reallocated sectors: 45
  [2] sdb: Temperature Warning (10 min ago)
       55C > 50C threshold
  [3] sda: Temperature Normal (1 hour ago)
       Temperature returned to normal

Disk Health Statistics:
  Total Disks: 2
  Healthy: 1
  Warning: 1
  Critical: 0

Sound Settings:
  Warning: bundled:disk-warning
  Critical: bundled:disk-critical
  Fail: bundled:disk-fail

[Configure] [Add Disk] [Test All]
```

---

## Audio Player Compatibility

Disk health monitoring doesn't play sounds directly:
- Monitoring feature using smartctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk Health Monitor

```go
type DiskHealthMonitor struct {
    config          *DiskHealthMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    diskState       map[string]*DiskInfo
    lastEventTime   map[string]time.Time
}

type DiskInfo struct {
    Disk           string
    Model          string
    Serial         string
    SMARTStatus    string
    Temperature    int
    Reallocated    int
    Pending        int
    CRCError       int
    PowerOnHours   int
    LastCheck      time.Time
}

func (m *DiskHealthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.diskState = make(map[string]*DiskInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DiskHealthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
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
    // Get list of disks
    disks := m.getDiskList()

    for _, disk := range disks {
        if !m.shouldWatchDisk(disk) {
            continue
        }

        info := m.checkDiskHealth(disk)
        if info == nil {
            continue
        }

        lastInfo := m.diskState[disk]
        if lastInfo == nil {
            m.diskState[disk] = info
            continue
        }

        // Evaluate health changes
        m.evaluateHealthChanges(disk, info, lastInfo)
        m.diskState[disk] = info
    }
}

func (m *DiskHealthMonitor) getDiskList() []string {
    var disks []string

    // Get block devices
    entries, err := os.ReadDir("/sys/block")
    if err != nil {
        return disks
    }

    for _, entry := range entries {
        name := entry.Name()
        // Skip loop devices and ram disks
        if strings.HasPrefix(name, "loop") || strings.HasPrefix(name, "ram") {
            continue
        }
        disks = append(disks, name)
    }

    return disks
}

func (m *DiskHealthMonitor) shouldWatchDisk(disk string) bool {
    if len(m.config.WatchDisks) == 0 {
        return true
    }

    for _, d := range m.config.WatchDisks {
        if d == "*" || d == disk || strings.HasPrefix(disk, d) {
            return true
        }
    }

    return false
}

func (m *DiskHealthMonitor) checkDiskHealth(disk string) *DiskInfo {
    cmd := exec.Command("smartctl", "-H", "-i", "-l", "sMART", "-o", "json",
        fmt.Sprintf("/dev/%s", disk))
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &DiskInfo{
        Disk:      disk,
        LastCheck: time.Now(),
    }

    // Parse smartctl JSON output
    m.parseSmartctlOutput(string(output), info)

    return info
}

func (m *DiskHealthMonitor) parseSmartctlOutput(output string, info *DiskInfo) {
    // This is a simplified parser - full implementation would use JSON parsing

    // Check health assessment
    if strings.Contains(output, "PASSED") || strings.Contains(output, "OK") {
        info.SMARTStatus = "OK"
    } else if strings.Contains(output, "FAIL") {
        info.SMARTStatus = "CRITICAL"
    } else if strings.Contains(output, "Attribute") {
        info.SMARTStatus = "WARNING"
    }

    // Extract temperature
    tempRe := regexp.MustCompile(`Temperature.*?(\d+)`)
    match := tempRe.FindStringSubmatch(output)
    if match != nil {
        info.Temperature, _ = strconv.Atoi(match[1])
    }

    // Extract reallocated sectors
    reallocRe := regexp.MustCompile(`Reallocated_Sector_Ct.*?(\d+)`)
    match = reallocRe.FindStringSubmatch(output)
    if match != nil {
        info.Reallocated, _ = strconv.Atoi(match[1])
    }

    // Extract pending sectors
    pendingRe := regexp.MustCompile(`Current_Pending_Sector.*?(\d+)`)
    match = pendingRe.FindStringSubmatch(output)
    if match != nil {
        info.Pending, _ = strconv.Atoi(match[1])
    }

    // Extract CRC errors (for SATA/NVMe)
    crcRe := regexp.MustCompile(`CRC_Error.*?(\d+)`)
    match = crcRe.FindStringSubmatch(output)
    if match != nil {
        info.CRCError, _ = strconv.Atoi(match[1])
    }
}

func (m *DiskHealthMonitor) evaluateHealthChanges(disk string, newInfo *DiskInfo, lastInfo *DiskInfo) {
    // Check SMART status change
    if newInfo.SMARTStatus != lastInfo.SMARTStatus {
        if newInfo.SMARTStatus == "CRITICAL" {
            m.onDiskCritical(disk, newInfo)
        } else if newInfo.SMARTStatus == "WARNING" && lastInfo.SMARTStatus == "OK" {
            m.onDiskWarning(disk, newInfo)
        }
    }

    // Check temperature
    if newInfo.Temperature >= m.config.TempCritical &&
        lastInfo.Temperature < m.config.TempCritical {
        m.onDiskTempCritical(disk, newInfo)
    } else if newInfo.Temperature >= m.config.TempWarning &&
        lastInfo.Temperature < m.config.TempWarning {
        m.onDiskTempWarning(disk, newInfo)
    }

    // Check for new bad sectors
    if newInfo.Reallocated > lastInfo.Reallocated ||
        newInfo.Pending > lastInfo.Pending ||
        newInfo.CRCError > lastInfo.CRCError {
        m.onBadSectorDetected(disk, newInfo, lastInfo)
    }
}

func (m *DiskHealthMonitor) onDiskWarning(disk string, info *DiskInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", disk)
    if m.shouldAlert(key, 4*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskHealthMonitor) onDiskCritical(disk string, info *DiskInfo) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("critical:%s", disk)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DiskHealthMonitor) onDiskTempWarning(disk string, info *DiskInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("temp_warning:%s", disk)
    if m.shouldAlert(key, 2*time.Hour) {
        sound := m.config.Sounds["temp_warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskHealthMonitor) onDiskTempCritical(disk string, info *DiskInfo) {
    key := fmt.Sprintf("temp_critical:%s", disk)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["temp_critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DiskHealthMonitor) onBadSectorDetected(disk string, newInfo *DiskInfo, lastInfo *DiskInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("bad_sector:%s", disk)
    if m.shouldAlert(key, 4*time.Hour) {
        sound := m.config.Sounds["bad_sector"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DiskHealthMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| smartctl | System Tool | Free | SMART disk monitoring |
| /dev/sd* | Device | Free | Disk devices |

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
| macOS | Supported | Uses smartctl (install from brew) |
| Linux | Supported | Uses smartctl |
