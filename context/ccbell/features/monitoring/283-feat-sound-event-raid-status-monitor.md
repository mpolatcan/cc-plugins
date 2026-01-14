# Feature: Sound Event RAID Status Monitor

Play sounds for RAID array status changes and degradation events.

## Summary

Monitor RAID array status, disk failures, and rebuild events, playing sounds for RAID status changes.

## Motivation

- RAID degradation alerts
- Rebuild completion feedback
- Disk failure warnings
- Array offline detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### RAID Events

| Event | Description | Example |
|-------|-------------|---------|
| Array Degraded | Disk failed | 1 disk missing |
| Array Offline | All disks down | Array offline |
| Rebuild Started | Recovery begun | Resync started |
| Rebuild Complete | Recovery done | Resync finished |
| Disk Added | Disk replaced | New member |

### Configuration

```go
type RAIDStatusMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchArrays        []string          `json:"watch_arrays"` // Array names or paths
    SoundOnDegraded    bool              `json:"sound_on_degraded"]
    SoundOnOffline     bool              `json:"sound_on_offline"]
    SoundOnRebuild     bool              `json:"sound_on_rebuild"]
    SoundOnComplete    bool              `json:"sound_on_complete"]
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type RAIDStatusEvent struct {
    ArrayName   string
    Level       string // "0", "1", "5", "6", "10"
    State       string // "active", "degraded", "offline", "resyncing"
    DisksTotal  int
    DisksActive int
    Progress    float64 // 0-100 for rebuild
}
```

### Commands

```bash
/ccbell:raid status                   # Show RAID status
/ccbell:raid add "RAID1"              # Add array to watch
/ccbell:raid remove "RAID1"
/ccbell:raid sound degraded <sound>
/ccbell:raid sound rebuild <sound>
/ccbell:raid test                    # Test RAID sounds
```

### Output

```
$ ccbell:raid status

=== Sound Event RAID Status Monitor ===

Status: Enabled
Degraded Sounds: Yes
Rebuild Sounds: Yes

Watched Arrays: 2

[1] RAID1 (Backup)
    Level: 1 (Mirror)
    Disks: 2/2 Active
    State: ACTIVE
    Status: OK
    Sound: bundled:stop

[2] RAID5 (Data)
    Level: 5 (Striping with Parity)
    Disks: 3/4 Active
    State: DEGRADED
    Missing: /dev/sdc
    Rebuild Progress: 45%
    Rebuild ETA: 2 hours
    Status: WARNING
    Sound: bundled:raid-warning

Recent Events:
  [1] RAID5: Disk Failed (1 hour ago)
       /dev/sdc removed
  [2] RAID5: Rebuild Started (1 hour ago)
       45% complete
  [3] RAID1: Check Passed (1 day ago)

Array Details:
  RAID1:
    - /dev/sda: Active
    - /dev/sdb: Active

  RAID5:
    - /dev/sda: Active
    - /dev/sdb: Active
    - /dev/sdd: Active
    - /dev/sdc: MISSING

Sound Settings:
  Degraded: bundled:stop
  Offline: bundled:stop
  Rebuild: bundled:stop
  Complete: bundled:stop

[Configure] [Add Array] [Test All]
```

---

## Audio Player Compatibility

RAID monitoring doesn't play sounds directly:
- Monitoring feature using RAID management tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### RAID Status Monitor

```go
type RAIDStatusMonitor struct {
    config           *RAIDStatusMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    arrayState       map[string]*RAIDArray
    lastCheckTime    map[string]time.Time
}

type RAIDArray struct {
    Name       string
    Level      string
    State      string
    DisksTotal int
    DisksActive int
    Progress   float64
}
```

```go
func (m *RAIDStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.arrayState = make(map[string]*RAIDArray)
    m.lastCheckTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *RAIDStatusMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkRAIDStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *RAIDStatusMonitor) checkRAIDStatus() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinRAID()
    } else {
        m.checkLinuxRAID()
    }
}

func (m *RAIDStatusMonitor) checkDarwinRAID() {
    // Use diskutil AppleRAID list
    cmd := exec.Command("diskutil", "appleRAID", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDiskutilOutput(string(output))
}

func (m *RAIDStatusMonitor) checkLinuxRAID() {
    // Check for mdadm arrays
    cmd := exec.Command("cat", "/proc/mdstat")
    output, err := cmd.Output()
    if err == nil {
        m.parseMDStatOutput(string(output))
    }

    // Also check with mdadm --detail
    for _, array := range m.config.WatchArrays {
        m.checkMDADMDetail(array)
    }
}

func (m *RAIDStatusMonitor) parseDiskutilOutput(output string) {
    lines := strings.Split(output, "\n")
    var currentArray *RAIDArray

    for _, line := range lines {
        if strings.HasPrefix(line, "   AppleRAID") {
            // New array
            parts := strings.Fields(line)
            if len(parts) >= 3 {
                currentArray = &RAIDArray{
                    Name: parts[2],
                }
            }
        } else if currentArray != nil && strings.Contains(line, "Member Count") {
            // Parse member count
            re := regexp.MustCompile(`(\d+)`)
            match := re.FindStringSubmatch(line)
            if len(match) >= 1 {
                if count, err := strconv.Atoi(match[1]); err == nil {
                    currentArray.DisksTotal = count
                }
            }
        } else if currentArray != nil && strings.Contains(line, "Status") {
            // Parse status
            if strings.Contains(line, "Online") || strings.Contains(line, "Active") {
                currentArray.State = "active"
            } else if strings.Contains(line, "Degraded") {
                currentArray.State = "degraded"
            }
            m.evaluateArray(currentArray)
            currentArray = nil
        }
    }
}

func (m *RAIDStatusMonitor) parseMDStatOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "md") {
            // Parse array line: "md0 : active raid1 sda[0] sdb[1]"
            parts := strings.Fields(line)
            if len(parts) < 3 {
                continue
            }

            arrayName := parts[0]
            array := &RAIDArray{
                Name: arrayName,
            }

            // Determine state
            if strings.Contains(line, "active") {
                array.State = "active"
            } else if strings.Contains(line, "resync") || strings.Contains(line, "recover") {
                array.State = "resyncing"
            } else if strings.Contains(line, "inactive") {
                array.State = "inactive"
            }

            // Count disks
            for _, part := range parts[2:] {
                if strings.HasSuffix(part, "[") || strings.HasSuffix(part, "]") {
                    array.DisksTotal++
                    if !strings.Contains(part, "[F]") {
                        array.DisksActive++
                    }
                }
            }

            m.evaluateArray(array)
        }
    }
}

func (m *RAIDStatusMonitor) checkMDADMDetail(arrayName string) {
    cmd := exec.Command("mdadm", "--detail", "/dev/"+arrayName)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseMDADMOutput(string(output), arrayName)
}

func (m *RAIDStatusMonitor) parseMDADMOutput(output string, arrayName string) {
    array := &RAIDArray{
        Name: arrayName,
    }

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "State :") {
            state := strings.TrimPrefix(line, "State : ")
            if strings.Contains(state, "clean") {
                array.State = "active"
            } else if strings.Contains(state, "degraded") {
                array.State = "degraded"
            } else if strings.Contains(state, "resyncing") {
                array.State = "resyncing"
            }
        } else if strings.HasPrefix(line, "Raid Level :") {
            array.Level = strings.TrimPrefix(line, "Raid Level : ")
        }
    }

    m.evaluateArray(array)
}

func (m *RAIDStatusMonitor) evaluateArray(array *RAIDArray) {
    lastState := m.arrayState[array.Name]

    // Check if we should watch this array
    if len(m.config.WatchArrays) > 0 {
        found := false
        for _, watchArray := range m.config.WatchArrays {
            if array.Name == watchArray {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    if lastState == nil {
        m.arrayState[array.Name] = array
        return
    }

    // Detect state changes
    if lastState.State != array.State {
        switch array.State {
        case "degraded":
            if lastState.State == "active" {
                m.onArrayDegraded(array)
            }
        case "inactive":
            if lastState.State != "inactive" {
                m.onArrayOffline(array)
            }
        case "resyncing":
            if lastState.State != "resyncing" {
                m.onRebuildStarted(array)
            }
        case "active":
            if lastState.State == "resyncing" {
                m.onRebuildComplete(array)
            }
        }
    }

    // Update progress for resyncing arrays
    if array.State == "resyncing" && array.Progress > lastState.Progress {
        // Progress update
    }

    m.arrayState[array.Name] = array
}

func (m *RAIDStatusMonitor) onArrayDegraded(array *RAIDArray) {
    if !m.config.SoundOnDegraded {
        return
    }

    sound := m.config.Sounds["degraded"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *RAIDStatusMonitor) onArrayOffline(array *RAIDArray) {
    if !m.config.SoundOnOffline {
        return
    }

    sound := m.config.Sounds["offline"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}

func (m *RAIDStatusMonitor) onRebuildStarted(array *RAIDArray) {
    if !m.config.SoundOnRebuild {
        return
    }

    sound := m.config.Sounds["rebuild"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *RAIDStatusMonitor) onRebuildComplete(array *RAIDArray) {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| diskutil | System Tool | Free | macOS RAID management |
| mdadm | System Tool | Free | Linux RAID management |
| /proc/mdstat | File | Free | Linux RAID status |

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
| macOS | Supported | Uses diskutil |
| Linux | Supported | Uses mdadm, /proc/mdstat |
| Windows | Not Supported | ccbell only supports macOS/Linux |
