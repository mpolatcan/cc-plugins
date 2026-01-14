# Feature: Sound Event Inode/Filesystem Monitor

Play sounds for inode exhaustion warnings and filesystem capacity events.

## Summary

Monitor inode usage, filesystem capacity, and filesystem health events, playing sounds for inode/filesystem events.

## Motivation

- Filesystem awareness
- Inode exhaustion prevention
- Capacity planning
- Filesystem health feedback
- Storage availability alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Inode/Filesystem Events

| Event | Description | Example |
|-------|-------------|---------|
| Inode Warning | Inode usage high | 85% used |
| Inode Critical | Inodes nearly exhausted | 95% used |
| Space Warning | Disk space low | 90% used |
| Space Critical | Disk nearly full | 98% used |
| Filesystem Readonly | Filesystem remounted RO | Errors detected |
| Filesystem Full | Filesystem completely full | No space left |

### Configuration

```go
type InodeFilesystemMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchMounts        []string          `json:"watch_mounts"` // "/", "/home", "*"
    InodeWarning       int               `json:"inode_warning"` // 85 default
    InodeCritical      int               `json:"inode_critical"` // 95 default
    SpaceWarning       int               `json:"space_warning"` // 90 default
    SpaceCritical      int               `json:"space_critical"` // 98 default
    SoundOnInodeWarning bool             `json:"sound_on_inode_warning"`
    SoundOnInodeCritical bool            `json:"sound_on_inode_critical"`
    SoundOnSpaceWarning bool             `json:"sound_on_space_warning"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 300 default
}

type InodeFilesystemEvent struct {
    MountPoint   string
    Filesystem   string
    InodeUsed    int // percentage
    InodeTotal   int64
    InodeFree    int64
    SpaceUsed    int // percentage
    SpaceTotal   int64
    SpaceFree    int64
    Readonly     bool
    EventType    string // "inode_warning", "inode_critical", "space_warning", "space_critical", "readonly"
}
```

### Commands

```bash
/ccbell:inodes status                 # Show inode/filesystem status
/ccbell:inodes add /home              # Add mount point to watch
/ccbell:inodes remove /home
/ccbell:inodes inode 85               # Set inode warning threshold
/ccbell:inodes space 90               # Set space warning threshold
/ccbell:inodes test                   # Test inode sounds
```

### Output

```
$ ccbell:inodes status

=== Sound Event Inode/Filesystem Monitor ===

Status: Enabled
Inode Warning: 85%
Inode Critical: 95%
Space Warning: 90%
Space Critical: 98%
Inode Warning Sounds: Yes
Space Warning Sounds: Yes

Watched Mount Points: 3

[1] / (root)
    Filesystem: /dev/sda1
    Inodes: 3.2M / 3.2M (78%)
    Space: 45 GB / 100 GB (45%)
    Status: OK
    Sound: bundled:inode-root

[2] /home
    Filesystem: /dev/sda3
    Inodes: 2.8M / 2.8M (92%) *** WARNING ***
    Space: 85 GB / 200 GB (43%)
    Status: INODE WARNING
    Sound: bundled:inode-home

[3] /var/lib/docker
    Filesystem: /dev/vg0/lv_docker
    Inodes: 1.2M / 1.2M (67%)
    Space: 45 GB / 50 GB (91%) *** WARNING ***
    Space: 18 GB / 200 GB (9%)
    Status: SPACE WARNING
    Sound: bundled:inode-docker

Recent Events:
  [1] /home: Inode Warning (5 min ago)
       Inode usage: 92% > 85% threshold
  [2] /var/lib/docker: Space Warning (10 min ago)
       Space usage: 91% > 90% threshold
  [3] /data: Readonly (1 hour ago)
       Filesystem remounted readonly

Filesystem Statistics:
  Monitored: 3 mounts
  Warnings Today: 5
  Critical: 0

Sound Settings:
  Inode Warning: bundled:inode-warning
  Inode Critical: bundled:inode-critical
  Space Warning: bundled:space-warning
  Readonly: bundled:space-readonly

[Configure] [Add Mount] [Test All]
```

---

## Audio Player Compatibility

Inode/filesystem monitoring doesn't play sounds directly:
- Monitoring feature using df/stat
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Inode/Filesystem Monitor

```go
type InodeFilesystemMonitor struct {
    config          *InodeFilesystemMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    fsState         map[string]*FSInfo
    lastEventTime   map[string]time.Time
}

type FSInfo struct {
    MountPoint   string
    Filesystem   string
    InodeUsed    int
    InodeTotal   int64
    InodeFree    int64
    SpaceUsed    int
    SpaceTotal   int64
    SpaceFree    int64
    Readonly     bool
    LastUpdate   time.Time
}

func (m *InodeFilesystemMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fsState = make(map[string]*FSInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *InodeFilesystemMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFSState()

    for {
        select {
        case <-ticker.C:
            m.checkFSState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *InodeFilesystemMonitor) snapshotFSState() {
    m.checkFSState()
}

func (m *InodeFilesystemMonitor) checkFSState() {
    cmd := exec.Command("df", "-Ph")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentFS := m.parseDFOutput(string(output))

    for mount, info := range currentFS {
        lastInfo := m.fsState[mount]

        if lastInfo == nil {
            m.fsState[mount] = info
            continue
        }

        // Check for status changes
        m.evaluateFSEvents(mount, info, lastInfo)
        m.fsState[mount] = info
    }
}

func (m *InodeFilesystemMonitor) parseDFOutput(output string) map[string]*FSInfo {
    fsMap := make(map[string]*FSInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Filesystem") || line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 6 {
            continue
        }

        filesystem := parts[0]
        mountPoint := parts[5]

        if !m.shouldWatchMount(mountPoint) {
            continue
        }

        // Parse size
        totalStr := parts[1]
        usedStr := parts[2]
        availStr := parts[3]

        // Parse percentage
        useStr := strings.TrimSuffix(parts[4], "%")
        usePct, _ := strconv.Atoi(useStr)

        total, _ := m.parseSize(totalStr)
        used, _ := m.parseSize(usedStr)
        avail, _ := m.parseSize(availStr)

        fsMap[mountPoint] = &FSInfo{
            Filesystem: filesystem,
            MountPoint: mountPoint,
            SpaceUsed:  usePct,
            SpaceTotal: total,
            SpaceFree:  avail,
            LastUpdate: time.Now(),
        }
    }

    // Get inode info
    for mount, info := range fsMap {
        inodeInfo := m.getInodeInfo(mount)
        info.InodeUsed = inodeInfo.InodeUsed
        info.InodeTotal = inodeInfo.InodeTotal
        info.InodeFree = inodeInfo.InodeFree
    }

    return fsMap
}

func (m *InodeFilesystemMonitor) getInodeInfo(mountPoint string) *FSInfo {
    cmd := exec.Command("df", "-Pi", mountPoint)
    output, err := cmd.Output()
    if err != nil {
        return &FSInfo{}
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

        useStr := strings.TrimSuffix(parts[4], "%")
        usePct, _ := strconv.Atoi(useStr)

        total, _ := strconv.ParseInt(parts[1], 10, 64)
        free, _ := strconv.ParseInt(parts[3], 10, 64)

        return &FSInfo{
            InodeUsed:  usePct,
            InodeTotal: total,
            InodeFree:  free,
        }
    }

    return &FSInfo{}
}

func (m *InodeFilesystemMonitor) parseSize(sizeStr string) (int64, error) {
    // Handle sizes like "100G", "50M", "1T"
    sizeStr = strings.TrimSpace(sizeStr)

    multiplier := int64(1)
    if strings.HasSuffix(sizeStr, "G") {
        multiplier = 1024 * 1024 * 1024
        sizeStr = sizeStr[:len(sizeStr)-1]
    } else if strings.HasSuffix(sizeStr, "M") {
        multiplier = 1024 * 1024
        sizeStr = sizeStr[:len(sizeStr)-1]
    } else if strings.HasSuffix(sizeStr, "K") {
        multiplier = 1024
        sizeStr = sizeStr[:len(sizeStr)-1]
    } else if strings.HasSuffix(sizeStr, "T") {
        multiplier = 1024 * 1024 * 1024 * 1024
        sizeStr = sizeStr[:len(sizeStr)-1]
    }

    value, err := strconv.ParseInt(sizeStr, 10, 64)
    if err != nil {
        return 0, err
    }

    return value * multiplier, nil
}

func (m *InodeFilesystemMonitor) shouldWatchMount(mountPoint string) bool {
    if len(m.config.WatchMounts) == 0 {
        return true
    }

    for _, mnt := range m.config.WatchMounts {
        if mnt == "*" || mnt == mountPoint {
            return true
        }
    }

    return false
}

func (m *InodeFilesystemMonitor) evaluateFSEvents(mount string, newInfo *FSInfo, lastInfo *FSInfo) {
    // Check inode warning
    if newInfo.InodeUsed >= m.config.InodeCritical &&
        lastInfo.InodeUsed < m.config.InodeCritical {
        m.onInodeCritical(mount, newInfo)
    } else if newInfo.InodeUsed >= m.config.InodeWarning &&
        lastInfo.InodeUsed < m.config.InodeWarning {
        m.onInodeWarning(mount, newInfo)
    }

    // Check space warning
    if newInfo.SpaceUsed >= m.config.SpaceCritical &&
        lastInfo.SpaceUsed < m.config.SpaceCritical {
        m.onSpaceCritical(mount, newInfo)
    } else if newInfo.SpaceUsed >= m.config.SpaceWarning &&
        lastInfo.SpaceUsed < m.config.SpaceWarning {
        m.onSpaceWarning(mount, newInfo)
    }

    // Check return to normal
    if newInfo.InodeUsed < m.config.InodeWarning &&
        lastInfo.InodeUsed >= m.config.InodeWarning {
        m.onInodeNormal(mount, newInfo)
    }

    if newInfo.SpaceUsed < m.config.SpaceWarning &&
        lastInfo.SpaceUsed >= m.config.SpaceWarning {
        m.onSpaceNormal(mount, newInfo)
    }
}

func (m *InodeFilesystemMonitor) onInodeWarning(mount string, info *FSInfo) {
    if !m.config.SoundOnInodeWarning {
        return
    }

    key := fmt.Sprintf("inode_warning:%s", mount)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["inode_warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *InodeFilesystemMonitor) onInodeCritical(mount string, info *FSInfo) {
    key := fmt.Sprintf("inode_critical:%s", mount)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["inode_critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *InodeFilesystemMonitor) onSpaceWarning(mount string, info *FSInfo) {
    if !m.config.SoundOnSpaceWarning {
        return
    }

    key := fmt.Sprintf("space_warning:%s", mount)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["space_warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *InodeFilesystemMonitor) onSpaceCritical(mount string, info *FSInfo) {
    key := fmt.Sprintf("space_critical:%s", mount)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["space_critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *InodeFilesystemMonitor) onInodeNormal(mount string, info *FSInfo) {
    // Optional: sound when inode usage returns to normal
}

func (m *InodeFilesystemMonitor) onSpaceNormal(mount string, info *FSInfo) {
    // Optional: sound when space returns to normal
}

func (m *InodeFilesystemMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| df | System Tool | Free | Filesystem usage |
| stat | System Tool | Free | File/Filesystem info |

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
| macOS | Supported | Uses df, stat |
| Linux | Supported | Uses df, stat |
