# Feature: Sound Event Disk SMART Monitor

Play sounds for disk SMART status, bad sectors, and drive health warnings.

## Summary

Monitor disk SMART attributes for health status, bad sectors, and predictive failures, playing sounds for SMART events.

## Motivation

- Disk failure prediction
- SMART alert awareness
- Bad sector detection
- Drive health monitoring
- Data protection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Disk SMART Events

| Event | Description | Example |
|-------|-------------|---------|
| Health Warning | SMART not healthy | failed |
| Bad Sectors | Reallocated sectors | > 0 |
| Pending Sectors | Pending reallocation | > 0 |
| Temperature High | Temp > threshold | > 50C |
| Self-Test Failed | Test returned error | failed |
| Wear Leveling | SSD wear low | < 10% |

### Configuration

```go
type DiskSMARTMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchDisks        []string          `json:"watch_disks"` // "/dev/sda", "/dev/nvme0", "*"
    WatchTypes        []string          `json:"watch_types"` // "ssd", "hdd", "nvme"
    TempThreshold     int               `json:"temp_threshold"` // 50 default
    BadSectorThreshold int              `json:"bad_sector_threshold"` // 0 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnBadSector  bool              `json:"sound_on_bad_sector"`
    SoundOnTemp       bool              `json:"sound_on_temp"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 3600 default
}
```

### Commands

```bash
/ccbell:smart status                   # Show SMART status
/ccbell:smart add /dev/sda             # Add disk to watch
/ccbell:smart remove /dev/sda
/ccbell:smart temp 50                  # Set temp threshold
/ccbell:smart sound warning <sound>
/ccbell:smart sound bad-sector <sound>
/ccbell:smart test                     # Test SMART sounds
```

### Output

```
$ ccbell:smart status

=== Sound Event Disk SMART Monitor ===

Status: Enabled
Temperature Threshold: 50C
Bad Sector Threshold: 0
Warning Sounds: Yes
Bad Sector Sounds: Yes

Watched Disks: 3

Disk SMART Status:

[1] /dev/sda (Samsung SSD 860 EVO 500GB)
    Status: PASSED
    Temperature: 35C
    Power-On Hours: 15,000
    Reallocated Sectors: 0
    Pending Sectors: 0
    Wear Leveling: 95%
    Sound: bundled:smart-ssd1

[2] /dev/sdb (WDC WD20EZRZ-00ZTB5 2TB)
    Status: PASSED
    Temperature: 42C
    Power-On Hours: 8,500
    Reallocated Sectors: 5
    Pending Sectors: 0
    Current Pending: 0
    Sound: bundled:smart-hdd1

[3] /dev/nvme0 (Samsung SSD 970 EVO Plus 1TB)
    Status: PASSED
    Temperature: 45C
    Power-On Hours: 2,000
    Media Errors: 0
    Wear Leveling: 98%
    Available Spare: 100%
    Sound: bundled:smart-nvme *** HEALTH WARNING ***

Recent Events:
  [1] /dev/sdb: Bad Sectors Detected (1 week ago)
       5 reallocated sectors
  [2] /dev/sdb: Temperature Warning (2 weeks ago)
       55C > 50C threshold
  [3] /dev/nvme0: Self-Test Scheduled (1 month ago)

SMART Statistics:
  Total Disks: 3
  Healthy: 2
  Warnings: 1
  Bad Sectors: 5

Sound Settings:
  Warning: bundled:smart-warning
  Bad Sector: bundled:smart-bad
  Temperature: bundled:smart-temp

[Configure] [Add Disk] [Test All]
```

---

## Audio Player Compatibility

SMART monitoring doesn't play sounds directly:
- Monitoring feature using smartctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk SMART Monitor

```go
type DiskSMARTMonitor struct {
    config          *DiskSMARTMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    diskState       map[string]*SMARTInfo
    lastEventTime   map[string]time.Time
}

type SMARTInfo struct {
    Device     string
    Model      string
    Type       string // "ssd", "hdd", "nvme"
    Status     string // "PASSED", "FAILED", "UNKNOWN"
    Temperature int
    PowerOnHours int64
    Reallocated int64
    Pending     int64
    WearLevel   int // percentage
    LastCheck   time.Time
}

func (m *DiskSMARTMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.diskState = make(map[string]*SMARTInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DiskSMARTMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotDiskState()

    for {
        select {
        case <-ticker.C:
            m.checkDiskState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DiskSMARTMonitor) snapshotDiskState() {
    // List disks
    disks := m.listDisks()
    for _, disk := range disks {
        m.checkDisk(disk)
    }
}

func (m *DiskSMARTMonitor) checkDiskState() {
    disks := m.listDisks()
    currentDisks := make(map[string]bool)

    for _, disk := range disks {
        currentDisks[disk] = true
        m.checkDisk(disk)
    }

    // Check for removed disks
    for disk := range m.diskState {
        if !currentDisks[disk] {
            delete(m.diskState, disk)
        }
    }
}

func (m *DiskSMARTMonitor) listDisks() []string {
    var disks []string

    // Get list of disk devices
    cmd := exec.Command("lsblk", "-dn", "-o", "NAME")
    output, err := cmd.Output()
    if err != nil {
        return disks
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        // Filter to disk devices (not partitions)
        if strings.HasPrefix(line, "sd") || strings.HasPrefix(line, "nvme") || strings.HasPrefix(line, "vd") {
            device := "/dev/" + line
            if !m.shouldWatchDisk(device) {
                continue
            }
            disks = append(disks, device)
        }
    }

    return disks
}

func (m *DiskSMARTMonitor) checkDisk(device string) {
    info := &SMARTInfo{
        Device:    device,
        LastCheck: time.Now(),
    }

    // Determine disk type
    if strings.Contains(device, "nvme") {
        info.Type = "nvme"
    } else {
        info.Type = "ssd"
    }

    // Run smartctl
    cmd := exec.Command("smartctl", "-H", "-x", device)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")

    for _, line := range lines {
        line = strings.TrimSpace(line)

        // Parse SMART overall health
        if strings.Contains(line, "SMART overall-health") {
            if strings.Contains(line, "PASSED") || strings.Contains(line, "OK") {
                info.Status = "PASSED"
            } else if strings.Contains(line, "FAILED") {
                info.Status = "FAILED"
            }
        }

        // Parse model
        if strings.Contains(line, "Model Family") || strings.Contains(line, "Device Model") {
            re := regexp.MustEach(`: (.*)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.Model = matches[0][1]
            }
        }

        // Parse temperature
        if strings.Contains(line, "Temperature") || strings.Contains(line, "Temperature_Celsius") {
            re := regexp.MustEach(`(\d+) C`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.Temperature, _ = strconv.Atoi(matches[0][1])
            }
        }

        // Parse power on hours
        if strings.Contains(line, "Power_On_Hours") || strings.Contains(line, "Power On Hours") {
            re := regexp.MustEach(`(\d+)$`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.PowerOnHours, _ = strconv.ParseInt(matches[0][1], 10, 64)
            }
        }

        // Parse reallocated sectors
        if strings.Contains(line, "Reallocated_Sector_Ct") || strings.Contains(line, "Reallocated_Event_Count") {
            re := regexp.MustEach(`(\d+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.Reallocated, _ = strconv.ParseInt(matches[0][1], 10, 64)
            }
        }

        // Parse pending sectors
        if strings.Contains(line, "Current_Pending_Sector") || strings.Contains(line, "Pending_Sector") {
            re := regexp.MustEach(`(\d+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.Pending, _ = strconv.ParseInt(matches[0][1], 10, 64)
            }
        }

        // Parse wear level for SSD
        if strings.Contains(line, "Wear_Level") || strings.Contains(line, "Percent_Life_Remaining") {
            re := regexp.MustEach(`(\d+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                info.WearLevel, _ = strconv.Atoi(matches[0][1])
            }
        }
    }

    m.processDiskStatus(device, info)
}

func (m *DiskSMARTMonitor) processDiskStatus(device string, info *SMARTInfo) {
    lastInfo := m.diskState[device]

    if lastInfo == nil {
        m.diskState[device] = info
        return
    }

    // Check for health warning
    if info.Status == "FAILED" && lastInfo.Status != "FAILED" {
        m.onHealthWarning(device, info)
    }

    // Check for bad sectors
    if info.Reallocated > int64(m.config.BadSectorThreshold) {
        if lastInfo.Reallocated <= int64(m.config.BadSectorThreshold) {
            if m.config.SoundOnBadSector {
                m.onBadSector(device, info)
            }
        }
    }

    // Check for pending sectors
    if info.Pending > 0 && lastInfo.Pending == 0 {
        m.onPendingSector(device, info)
    }

    // Check temperature
    if info.Temperature >= m.config.TempThreshold {
        if lastInfo.Temperature < m.config.TempThreshold {
            if m.config.SoundOnTemp {
                m.onHighTemperature(device, info)
            }
        }
    }

    m.diskState[device] = info
}

func (m *DiskSMARTMonitor) onHealthWarning(device string, info *SMARTInfo) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", device)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DiskSMARTMonitor) onBadSector(device string, info *SMARTInfo) {
    if !m.config.SoundOnBadSector {
        return
    }

    key := fmt.Sprintf("badsector:%s", device)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["bad_sector"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DiskSMARTMonitor) onPendingSector(device string, info *SMARTInfo) {
    key := fmt.Sprintf("pending:%s", device)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["pending"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskSMARTMonitor) onHighTemperature(device string, info *SMARTInfo) {
    if !m.config.SoundOnTemp {
        return
    }

    key := fmt.Sprintf("temp:%s", device)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["temp"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskSMARTMonitor) shouldWatchDisk(device string) bool {
    if len(m.config.WatchDisks) == 0 {
        return true
    }

    for _, d := range m.config.WatchDisks {
        if d == "*" || d == device {
            return true
        }
    }

    return false
}

func (m *DiskSMARTMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| smartctl | System Tool | Free | SMART monitoring (smartmontools) |
| lsblk | System Tool | Free | Block device listing |

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
| macOS | Supported | Uses smartctl (via smartmontools) |
| Linux | Supported | Uses smartctl, lsblk |
