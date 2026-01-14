# Feature: Sound Event Inode Monitor

Play sounds for filesystem inode exhaustion warnings and inode usage thresholds.

## Summary

Monitor filesystem inode usage for capacity thresholds and inode exhaustion warnings, playing sounds for inode events.

## Motivation

- Inode awareness
- Storage capacity
- Filesystem health
- Prevent filesystem full
- Small file tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Inode Events

| Event | Description | Example |
|-------|-------------|---------|
| Inode Warning | > 80% used | 85% |
| Inode Critical | > 95% used | 97% |
| Inode Full | 100% used | full |
| Inode Normal | Back to normal | < 80% |
| Inode High | Increasing trend | +5% today |
| Inode Low | Available inodes | < 1000 |

### Configuration

```go
type InodeMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchMounts      []string          `json:"watch_mounts"` // "/", "/home", "*"
    WarningPercent   int               `json:"warning_percent"` // 80 default
    CriticalPercent  int               `json:"critical_percent"` // 95 default
    MinAvailable     int               `json:"min_available"` // 1000 default
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"`
    SoundOnFull      bool              `json:"sound_on_full"`
    SoundOnNormal    bool              `json:"sound_on_normal"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:inode status                # Show inode status
/ccbell:inode add /                 # Add mount point to watch
/ccbell:inode warning 80            # Set warning threshold
/ccbell:inode sound warning <sound>
/ccbell:inode test                  # Test inode sounds
```

### Output

```
$ ccbell:inode status

=== Sound Event Inode Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%
Min Available: 1000

Inode Status:

[1] / (APFS)
    Status: HEALTHY
    Total: 10,485,760
    Used: 6,291,456 (60%)
    Free: 4,194,304 (40%)
    Sound: bundled:inode-root

[2] /home (APFS)
    Status: WARNING *** WARNING ***
    Total: 10,485,760
    Used: 8,696,832 (83%)
    Free: 1,788,928 (17%)
    Sound: bundled:inode-home *** WARNING ***

[3] /var (APFS)
    Status: CRITICAL *** CRITICAL ***
    Total: 10,485,760
    Used: 10,192,716 (97%)
    Free: 293,044 (3%)
    Available: 293,044
    Sound: bundled:inode-var *** FAILED ***

Recent Events:

[1] /var: Inode Critical (5 min ago)
       97% used > 95% threshold
       Sound: bundled:inode-critical
  [2] /home: Inode Warning (1 hour ago)
       83% used > 80% threshold
       Sound: bundled:inode-warning
  [3] /: Inode Normal (2 hours ago)
       Back to 60% usage
       Sound: bundled:inode-normal

Inode Statistics:
  Total Partitions: 3
  Healthy: 1
  Warning: 1
  Critical: 1

Sound Settings:
  Warning: bundled:inode-warning
  Critical: bundled:inode-critical
  Full: bundled:inode-full
  Normal: bundled:inode-normal

[Configure] [Add Mount] [Test All]
```

---

## Audio Player Compatibility

Inode monitoring doesn't play sounds directly:
- Monitoring feature using df -i
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Inode Monitor

```go
type InodeMonitor struct {
    config        *InodeMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    inodeState    map[string]*InodeInfo
    lastEventTime map[string]time.Time
}

type InodeInfo struct {
    MountPoint   string
    Filesystem   string
    TotalInodes  int64
    UsedInodes   int64
    FreeInodes   int64
    UsedPercent  float64
    Status       string // "healthy", "warning", "critical", "full"
}

func (m *InodeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.inodeState = make(map[string]*InodeInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *InodeMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotInodeState()

    for {
        select {
        case <-ticker.C:
            m.checkInodeState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *InodeMonitor) snapshotInodeState() {
    m.checkInodeState()
}

func (m *InodeMonitor) checkInodeState() {
    // Get inode usage with df -i
    cmd := exec.Command("df", "-i", "-P")
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

        info := m.parseDFInodeOutput(line)
        if info != nil {
            m.processInodeStatus(info)
        }
    }
}

func (m *InodeMonitor) parseDFInodeOutput(line string) *InodeInfo {
    fields := strings.Fields(line)
    if len(fields) < 6 {
        return nil
    }

    mountPoint := fields[5]

    // Check if we should watch this mount point
    if !m.shouldWatchMount(mountPoint) {
        return nil
    }

    info := &InodeInfo{
        MountPoint: mountPoint,
        Filesystem: fields[0],
    }

    // Parse inode counts
    info.TotalInodes, _ = strconv.ParseInt(fields[1], 10, 64)
    info.UsedInodes, _ = strconv.ParseInt(fields[2], 10, 64)
    info.FreeInodes, _ = strconv.ParseInt(fields[3], 10, 64)

    // Parse percentage
    usedPercent, _ := strconv.ParseFloat(strings.TrimSuffix(fields[4], "%"), 64)
    info.UsedPercent = usedPercent

    info.Status = m.calculateStatus(info.UsedPercent, info.FreeInodes)

    return info
}

func (m *InodeMonitor) shouldWatchMount(mountPoint string) bool {
    for _, mount := range m.config.WatchMounts {
        if mount == "*" || mount == mountPoint || strings.HasPrefix(mountPoint, mount) {
            return true
        }
    }
    return false
}

func (m *InodeMonitor) calculateStatus(usedPercent float64, freeInodes int64) string {
    if usedPercent >= 100 || freeInodes == 0 {
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

func (m *InodeMonitor) processInodeStatus(info *InodeInfo) {
    lastInfo := m.inodeState[info.MountPoint]

    if lastInfo == nil {
        m.inodeState[info.MountPoint] = info

        if info.Status == "critical" || info.Status == "full" {
            if m.config.SoundOnCritical {
                m.onInodeCritical(info)
            }
        } else if info.Status == "warning" {
            if m.config.SoundOnWarning {
                m.onInodeWarning(info)
            }
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "full":
            if m.config.SoundOnFull && m.shouldAlert(info.MountPoint+"full", 30*time.Minute) {
                m.onInodeFull(info)
            }
        case "critical":
            if (lastInfo.Status == "warning" || lastInfo.Status == "healthy") && m.config.SoundOnCritical {
                if m.shouldAlert(info.MountPoint+"critical", 30*time.Minute) {
                    m.onInodeCritical(info)
                }
            }
        case "warning":
            if lastInfo.Status == "healthy" && m.config.SoundOnWarning {
                if m.shouldAlert(info.MountPoint+"warning", 1*time.Hour) {
                    m.onInodeWarning(info)
                }
            }
        case "healthy":
            if lastInfo.Status != "healthy" && m.config.SoundOnNormal {
                m.onInodeNormal(info)
            }
        }
    }

    // Check for low available inodes
    if info.FreeInodes < int64(m.config.MinAvailable) &&
       lastInfo.FreeInodes >= int64(m.config.MinAvailable) {
        if m.shouldAlert(info.MountPoint+"low", 1*time.Hour) {
            m.onInodeLow(info)
        }
    }

    m.inodeState[info.MountPoint] = info
}

func (m *InodeMonitor) onInodeWarning(info *InodeInfo) {
    key := fmt.Sprintf("warning:%s", info.MountPoint)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *InodeMonitor) onInodeCritical(info *InodeInfo) {
    key := fmt.Sprintf("critical:%s", info.MountPoint)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *InodeMonitor) onInodeFull(info *InodeInfo) {
    sound := m.config.Sounds["full"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *InodeMonitor) onInodeNormal(info *InodeInfo) {
    sound := m.config.Sounds["normal"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *InodeMonitor) onInodeLow(info *InodeInfo) {
    sound := m.config.Sounds["low"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *InodeMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| df | System Tool | Free | Disk filesystem info |

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
