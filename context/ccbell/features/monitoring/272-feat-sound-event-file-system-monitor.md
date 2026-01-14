# Feature: Sound Event File System Monitor

Play sounds for file system events and storage changes.

## Summary

Monitor file system changes, disk usage, and storage events, playing sounds for file system activity.

## Motivation

- Disk space warnings
- File change detection
- Storage capacity alerts
- Mount/unmount events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### File System Events

| Event | Description | Example |
|-------|-------------|---------|
| Disk Low | Space < 10% | 8% free |
| Disk Critical | Space < 5% | 3% free |
| Mount | Volume mounted | USB inserted |
| Unmount | Volume unmounted | USB ejected |
| Large File | File > 1GB | Download detected |

### Configuration

```go
type FileSystemMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPaths        []string          `json:"watch_paths"` // "/", "/home"
    WarningThreshold  int               `json:"warning_threshold_percent"` // 10 default
    CriticalThreshold int               `json:"critical_threshold_percent"` // 5 default
    LargeFileThreshold int64            `json:"large_file_threshold_mb"` // 1024 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnMount      bool              `json:"sound_on_mount"`
    SoundOnUnmount    bool              `json:"sound_on_unmount"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type FileSystemEvent struct {
    MountPoint   string
    DeviceName   string
    UsedPercent  float64
    FreeBytes    int64
    TotalBytes   int64
    EventType    string // "warning", "critical", "mount", "unmount"
}
```

### Commands

```bash
/ccbell:filesystem status              # Show filesystem status
/ccbell:filesystem add "/"             # Add path to watch
/ccbell:filesystem remove "/"
/ccbell:filesystem sound warning <sound>
/ccbell:filesystem sound critical <sound>
/ccbell:filesystem test                # Test filesystem sounds
```

### Output

```
$ ccbell:filesystem status

=== Sound Event File System Monitor ===

Status: Enabled
Warning: 10%
Critical: 5%

Watched Paths: 3

[1] / (root)
    Device: /dev/disk1s5
    Used: 78% (112 GB / 145 GB)
    Available: 33 GB
    Status: OK
    Sound: bundled:stop

[2] /home
    Device: /dev/disk1s6
    Used: 45% (90 GB / 200 GB)
    Available: 110 GB
    Status: OK
    Sound: bundled:stop

[3] /Volumes/Time Machine
    Device: /dev/disk2s1
    Used: 92% (1.5 TB / 1.6 TB)
    Available: 120 GB
    Status: OK
    Sound: bundled:stop

Recent Events:
  [1] /Volumes/USB: Mounted (5 min ago)
  [2] /: Warning (1 day ago)
       12% free space
  [3] /Volumes/Backup: Unmounted (2 days ago)

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Mount: bundled:stop
  Unmount: bundled:stop

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

File system monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### File System Monitor

```go
type FileSystemMonitor struct {
    config           *FileSystemMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    fsState          map[string]*FSStatus
    lastWarningTime  time.Time
    lastCriticalTime time.Time
}

type FSStatus struct {
    MountPoint  string
    DeviceName  string
    UsedPercent float64
    FreeBytes   int64
    TotalBytes  int64
}
```

```go
func (m *FileSystemMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fsState = make(map[string]*FSStatus)
    go m.monitor()
}

func (m *FileSystemMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkFileSystems()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FileSystemMonitor) checkFileSystems() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinFileSystems()
    } else {
        m.checkLinuxFileSystems()
    }
}

func (m *FileSystemMonitor) checkDarwinFileSystems() {
    // Use df to get disk usage
    cmd := exec.Command("df", "-h")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Filesystem") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 9 {
            continue
        }

        mountPoint := parts[8]
        usedPercent := strings.TrimSuffix(parts[4], "%")

        // Check if we should watch this mount point
        if !m.shouldWatch(mountPoint) {
            continue
        }

        used, _ := strconv.ParseFloat(usedPercent, 64)
        status := &FSStatus{
            MountPoint:  mountPoint,
            DeviceName:  parts[0],
            UsedPercent: used,
        }

        m.evaluateFileSystem(status)
    }

    // Check for mounted volumes
    m.checkMountedVolumes()
}

func (m *FileSystemMonitor) checkLinuxFileSystems() {
    // Use df to get disk usage
    cmd := exec.Command("df", "-h", "-T")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "Filesystem") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 7 {
            continue
        }

        mountPoint := parts[6]
        fsType := parts[1]

        // Skip virtual filesystems
        if fsType == "proc" || fsType == "sysfs" || fsType == "devpts" ||
           fsType == "tmpfs" || fsType == "cgroup" || fsType == "cgroup2" ||
           fsType == "pstore" || fsType == "securityfs" || fsType == "debugfs" ||
           fsType == "hugetlbfs" || fsType == "mqueue" || fsType == "fusectl" {
            continue
        }

        usedPercent := strings.TrimSuffix(parts[4], "%")

        if !m.shouldWatch(mountPoint) {
            continue
        }

        used, _ := strconv.ParseFloat(usedPercent, 64)
        status := &FSStatus{
            MountPoint:  mountPoint,
            DeviceName:  parts[0],
            UsedPercent: used,
        }

        m.evaluateFileSystem(status)
    }

    // Check for mounted volumes
    m.checkMountedVolumes()
}

func (m *FileSystemMonitor) shouldWatch(mountPoint string) bool {
    if len(m.config.WatchPaths) == 0 {
        return true
    }

    for _, path := range m.config.WatchPaths {
        if mountPoint == path || strings.HasPrefix(mountPoint, path) {
            return true
        }
    }

    return false
}

func (m *FileSystemMonitor) checkMountedVolumes() {
    // Get current mounts
    cmd := exec.Command("mount")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, " on ", 2)
        if len(parts) < 2 {
            continue
        }

        device := parts[0]
        mountPoint := parts[1]
        mountPoint = strings.SplitN(mountPoint, " ", 2)[0] // Remove options

        key := device
        lastState := m.fsState[key]

        if lastState == nil {
            // New mount
            m.fsState[key] = &FSStatus{
                MountPoint: mountPoint,
                DeviceName: device,
            }
            m.onMount(device, mountPoint)
        }
    }
}

func (m *FileSystemMonitor) evaluateFileSystem(status *FSStatus) {
    key := status.MountPoint
    lastState := m.fsState[key]

    if lastState == nil {
        m.fsState[key] = status
        return
    }

    // Check thresholds
    if status.UsedPercent >= float64(m.config.CriticalThreshold) {
        if lastState.UsedPercent < float64(m.config.CriticalThreshold) {
            m.onCriticalDisk(status)
        }
    } else if status.UsedPercent >= float64(m.config.WarningThreshold) {
        if lastState.UsedPercent < float64(m.config.WarningThreshold) {
            m.onWarningDisk(status)
        }
    }

    m.fsState[key] = status
}

func (m *FileSystemMonitor) onWarningDisk(status *FSStatus) {
    if !m.config.SoundOnWarning {
        return
    }

    if time.Since(m.lastWarningTime) < 24*time.Hour {
        return
    }

    m.lastWarningTime = time.Now()

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *FileSystemMonitor) onCriticalDisk(status *FSStatus) {
    if !m.config.SoundOnCritical {
        return
    }

    if time.Since(m.lastCriticalTime) < 24*time.Hour {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *FileSystemMonitor) onMount(device string, mountPoint string) {
    if !m.config.SoundOnMount {
        return
    }

    sound := m.config.Sounds["mount"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *FileSystemMonitor) onUnmount(device string, mountPoint string) {
    if !m.config.SoundOnUnmount {
        return
    }

    sound := m.config.Sounds["unmount"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| df | System Tool | Free | Disk usage |
| mount | System Tool | Free | Mount info |

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
| macOS | Supported | Uses df, mount |
| Linux | Supported | Uses df, mount |
| Windows | Not Supported | ccbell only supports macOS/Linux |
