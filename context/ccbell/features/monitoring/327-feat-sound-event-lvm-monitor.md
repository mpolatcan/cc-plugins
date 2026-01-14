# Feature: Sound Event LVM Monitor

Play sounds for LVM volume group and logical volume events.

## Summary

Monitor LVM volume groups, logical volumes, and snapshots, playing sounds for LVM events.

## Motivation

- Volume awareness
- Space exhaustion alerts
- Snapshot completion feedback
- VG/LV change detection

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
| Space Low | VG space low | < 20% free |
| LV Active | LV activated | lvchange -ay |
| Snapshot Merge | Merge started | snapshot merge |
| VG Extended | VG extended | vgextend |

### Configuration

```go
type LVMMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVGs          []string          `json:"watch_vgs"] // "vg01", "data-vg"
    WatchLVs          []string          `json:"watch_lvs"] // "vg01/lv_root"
    SpaceWarningPct   float64           `json:"space_warning_pct"` // 80.0 default
    SoundOnSpaceLow   bool              `json:"sound_on_space_low"]
    SoundOnActivate   bool              `json:"sound_on_activate"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}

type LVMEvent struct {
    VG          string
    LV          string
    UsedPercent float64
    FreeBytes   int64
    EventType   string // "space_low", "activated", "snapshot", "extended"
}
```

### Commands

```bash
/ccbell:lvm status                    # Show LVM status
/ccbell:lvm add vg01                  # Add VG to watch
/ccbell:lvm remove vg01
/ccbell:lvm warning 80                # Set warning threshold
/ccbell:lvm sound space <sound>
/ccbell:lvm test                      # Test LVM sounds
```

### Output

```
$ ccbell:lvm status

=== Sound Event LVM Monitor ===

Status: Enabled
Space Warning: 80%
Watched VGs: 2

[1] vg01
    Total: 500 GB
    Used: 425 GB (85%)
    Free: 75 GB
    Status: WARNING
    Sound: bundled:lvm-space

[2] data-vg
    Total: 2 TB
    Used: 500 GB (25%)
    Free: 1.5 TB
    Status: OK
    Sound: bundled:stop

Logical Volumes:
  vg01/lv_root - Active, 100 GB
  vg01/lv_home - Active, 200 GB
  data-vg/db - Active, 500 GB

Recent Events:
  [1] vg01: Space Low (5 min ago)
       85% used
  [2] data-vg: VG Extended (1 hour ago)
       Added /dev/sdc
  [3] vg01/lv_snap: Snapshot Created (2 hours ago)
       Origin: lv_root

LVM Statistics:
  Total VGs: 2
  Near capacity: 1

Sound Settings:
  Space Low: bundled:lvm-space
  Activated: bundled:stop
  Snapshot: bundled:lvm-snapshot

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

### LVM Monitor

```go
type LVMMonitor struct {
    config           *LVMMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    vgState          map[string]*VGInfo
    lastEventTime    map[string]time.Time
}

type VGInfo struct {
    VG          string
    TotalBytes  int64
    FreeBytes   int64
    UsedPercent float64
    LVs         []string
}

func (m *LVMMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.vgState = make(map[string]*VGInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LVMMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLVMState()

    for {
        select {
        case <-ticker.C:
            m.checkLVMState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LVMMonitor) snapshotLVMState() {
    cmd := exec.Command("vgs", "--units", "b", "--nosuffix", "-o", "vg_name,vg_size,vg_free,lv_count")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseVGSOutput(string(output))
}

func (m *LVMMonitor) checkLVMState() {
    cmd := exec.Command("vgs", "--units", "b", "--nosuffix", "-o", "vg_name,vg_size,vg_free,lv_count")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseVGSOutput(string(output))
}

func (m *LVMMonitor) parseVGSOutput(output string) {
    lines := strings.Split(output, "\n")
    currentVGs := make(map[string]*VGInfo)

    for _, line := range lines {
        if line == "" || strings.HasPrefix(line, "VG") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        vgName := parts[0]
        totalBytes, _ := strconv.ParseInt(parts[1], 10, 64)
        freeBytes, _ := strconv.ParseInt(parts[2], 10, 64)
        usedPercent := float64(totalBytes-freeBytes) / float64(totalBytes) * 100

        if !m.shouldWatchVG(vgName) {
            continue
        }

        // Get LVs for this VG
        lvs := m.getLVsForVG(vgName)

        info := &VGInfo{
            VG:          vgName,
            TotalBytes:  totalBytes,
            FreeBytes:   freeBytes,
            UsedPercent: usedPercent,
            LVs:         lvs,
        }

        currentVGs[vgName] = info
        m.evaluateVGState(vgName, info)
    }

    m.vgState = currentVGs
}

func (m *LVMMonitor) getLVsForVG(vgName string) []string {
    cmd := exec.Command("lvs", "--noheadings", "-o", "lv_name", vgName)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    var lvs []string
    for _, line := range strings.Split(string(output), "\n") {
        line = strings.TrimSpace(line)
        if line != "" {
            lvs = append(lvs, line)
        }
    }

    return lvs
}

func (m *LVMMonitor) evaluateVGState(vgName string, info *VGInfo) {
    lastInfo := m.vgState[vgName]

    if lastInfo == nil {
        return
    }

    // Check space threshold
    if info.UsedPercent >= m.config.SpaceWarningPct {
        if lastInfo.UsedPercent < m.config.SpaceWarningPct {
            m.onSpaceLow(vgName, info.UsedPercent, info.FreeBytes)
        }
    }

    // Check LV count change (activation/deactivation)
    if len(info.LVs) != len(lastInfo.LVs) {
        if len(info.LVs) > len(lastInfo.LVs) {
            m.onLVActivated(vgName)
        }
    }
}

func (m *LVMMonitor) shouldWatchVG(vgName string) bool {
    if len(m.config.WatchVGs) == 0 {
        return true
    }

    for _, vg := range m.config.WatchVGs {
        if vg == vgName {
            return true
        }
    }

    return false
}

func (m *LVMMonitor) onSpaceLow(vgName string, percent float64, freeBytes int64) {
    if !m.config.SoundOnSpaceLow {
        return
    }

    key := fmt.Sprintf("space:%s", vgName)
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["space_low"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LVMMonitor) onLVActivated(vgName string) {
    if !m.config.SoundOnActivate {
        return
    }

    key := fmt.Sprintf("activate:%s", vgName)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["activate"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LVMMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| vgs | System Tool | Free | VG status |
| lvs | System Tool | Free | LV status |

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
| macOS | Not Supported | No native LVM |
| Linux | Supported | Uses vgs, lvs |
| Windows | Not Supported | ccbell only supports macOS/Linux |
