# Feature: Sound Event Disk Space Monitor

Play sounds for disk space thresholds, partition usage alerts, and filesystem full warnings.

## Summary

Monitor disk space usage across partitions and filesystems for capacity thresholds and space warnings, playing sounds for disk events.

## Motivation

- Disk awareness
- Capacity alerts
- Prevent filesystem full
- Storage planning
- Performance maintenance

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Disk Space Events

| Event | Description | Example |
|-------|-------------|---------|
| Disk Full | > 90% used | 95% used |
| Disk Warning | > 80% used | 85% used |
| Disk Critical | > 95% used | 97% used |
| Space Low | < 10% free | 8% free |
| Inode Full | Inodes exhausted | 100% |
| Read Error | Read failure | I/O error |

### Configuration

```go
type DiskSpaceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchMounts       []string          `json:"watch_mounts"` // "/", "/home", "*"
    WarningPercent    int               `json:"warning_percent"` // 80 default
    CriticalPercent   int               `json:"critical_percent"` // 95 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnFull       bool              `json:"sound_on_full"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:disk status                 # Show disk status
/ccbell:disk add /                  # Add mount point to watch
/ccbell:disk warning 80             # Set warning threshold
/ccbell:disk sound warning <sound>
/ccbell:disk test                   # Test disk sounds
```

### Output

```
$ ccbell:disk status

=== Sound Event Disk Space Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%

Disk Status:

[1] / (APFS)
    Status: HEALTHY
    Total: 500 GB
    Used: 350 GB (70%)
    Free: 150 GB (30%)
    Inodes: 45%
    Sound: bundled:disk-root

[2] /home (APFS)
    Status: WARNING *** WARNING ***
    Total: 1 TB
    Used: 850 GB (85%)
    Free: 150 GB (15%)
    Inodes: 60%
    Sound: bundled:disk-home *** WARNING ***

[3] /var (APFS)
    Status: CRITICAL *** CRITICAL ***
    Total: 100 GB
    Used: 97 GB (97%)
    Free: 3 GB (3%)
    Inodes: 88%
    Sound: bundled:disk-var *** FAILED ***

Recent Events:

[1] /var: Disk Critical (5 min ago)
       97% used > 95% threshold
       Sound: bundled:disk-critical
  [2] /home: Disk Warning (1 hour ago)
       85% used > 80% threshold
       Sound: bundled:disk-warning
  [3] /: Space Cleared (2 hours ago)
       Back to 70% usage
       Sound: bundled:disk-cleared

Disk Statistics:
  Total Partitions: 3
  Healthy: 1
  Warning: 1
  Critical: 1

Sound Settings:
  Warning: bundled:disk-warning
  Critical: bundled:disk-critical
  Full: bundled:disk-full
  Cleared: bundled:disk-cleared

[Configure] [Add Mount] [Test All]
```

---

## Audio Player Compatibility

Disk monitoring doesn't play sounds directly:
- Monitoring feature using df, statfs
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Disk Space Monitor

```go
type DiskSpaceMonitor struct {
    config        *DiskSpaceMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    diskState     map[string]*DiskInfo
    lastEventTime map[string]time.Time
}

type DiskInfo struct {
    MountPoint   string
    Filesystem   string
    TotalBytes   int64
    UsedBytes    int64
    FreeBytes    int64
    UsedPercent  float64
    InodePercent float64
    Status       string // "healthy", "warning", "critical", "full"
}

func (m *DiskSpaceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.diskState = make(map[string]*DiskInfo)
    m.lastEventTime = make(map[string]time.Time)
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
    // Get all mounted filesystems
    cmd := exec.Command("df", "-h", "-P")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines[1:] { // Skip header
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        info := m.parseDFOutput(line)
        if info != nil {
            m.processDiskStatus(info)
        }
    }
}

func (m *DiskSpaceMonitor) parseDFOutput(line string) *DiskInfo {
    fields := strings.Fields(line)
    if len(fields) < 6 {
        return nil
    }

    mountPoint := fields[5]

    // Check if we should watch this mount point
    if !m.shouldWatchMount(mountPoint) {
        return nil
    }

    info := &DiskInfo{
        MountPoint: mountPoint,
        Filesystem: fields[0],
    }

    // Parse sizes (they're in the format "70G", "1.5T", etc.)
    info.TotalBytes = m.parseSize(fields[1])
    info.UsedBytes = m.parseSize(fields[2])
    info.FreeBytes = m.parseSize(fields[3])

    // Parse percentage
    usedPercent, _ := strconv.ParseFloat(strings.TrimSuffix(fields[4], "%"), 64)
    info.UsedPercent = usedPercent

    info.Status = m.calculateStatus(info.UsedPercent)

    return info
}

func (m *DiskSpaceMonitor) parseSize(sizeStr string) int64 {
    sizeStr = strings.TrimSpace(sizeStr)

    multipliers := map[string]int64{
        "K": 1024,
        "M": 1024 * 1024,
        "G": 1024 * 1024 * 1024,
        "T": 1024 * 1024 * 1024 * 1024,
        "P": 1024 * 1024 * 1024 * 1024 * 1024,
    }

    lastChar := sizeStr[len(sizeStr)-1:]
    if _, ok := multipliers[lastChar]; ok {
        value, _ := strconv.ParseFloat(sizeStr[:len(sizeStr)-1], 64)
        return int64(value * float64(multipliers[lastChar]))
    }

    // Assume bytes
    value, _ := strconv.ParseInt(sizeStr, 10, 64)
    return value
}

func (m *DiskSpaceMonitor) shouldWatchMount(mountPoint string) bool {
    for _, mount := range m.config.WatchMounts {
        if mount == "*" || mount == mountPoint || strings.HasPrefix(mountPoint, mount) {
            return true
        }
    }
    return false
}

func (m *DiskSpaceMonitor) calculateStatus(usedPercent float64) string {
    if usedPercent >= 100 {
        return "full"
    }
    if usedPercent >= float64(m.config.CriticalPercent) {
        return "critical"
    }
    if usedPercent >= float64(m.config.WarningPercent) {
        return "warning"
    }
    return "healthy"
}

func (m *DiskSpaceMonitor) processDiskStatus(info *DiskInfo) {
    lastInfo := m.diskState[info.MountPoint]

    if lastInfo == nil {
        m.diskState[info.MountPoint] = info

        if info.Status == "critical" || info.Status == "full" {
            if m.config.SoundOnCritical {
                m.onDiskCritical(info)
            }
        } else if info.Status == "warning" {
            if m.config.SoundOnWarning {
                m.onDiskWarning(info)
            }
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "full":
            if m.config.SoundOnFull && m.shouldAlert(info.MountPoint+"full", 30*time.Minute) {
                m.onDiskFull(info)
            }
        case "critical":
            if (lastInfo.Status == "warning" || lastInfo.Status == "healthy") && m.config.SoundOnCritical {
                if m.shouldAlert(info.MountPoint+"critical", 30*time.Minute) {
                    m.onDiskCritical(info)
                }
            }
        case "warning":
            if lastInfo.Status == "healthy" && m.config.SoundOnWarning {
                if m.shouldAlert(info.MountPoint+"warning", 1*time.Hour) {
                    m.onDiskWarning(info)
                }
            }
        case "healthy":
            if lastInfo.Status != "healthy" && m.config.SoundOnFull {
                m.onDiskSpaceCleared(info)
            }
        }
    }

    m.diskState[info.MountPoint] = info
}

func (m *DiskSpaceMonitor) onDiskWarning(info *DiskInfo) {
    key := fmt.Sprintf("warning:%s", info.MountPoint)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DiskSpaceMonitor) onDiskCritical(info *DiskInfo) {
    key := fmt.Sprintf("critical:%s", info.MountPoint)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DiskSpaceMonitor) onDiskFull(info *DiskInfo) {
    sound := m.config.Sounds["full"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *DiskSpaceMonitor) onDiskSpaceCleared(info *DiskInfo) {
    sound := m.config.Sounds["cleared"]
    if sound != "" {
        m.player.Play(sound, 0.3)
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
| macOS | Supported | Uses df, statfs |
| Linux | Supported | Uses df, statfs |
