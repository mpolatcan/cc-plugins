# Feature: Sound Event Inode Monitor

Play sounds for inode exhaustion warnings.

## Summary

Monitor inode usage and availability, playing sounds when inode counts approach limits.

## Motivation

- Storage exhaustion alerts
- Filesystem health monitoring
- Inode leak detection
- Capacity planning feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Inode Events

| Event | Description | Example |
|-------|-------------|---------|
| Inode High | High inode usage | > 80% |
| Inode Critical | Critical inode usage | > 95% |
| Inode Full | Filesystem full | 100% used |
| Inode Freed | Inodes freed | Cleanup occurred |

### Configuration

```go
type InodeMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchMountPoints  []string          `json:"watch_mount_points"` // "/", "/home"
    WarningThreshold  int               `json:"warning_threshold"` // 80 default
    CriticalThreshold int               `json:"critical_threshold"` // 95 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnCritical   bool              `json:"sound_on_critical"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default (5 min)
}

type InodeEvent struct {
    MountPoint    string
    TotalInodes   int64
    UsedInodes    int64
    FreeInodes    int64
    UsagePercent  float64
    EventType     string // "warning", "critical", "full", "freed"
}
```

### Commands

```bash
/ccbell:inode status                  # Show inode status
/ccbell:inode add /                   # Add mount point to watch
/ccbell:inode remove /
/ccbell:inode warning 80              # Set warning threshold
/ccbell:inode sound warning <sound>
/ccbell:inode test                    # Test inode sounds
```

### Output

```
$ ccbell:inode status

=== Sound Event Inode Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%

Watched Mount Points: 2

[1] / (APFS)
    Total: 10,485,760
    Used: 8,388,608 (80%)
    Free: 2,097,152
    Status: WARNING
    Sound: bundled:inode-warning

[2] /home (APFS)
    Total: 5,242,880
    Used: 2,097,152 (40%)
    Free: 3,145,728
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] /: Inode Warning (5 min ago)
       80% used (8.3M/10.4M)
  [2] /home: Inodes Freed (1 day ago)
       Cleanup released 100K inodes

Inode Statistics:
  /: +5,000/day
  /home: +100/day

Sound Settings:
  Warning: bundled:inode-warning
  Critical: bundled:inode-critical

[Configure] [Add Mount Point] [Test All]
```

---

## Audio Player Compatibility

Inode monitoring doesn't play sounds directly:
- Monitoring feature using filesystem tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Inode Monitor

```go
type InodeMonitor struct {
    config            *InodeMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    mountPointInodes  map[string]*InodeUsage
    lastWarningTime   map[string]time.Time
}

type InodeUsage struct {
    MountPoint   string
    TotalInodes  int64
    UsedInodes   int64
    FreeInodes   int64
    UsagePercent float64
}

func (m *InodeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.mountPointInodes = make(map[string]*InodeUsage)
    m.lastWarningTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *InodeMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotInodeUsage()

    for {
        select {
        case <-ticker.C:
            m.checkInodeUsage()
        case <-m.stopCh:
            return
        }
    }
}

func (m *InodeMonitor) snapshotInodeUsage() {
    // Get all mount points
    if runtime.GOOS == "darwin" {
        m.checkDarwinInodes()
    } else {
        m.checkLinuxInodes()
    }
}

func (m *InodeMonitor) checkInodeUsage() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinInodes()
    } else {
        m.checkLinuxInodes()
    }
}

func (m *InodeMonitor) checkDarwinInodes() {
    cmd := exec.Command("df", "-i", "-P")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDFOutput(string(output))
}

func (m *InodeMonitor) checkLinuxInodes() {
    cmd := exec.Command("df", "-i", "-P")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDFOutput(string(output))
}

func (m *InodeMonitor) parseDFOutput(output string) {
    lines := strings.Split(output, "\n")

    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Filesystem") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        mountPoint := parts[5]

        if !m.shouldWatchMountPoint(mountPoint) {
            continue
        }

        totalInodes, _ := strconv.ParseInt(parts[1], 10, 64)
        usedInodes, _ := strconv.ParseInt(parts[2], 10, 64)
        freeInodes, _ := strconv.ParseInt(parts[3], 10, 64)

        usagePercent := float64(usedInodes) / float64(totalInodes) * 100

        m.evaluateInodeUsage(mountPoint, totalInodes, usedInodes, freeInodes, usagePercent)
    }
}

func (m *InodeMonitor) shouldWatchMountPoint(mountPoint string) bool {
    if len(m.config.WatchMountPoints) == 0 {
        return true
    }

    for _, mp := range m.config.WatchMountPoints {
        if mountPoint == mp {
            return true
        }
    }

    return false
}

func (m *InodeMonitor) evaluateInodeUsage(mountPoint string, total int64, used int64, free int64, percent float64) {
    lastUsage := m.mountPointInodes[mountPoint]

    current := &InodeUsage{
        MountPoint:   mountPoint,
        TotalInodes:  total,
        UsedInodes:   used,
        FreeInodes:   free,
        UsagePercent: percent,
    }

    if lastUsage == nil {
        m.mountPointInodes[mountPoint] = current
        return
    }

    // Check thresholds
    if percent >= float64(m.config.CriticalThreshold) {
        if lastUsage.UsagePercent < float64(m.config.CriticalThreshold) {
            m.onInodeCritical(mountPoint, current)
        }
    } else if percent >= float64(m.config.WarningThreshold) {
        if lastUsage.UsagePercent < float64(m.config.WarningThreshold) {
            m.onInodeWarning(mountPoint, current)
        }
    }

    m.mountPointInodes[mountPoint] = current
}

func (m *InodeMonitor) onInodeWarning(mountPoint string, usage *InodeUsage) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("warning:%s", mountPoint)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *InodeMonitor) onInodeCritical(mountPoint string, usage *InodeUsage) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("critical:%s", mountPoint)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *InodeMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastWarningTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastWarningTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| df | System Tool | Free | Filesystem usage |

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
| macOS | Supported | Uses df -i |
| Linux | Supported | Uses df -i |
| Windows | Not Supported | ccbell only supports macOS/Linux |
