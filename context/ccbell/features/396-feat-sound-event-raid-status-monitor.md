# Feature: Sound Event RAID Status Monitor

Play sounds for RAID array status changes, disk failures, and rebuild events.

## Summary

Monitor RAID arrays for degraded state, disk failures, and rebuild progress, playing sounds for RAID events.

## Motivation

- Storage redundancy alerts
- Disk failure detection
- Rebuild completion notifications
- Array degradation awareness
- Data protection feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### RAID Status Events

| Event | Description | Example |
|-------|-------------|---------|
| Array Degraded | Disk failed | 1 disk missing |
| Array Failed | Multiple failures | critical |
| Disk Failed | Individual disk failed | sdd failed |
| Rebuild Started | Resyncing array | rebuilding |
| Rebuild Completed | Sync finished | 100% complete |
| Disk Added | New disk inserted | spare added |

### Configuration

```go
type RAIDStatusMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchArrays       []string          `json:"watch_arrays"` // "/dev/md0", "*"
    WatchLevels       []int             `json:"watch_levels"` // 0, 1, 5, 6, 10
    SoundOnDegraded   bool              `json:"sound_on_degraded"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnRebuild    bool              `json:"sound_on_rebuild"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:raid status                   # Show RAID status
/ccbell:raid add /dev/md0             # Add array to watch
/ccbell:raid remove /dev/md0
/ccbell:raid sound degraded <sound>
/ccbell:raid sound failed <sound>
/ccbell:raid test                     # Test RAID sounds
```

### Output

```
$ ccbell:raid status

=== Sound Event RAID Status Monitor ===

Status: Enabled
Degraded Sounds: Yes
Failed Sounds: Yes
Rebuild Sounds: Yes

Watched Arrays: 2

RAID Array Status:

[1] /dev/md0 (RAID-5, 4 disks)
    Status: DEGRADED
    Active Disks: 3/4
    Disk(s) Failed: /dev/sdd
    Rebuild Progress: N/A
    Last Check: 5 min ago
    Sound: bundled:raid-md0 *** DEGRADED ***

[2] /dev/md1 (RAID-1, 2 disks)
    Status: ACTIVE
    Active Disks: 2/2
    Rebuild Progress: N/A
    Last Check: 5 min ago
    Sound: bundled:raid-md1

Disk Status:
  /dev/sda: ACTIVE
  /dev/sdb: ACTIVE
  /dev/sdc: ACTIVE
  /dev/sdd: FAILED
  /dev/sde: SPARE

Recent Events:
  [1] /dev/md0: Array Degraded (10 min ago)
       /dev/sdd failed
  [2] /dev/md0: Disk Failed (10 min ago)
       I/O errors detected
  [3] /dev/md1: Rebuild Completed (1 day ago)
       100% complete

RAID Statistics:
  Active Arrays: 1
  Degraded: 1
  Failed: 0
  Total Disks: 6

Sound Settings:
  Degraded: bundled:raid-degraded
  Failed: bundled:raid-failed
  Rebuild: bundled:raid-rebuild
  Complete: bundled:raid-complete

[Configure] [Add Array] [Test All]
```

---

## Audio Player Compatibility

RAID monitoring doesn't play sounds directly:
- Monitoring feature using mdadm/smartctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### RAID Status Monitor

```go
type RAIDStatusMonitor struct {
    config          *RAIDStatusMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    arrayState      map[string]*RAIDArrayInfo
    lastEventTime   map[string]time.Time
}

type RAIDArrayInfo struct {
    Device     string
    Level      int
    Status     string // "active", "clean", "degraded", "failed", "resyncing"
    Disks      int
    ActiveDisks int
    FailedDisks int
    RebuildPct float64
    LastCheck  time.Time
}

func (m *RAIDStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.arrayState = make(map[string]*RAIDArrayInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *RAIDStatusMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotArrayState()

    for {
        select {
        case <-ticker.C:
            m.checkArrayState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *RAIDStatusMonitor) snapshotArrayState() {
    m.checkArrayState()
}

func (m *RAIDStatusMonitor) checkArrayState() {
    // List RAID arrays
    arrays := m.listRAIDArrays()

    for _, device := range arrays {
        m.checkArray(device)
    }
}

func (m *RAIDStatusMonitor) listRAIDArrays() []string {
    var arrays []string

    // Check /proc/mdstat
    cmd := exec.Command("cat", "/proc/mdstat")
    output, err := cmd.Output()
    if err != nil {
        return arrays
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "md") {
            parts := strings.Fields(line)
            if len(parts) > 0 {
                arrays = append(arrays, "/dev/"+parts[0])
            }
        }
    }

    return arrays
}

func (m *RAIDStatusMonitor) checkArray(device string) {
    info := &RAIDArrayInfo{
        Device:    device,
        LastCheck: time.Now(),
    }

    // Get detailed status
    cmd := exec.Command("mdadm", "--detail", device)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.Contains(line, "State :") {
            status := strings.TrimPrefix(line, "State : ")
            info.Status = m.parseRAIDStatus(status)
        } else if strings.Contains(line, "Raid Level :") {
            level := strings.TrimPrefix(line, "Raid Level : ")
            info.Level, _ = strconv.Atoi(level)
        } else if strings.Contains(line, "Active Devices :") {
            active := strings.TrimPrefix(line, "Active Devices : ")
            info.ActiveDisks, _ = strconv.Atoi(active)
        } else if strings.Contains(line, "Working Devices :") {
            working := strings.TrimPrefix(line, "Working Devices : ")
            info.Disks, _ = strconv.Atoi(working)
        } else if strings.Contains(line, "Failed Devices :") {
            failed := strings.TrimPrefix(line, "Failed Devices : ")
            info.FailedDisks, _ = strconv.Atoi(failed)
        } else if strings.Contains(line, "Resync Status :") {
            // Parse: "66% complete"
            resync := strings.TrimPrefix(line, "Resync Status : ")
            re := regexp.MustEach(`(\d+)%`)
            matches := re.FindAllStringSubmatch(resync, -1)
            if len(matches) > 0 {
                info.RebuildPct, _ = strconv.ParseFloat(matches[0][1], 64)
            }
        }
    }

    m.processArrayStatus(device, info)
}

func (m *RAIDStatusMonitor) parseRAIDStatus(status string) string {
    status = strings.ToLower(status)
    if strings.Contains(status, "clean") {
        return "active"
    } else if strings.Contains(status, "degraded") || strings.Contains(status, "recovering") {
        return "degraded"
    } else if strings.Contains(status, "failed") || strings.Contains(status, "faulty") {
        return "failed"
    } else if strings.Contains(status, "resync") || strings.Contains(status, "reshape") {
        return "resyncing"
    }
    return status
}

func (m *RAIDStatusMonitor) processArrayStatus(device string, info *RAIDArrayInfo) {
    lastInfo := m.arrayState[device]

    if lastInfo == nil {
        m.arrayState[device] = info
        return
    }

    // Check for status changes
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "degraded":
            if info.FailedDisks > lastInfo.FailedDisks {
                m.onArrayDegraded(device, info)
            }
        case "failed":
            m.onArrayFailed(device, info)
        case "active":
            if lastInfo.Status == "degraded" {
                m.onArrayRecovered(device, info)
            }
        case "resyncing":
            if lastInfo.Status != "resyncing" {
                m.onRebuildStarted(device, info)
            }
        }
    }

    // Check for rebuild completion
    if info.Status == "active" && lastInfo.Status == "resyncing" && info.RebuildPct >= 100 {
        m.onRebuildCompleted(device, info)
    }

    m.arrayState[device] = info
}

func (m *RAIDStatusMonitor) onArrayDegraded(device string, info *RAIDArrayInfo) {
    if !m.config.SoundOnDegraded {
        return
    }

    key := fmt.Sprintf("degraded:%s", device)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["degraded"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *RAIDStatusMonitor) onArrayFailed(device string, info *RAIDArrayInfo) {
    if !m.config.SoundOnFailed {
        return
    }

    key := fmt.Sprintf("failed:%s", device)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *RAIDStatusMonitor) onArrayRecovered(device string, info *RAIDArrayInfo) {
    // Optional: sound when array recovers
}

func (m *RAIDStatusMonitor) onRebuildStarted(device string, info *RAIDArrayInfo) {
    if !m.config.SoundOnRebuild {
        return
    }

    key := fmt.Sprintf("rebuild:%s", device)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["rebuild"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *RAIDStatusMonitor) onRebuildCompleted(device string, info *RAIDArrayInfo) {
    if !m.config.SoundOnComplete {
        return
    }

    key := fmt.Sprintf("complete:%s", device)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["complete"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *RAIDStatusMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| mdadm | System Tool | Free | RAID management |
| /proc/mdstat | Linux Path | Free | RAID status |

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
| macOS | Not Supported | No native RAID support |
| Linux | Supported | Uses mdadm, /proc/mdstat |
