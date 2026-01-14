# Feature: Sound Event Disk Space Monitor

Play sounds for low disk space, high disk usage, and disk full events.

## Summary

Monitor disk space and usage for partitions and volumes, playing sounds for disk space events.

## Motivation

- Disk space awareness
- Storage capacity alerts
- Prevention of disk full errors
- Partition monitoring
- Storage health feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Disk Space Events

| Event | Description | Example |
|-------|-------------|---------|
| Disk High | Usage > threshold | > 80% |
| Disk Critical | Usage > critical | > 95% |
| Disk Full | Partition full | 100% |
| Low Inodes | Inodes exhausted | < 5% |
| Disk Recovered | Back to normal | < 70% |
| Disk Slow | High I/O wait | > 50ms |

### Configuration

```go
type DiskSpaceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/", "/home", "/Volumes/*"
    WarningPercent    int               `json:"warning_percent"` // 80 default
    CriticalPercent   int               `json:"critical_percent"` // 95 default
    InodeWarning      int               `json:"inode_warning_percent"` // 5 default
    SoundOnHigh       bool              `json:"sound_on_high"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnRecovered  bool              `json:"sound_on_recovered"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:disk status                  # Show disk status
/ccbell:disk add /home               # Add path to watch
/ccbell:disk warning 80              # Set warning threshold
/ccbell:disk sound high <sound>
/ccbell:disk sound critical <sound>
/ccbell:disk test                    # Test disk sounds
```

### Output

```
$ ccbell:disk status

=== Sound Event Disk Space Monitor ===

Status: Enabled
Warning Threshold: 80%
Critical Threshold: 95%
Inode Warning: 5%

Disk Status:

[1] / (root)
    Status: NORMAL
    Used: 45 GB / 100 GB
    Usage: 45%
    Inodes: 95% available
    Sound: bundled:disk-root

[2] /home
    Status: WARNING
    Used: 380 GB / 450 GB
    Usage: 84% *** WARNING ***
    Inodes: 88% available
    Sound: bundled:disk-home *** WARNING ***

[3] /Volumes/Backup
    Status: NORMAL
    Used: 800 GB / 2 TB
    Usage: 40%
    Inodes: 99% available
    Sound: bundled:disk-backup

Disk History:

  /home usage over last 24 hours:
  00:00: 80% (Warning)
  06:00: 81% (Warning)
  12:00: 82% (Warning)
  18:00: 84% (Warning)

Recent Events:
  [1] /home: Disk High (2 hours ago)
       84% usage detected
  [2] /: Disk Recovered (1 day ago)
       Usage dropped to 45%
  [3] /home: Disk High (1 day ago)
       80% threshold crossed

Disk Statistics:
  Total Partitions: 3
  Normal: 2
  Warning: 1
  Critical: 0

Sound Settings:
  High: bundled:disk-high
  Critical: bundled:disk-critical
  Recovered: bundled:disk-recovered

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Disk monitoring doesn't play sounds directly:
- Monitoring feature using df
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Disk Space Monitor

```go
type DiskSpaceMonitor struct {
    config          *DiskSpaceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    diskState       map[string]*DiskInfo
    lastEventTime   map[string]time.Time
    lastStatus      map[string]string
}

type DiskInfo struct {
    Path          string
    Device        string
    Total         uint64
    Used          uint64
    Available     uint64
    UsedPercent   float64
    InodesTotal   uint64
    InodesUsed    uint64
    InodesPercent float64
    Status        string // "normal", "warning", "critical"
}

func (m *DiskSpaceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.diskState = make(map[string]*DiskInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastStatus = make(map[string]string)
    go m.monitor()
}

func (m *DiskSpaceMonitor) monitor() {
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

func (m *DiskSpaceMonitor) snapshotDiskState() {
    m.checkDiskState()
}

func (m *DiskSpaceMonitor) checkDiskState() {
    disks := m.listDisks()

    for _, disk := range disks {
        if !m.shouldWatchPath(disk.Path) {
            continue
        }
        m.processDiskStatus(disk)
    }
}

func (m *DiskSpaceMonitor) listDisks() []*DiskInfo {
    var disks []*DiskInfo

    cmd := exec.Command("df", "-k", "-P", "-l")
    output, err := cmd.Output()
    if err != nil {
        return disks
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Filesystem") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        total, _ := strconv.ParseUint(parts[1], 10, 64)
        used, _ := strconv.ParseUint(parts[2], 10, 64)
        avail, _ := strconv.ParseUint(parts[3], 10, 64)
        usedPercent, _ := strconv.ParseFloat(strings.TrimSuffix(parts[4], "%"), 64)

        disk := &DiskInfo{
            Path:        parts[5],
            Device:      parts[0],
            Total:       total * 1024,
            Used:        used * 1024,
            Available:   avail * 1024,
            UsedPercent: usedPercent,
            Status:      m.calculateStatus(usedPercent),
        }

        disks = append(disks, disk)
    }

    return disks
}

func (m *DiskSpaceMonitor) listDarwinDisks() []*DiskInfo {
    var disks []*DiskInfo

    // Get mounted volumes
    cmd := exec.Command("df", "-k", "-l")
    output, err := cmd.Output()
    if err != nil {
        return disks
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Filesystem") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        total, _ := strconv.ParseUint(parts[1], 10, 64)
        used, _ := strconv.ParseUint(parts[2], 10, 64)
        avail, _ := strconv.ParseUint(parts[3], 10, 64)
        usedPercent, _ := strconv.ParseFloat(strings.TrimSuffix(parts[4], "%"), 64)

        disk := &DiskInfo{
            Path:        parts[5],
            Device:      parts[0],
            Total:       total * 1024,
            Used:        used * 1024,
            Available:   avail * 1024,
            UsedPercent: usedPercent,
            Status:      m.calculateStatus(usedPercent),
        }

        disks = append(disks, disk)
    }

    return disks
}

func (m *DiskSpaceMonitor) calculateStatus(usedPercent float64) string {
    if usedPercent >= float64(m.config.CriticalPercent) {
        return "critical"
    }
    if usedPercent >= float64(m.config.WarningPercent) {
        return "warning"
    }
    return "normal"
}

func (m *DiskSpaceMonitor) shouldWatchPath(path string) bool {
    if len(m.config.WatchPaths) == 0 {
        return true
    }

    for _, p := range m.config.WatchPaths {
        expandedPath := m.expandPath(p)
        if expandedPath == path || strings.HasPrefix(path, expandedPath+"/") {
            return true
        }
        // Handle wildcards for macOS
        if strings.Contains(expandedPath, "*") {
            pattern := strings.ReplaceAll(expandedPath, "*", ".*")
            matched, _ := regexp.MatchString(pattern, path)
            if matched {
                return true
            }
        }
    }

    return false
}

func (m *DiskSpaceMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *DiskSpaceMonitor) processDiskStatus(disk *DiskInfo) {
    lastInfo := m.diskState[disk.Path]
    lastStatus := m.lastStatus[disk.Path]

    if lastInfo == nil {
        m.diskState[disk.Path] = disk
        m.lastStatus[disk.Path] = disk.Status
        return
    }

    // Check for status changes
    if disk.Status != lastStatus {
        m.onDiskStatusChanged(disk.Path, disk.Status, disk)
        m.lastStatus[disk.Path] = disk.Status
    }

    m.diskState[disk.Path] = disk
}

func (m *DiskSpaceMonitor) onDiskStatusChanged(path, status string, disk *DiskInfo) {
    switch status {
    case "critical":
        if m.config.SoundOnCritical {
            m.onDiskCritical(disk)
        }
    case "warning":
        if m.config.SoundOnHigh {
            m.onDiskHigh(disk)
        }
    case "normal":
        if lastStatus, exists := m.lastStatus[path]; exists {
            if lastStatus == "warning" || lastStatus == "critical" {
                if m.config.SoundOnRecovered {
                    m.onDiskRecovered(disk)
                }
            }
        }
    }
}

func (m *DiskSpaceMonitor) onDiskHigh(disk *DiskInfo) {
    key := fmt.Sprintf("disk:high:%s", disk.Path)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["high"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DiskSpaceMonitor) onDiskCritical(disk *DiskInfo) {
    key := fmt.Sprintf("disk:critical:%s", disk.Path)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *DiskSpaceMonitor) onDiskRecovered(disk *DiskInfo) {
    key := fmt.Sprintf("disk:recovered:%s", disk.Path)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["recovered"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *DiskSpaceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| df | System Tool | Free | Disk free space |

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
| macOS | Supported | Uses df |
| Linux | Supported | Uses df |
