# Feature: Sound Event LVM Status Monitor

Play sounds for LVM volume group and logical volume status changes.

## Summary

Monitor LVM volume groups, logical volumes, and physical volumes, playing sounds for LVM status changes.

## Motivation

- Volume group alerts
- Logical volume warnings
- Space usage notifications
- Snapshot creation feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### LVM Events

| Event | Description | Example |
|-------|-------------|---------|
| VG Full | Space exhausted | 0% free |
| LV Full | LV at capacity | 95% used |
| VG Resized | VG extended | PV added |
| Snapshot Created | Snap created | Backup snap |
| Snapshot Removed | Snap removed | Cleanup |

### Configuration

```go
type LVMStatusMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVGs          []string          `json:"watch_vgs"` // Volume groups
    WatchLVs          []string          `json:"watch_lvs"` // Logical volumes
    UsageWarning      int               `json:"usage_warning_percent"` // 80 default
    UsageCritical     int               `json:"usage_critical_percent"` // 95 default
    SoundOnWarning    bool              `json:"sound_on_warning"]
    SoundOnCritical   bool              `json:"sound_on_critical"]
    SoundOnResize     bool              `json:"sound_on_resize"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type LVMStatusEvent struct {
    VGName       string
    LVName       string
    UsedPercent  float64
    FreeBytes    int64
    TotalBytes   int64
    EventType    string // "vg_warning", "vg_critical", "lv_warning", "lv_critical", "resize"
}
```

### Commands

```bash
/ccbell:lvm status                   # Show LVM status
/ccbell:lvm add vg0                  # Add VG to watch
/ccbell:lvm remove vg0
/ccbell:lvm sound warning <sound>
/ccbell:lvm sound critical <sound>
/ccbell:lvm test                     # Test LVM sounds
```

### Output

```
$ ccbell:lvm status

=== Sound Event LVM Status Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%

Watched Volume Groups: 2

[1] vg0 (main)
    Total: 500 GB
    Used: 385 GB (77%)
    Free: 115 GB (23%)
    Status: OK
    Logical Volumes: 4
    Sound: bundled:stop

[2] vg1 (backup)
    Total: 1 TB
    Used: 950 GB (95%)
    Free: 50 GB (5%)
    Status: CRITICAL
    Logical Volumes: 2
    Sound: bundled:lvm-warning

Logical Volumes:

[1] vg0/lv_root
    Size: 50 GB
    Used: 42 GB (84%)
    Status: WARNING
    Sound: bundled:stop

[2] vg0/lv_home
    Size: 200 GB
    Used: 145 GB (72%)
    Status: OK
    Sound: bundled:stop

[3] vg1/lv_data
    Size: 800 GB
    Used: 780 GB (97%)
    Status: CRITICAL
    Sound: bundled:lvm-warning

Recent Events:
  [1] vg1: Critical Usage (1 hour ago)
       95% used
  [2] lv_data: Critical Usage (2 hours ago)
       97% used
  [3] vg0: Resized (1 day ago)
       Extended by 100 GB

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Resize: bundled:stop

[Configure] [Add VG] [Test All]
```

---

## Audio Player Compatibility

LVM monitoring doesn't play sounds directly:
- Monitoring feature using LVM tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### LVM Status Monitor

```go
type LVMStatusMonitor struct {
    config           *LVMStatusMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    vgState          map[string]*VGStatus
    lvState          map[string]*LVStatus
    lastWarningTime  map[string]time.Time
}

type VGStatus struct {
    Name        string
    TotalBytes  int64
    FreeBytes   int64
    UsedPercent float64
    LVCount     int
}

type LVStatus struct {
    VGName      string
    LVName      string
    SizeBytes   int64
    UsedPercent float64
}
```

```go
func (m *LVMStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vgState = make(map[string]*VGStatus)
    m.lvState = make(map[string]*LVStatus)
    m.lastWarningTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LVMStatusMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLVMStatus()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LVMStatusMonitor) checkLVMStatus() {
    // Check volume groups
    m.checkVolumeGroups()

    // Check logical volumes
    m.checkLogicalVolumes()
}

func (m *LVMStatusMonitor) checkVolumeGroups() {
    cmd := exec.Command("vgs", "--units", "b", "--noheadings", "-o", "vg_name,vg_size,vg_free,lv_count")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        vgName := parts[0]
        totalBytes, _ := strconv.ParseInt(parts[1], 10, 64)
        freeBytes, _ := strconv.ParseInt(parts[2], 10, 64)
        lvCount, _ := strconv.Atoi(parts[3])

        usedBytes := totalBytes - freeBytes
        usedPercent := float64(usedBytes) / float64(totalBytes) * 100

        vgStatus := &VGStatus{
            Name:        vgName,
            TotalBytes:  totalBytes,
            FreeBytes:   freeBytes,
            UsedPercent: usedPercent,
            LVCount:     lvCount,
        }

        // Check if we should watch this VG
        if len(m.config.WatchVGs) > 0 {
            found := false
            for _, watchVG := range m.config.WatchVGs {
                if vgName == watchVG {
                    found = true
                    break
                }
            }
            if !found {
                continue
            }
        }

        m.evaluateVGStatus(vgName, vgStatus)
    }
}

func (m *LVMStatusMonitor) checkLogicalVolumes() {
    cmd := exec.Command("lvs", "--units", "b", "--noheadings", "-o", "vg_name,lv_name,lv_size")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        vgName := parts[0]
        lvName := parts[1]
        sizeBytes, _ := strconv.ParseInt(parts[2], 10, 64)

        // Get LV usage (requires additional commands)
        lvPath := fmt.Sprintf("/dev/%s/%s", vgName, lvName)
        usedPercent := m.getLVUsage(vgName, lvName)

        lvKey := fmt.Sprintf("%s/%s", vgName, lvName)
        lvStatus := &LVStatus{
            VGName:      vgName,
            LVName:      lvName,
            SizeBytes:   sizeBytes,
            UsedPercent: usedPercent,
        }

        // Check if we should watch this LV
        if len(m.config.WatchLVs) > 0 {
            found := false
            for _, watchLV := range m.config.WatchLVs {
                if lvName == watchLV {
                    found = true
                    break
                }
            }
            if !found {
                continue
            }
        }

        m.evaluateLVStatus(lvKey, lvStatus)
    }
}

func (m *LVMStatusMonitor) getLVUsage(vgName string, lvName string) float64 {
    // Get filesystem usage for the LV
    lvPath := fmt.Sprintf("/dev/mapper/%s-%s", vgName, lvName)

    cmd := exec.Command("df", "-B1", "--output=pcent", lvPath)
    output, err := cmd.Output()
    if err != nil {
        return 0
    }

    percentStr := strings.TrimSpace(string(output))
    percentStr = strings.TrimSuffix(percentStr, "%")

    percent, _ := strconv.ParseFloat(percentStr, 64)
    return percent
}

func (m *LVMStatusMonitor) evaluateVGStatus(vgName string, status *VGStatus) {
    lastState := m.vgState[vgName]

    if lastState == nil {
        m.vgState[vgName] = status
        return
    }

    // Check for critical usage
    if status.UsedPercent >= float64(m.config.UsageCritical) {
        if lastState.UsedPercent < float64(m.config.UsageCritical) {
            m.onVGCritical(vgName, status)
        }
    } else if status.UsedPercent >= float64(m.config.UsageWarning) {
        if lastState.UsedPercent < float64(m.config.UsageWarning) {
            m.onVGWarning(vgName, status)
        }
    }

    m.vgState[vgName] = status
}

func (m *LVMStatusMonitor) evaluateLVStatus(lvKey string, status *LVStatus) {
    lastState := m.lvState[lvKey]

    if lastState == nil {
        m.lvState[lvKey] = status
        return
    }

    // Check for critical usage
    if status.UsedPercent >= float64(m.config.UsageCritical) {
        if lastState.UsedPercent < float64(m.config.UsageCritical) {
            m.onLVCritical(status)
        }
    } else if status.UsedPercent >= float64(m.config.UsageWarning) {
        if lastState.UsedPercent < float64(m.config.UsageWarning) {
            m.onLVWarning(status)
        }
    }

    m.lvState[lvKey] = status
}

func (m *LVMStatusMonitor) onVGWarning(vgName string, status *VGStatus) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("vg_warning:%s", vgName)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LVMStatusMonitor) onVGCritical(vgName string, status *VGStatus) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("vg_critical:%s", vgName)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *LVMStatusMonitor) onLVWarning(status *LVStatus) {
    if !m.config.SoundOnWarning {
        return
    }

    key := fmt.Sprintf("lv_warning:%s/%s", status.VGName, status.LVName)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LVMStatusMonitor) onLVCritical(status *LVStatus) {
    if !m.config.SoundOnCritical {
        return
    }

    key := fmt.Sprintf("lv_critical:%s/%s", status.VGName, status.LVName)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["critical"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *LVMStatusMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| vgs | System Tool | Free | LVM VG status |
| lvs | System Tool | Free | LVM LV status |
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
| macOS | Not Supported | LVM not native to macOS |
| Linux | Supported | Uses vgs, lvs, df |
| Windows | Not Supported | ccbell only supports macOS/Linux |
