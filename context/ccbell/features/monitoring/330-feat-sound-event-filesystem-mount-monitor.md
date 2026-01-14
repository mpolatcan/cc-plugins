# Feature: Sound Event File System Mount Monitor

Play sounds for mount/umount events and mount point changes.

## Summary

Monitor filesystem mount operations, mount point changes, and unmount events, playing sounds for mount events.

## Motivation

- Mount awareness
- Removable device detection
- Mount failure alerts
- Storage change feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Mount Events

| Event | Description | Example |
|-------|-------------|---------|
| Mounted | Filesystem mounted | /dev/sda1 on /mnt/data |
| Unmounted | Filesystem unmounted | /mnt/data unmounted |
| Mount Failed | Mount error | Read-only fs |
| Remount | Remount occurred | remount ro -> rw |

### Configuration

```go
type MountMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchMountPoints []string          `json:"watch_mount_points"] // "/mnt", "/home"
    WatchDevices     []string          `json:"watch_devices"] // "/dev/sd*", "/dev/nvme*"
    SoundOnMount     bool              `json:"sound_on_mount"]
    SoundOnUnmount   bool              `json:"sound_on_unmount"]
    SoundOnFail      bool              `json:"sound_on_fail"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type MountEvent struct {
    Device      string
    MountPoint  string
    FSType      string
    Options     string
    EventType   string // "mount", "unmount", "fail", "remount"
}
```

### Commands

```bash
/ccbell:mount status                  # Show mount status
/ccbell:mount add /mnt                # Add mount point to watch
/ccbell:mount remove /mnt
/ccbell:mount sound mount <sound>
/ccbell:mount sound unmount <sound>
/ccbell:mount test                    # Test mount sounds
```

### Output

```
$ ccbell:mount status

=== Sound Event Mount Monitor ===

Status: Enabled
Mount Sounds: Yes
Unmount Sounds: Yes

Watched Mount Points: 2

[1] /mnt/data (/dev/sda1)
    Type: ext4
    Options: rw,noatime
    Status: MOUNTED
    Sound: bundled:mount-add

[2] /home (/dev/sdb1)
    Type: ext4
    Options: rw
    Status: MOUNTED
    Sound: bundled:stop

Recent Events:
  [1] /mnt/data: Mounted (5 min ago)
       /dev/sda1 mounted
  [2] /home: Remounted (1 hour ago)
       Options changed
  [3] /backup: Unmounted (2 hours ago)
       Device removed

Mount Statistics:
  Total mounts: 5
  Total unmounts: 2

Sound Settings:
  Mount: bundled:mount-add
  Unmount: bundled:mount-remove
  Fail: bundled:mount-fail

[Configure] [Add Mount Point] [Test All]
```

---

## Audio Player Compatibility

Mount monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Mount Monitor

```go
type MountMonitor struct {
    config             *MountMonitorConfig
    player             *audio.Player
    running            bool
    stopCh             chan struct{}
    mountState         map[string]*MountInfo
    lastEventTime      map[string]time.Time
}

type MountInfo struct {
    Device     string
    MountPoint string
    FSType     string
    Options    string
    Mounted    bool
}

func (m *MountMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.mountState = make(map[string]*MountInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MountMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotMountState()

    for {
        select {
        case <-ticker.C:
            m.checkMountState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MountMonitor) snapshotMountState() {
    data, err := os.ReadFile("/proc/mounts")
    if err != nil {
        return
    }

    m.parseMounts(string(data))
}

func (m *MountMonitor) checkMountState() {
    data, err := os.ReadFile("/proc/mounts")
    if err != nil {
        return
    }

    m.parseMounts(string(data))
}

func (m *MountMonitor) parseMounts(data string) {
    lines := strings.Split(data, "\n")
    currentMounts := make(map[string]*MountInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        device := parts[0]
        mountPoint := parts[1]
        fsType := parts[2]
        options := parts[3]

        // Check if we should watch this mount
        if !m.shouldWatchMount(mountPoint) && !m.shouldWatchDevice(device) {
            continue
        }

        key := mountPoint
        info := &MountInfo{
            Device:     device,
            MountPoint: mountPoint,
            FSType:     fsType,
            Options:    options,
            Mounted:    true,
        }

        currentMounts[key] = info

        lastInfo := m.mountState[key]
        if lastInfo == nil {
            // New mount
            m.onMounted(info)
        } else if lastInfo.Options != options {
            // Remount
            m.onRemount(info, lastInfo)
        }
    }

    // Check for unmounted filesystems
    for key, lastInfo := range m.mountState {
        if _, exists := currentMounts[key]; !exists {
            m.onUnmounted(lastInfo)
        }
    }

    m.mountState = currentMounts
}

func (m *MountMonitor) shouldWatchMount(mountPoint string) bool {
    if len(m.config.WatchMountPoints) == 0 {
        return true
    }

    for _, mp := range m.config.WatchMountPoints {
        if strings.HasPrefix(mountPoint, mp) {
            return true
        }
    }

    return false
}

func (m *MountMonitor) shouldWatchDevice(device string) bool {
    for _, pattern := range m.config.WatchDevices {
        matched, _ := filepath.Match(pattern, filepath.Base(device))
        if matched {
            return true
        }
    }

    return false
}

func (m *MountMonitor) onMounted(info *MountInfo) {
    if !m.config.SoundOnMount {
        return
    }

    key := fmt.Sprintf("mount:%s", info.MountPoint)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["mount"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *MountMonitor) onUnmounted(info *MountInfo) {
    if !m.config.SoundOnUnmount {
        return
    }

    key := fmt.Sprintf("unmount:%s", info.MountPoint)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["unmount"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *MountMonitor) onRemount(current *MountInfo, last *MountInfo) {
    sound := m.config.Sounds["remount"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *MountMonitor) onMountFail(mountPoint string) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", mountPoint)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MountMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| /proc/mounts | File | Free | Mount information |

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
| macOS | Supported | Uses mount output parsing |
| Linux | Supported | Uses /proc/mounts |
| Windows | Not Supported | ccbell only supports macOS/Linux |
