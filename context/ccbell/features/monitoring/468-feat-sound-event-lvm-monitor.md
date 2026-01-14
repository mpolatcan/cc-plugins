# Feature: Sound Event LVM Monitor

Play sounds for LVM volume group changes, volume扩容, and physical disk events.

## Summary

Monitor LVM (Logical Volume Manager) for volume group status, logical volume changes, and physical volume issues, playing sounds for LVM events.

## Motivation

- LVM awareness
- Volume changes
- Storage扩容 alerts
- VG health monitoring
- PV failure detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### LVM Events

| Event | Description | Example |
|-------|-------------|---------|
| VG Full | Volume group full | 95% used |
| VG Extended | VG extended | +100GB |
| LV Resized | LV size changed | resized |
| PV Removed | Physical volume removed | removed |
| PV Failed | Physical volume failed | failed |
| Mirror Broken | Mirror failed | broken |

### Configuration

```go
type LVMMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchVGs          []string          `json:"watch_vgs"` // "vg0", "data_vg", "*"
    WarningPercent    int               `json:"warning_percent"` // 80 default
    CriticalPercent   int               `json:"critical_percent"` // 95 default
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnResize     bool              `json:"sound_on_resize"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:lvm status                  # Show LVM status
/ccbell:lvm add vg0                 # Add VG to watch
/ccbell:lvm warning 80              # Set warning threshold
/ccbell:lvm sound warning <sound>
/ccbell:lvm test                    # Test LVM sounds
```

### Output

```
$ ccbell:lvm status

=== Sound Event LVM Monitor ===

Status: Enabled
Warning: 80%
Critical: 95%

LVM Status:

[1] vg0 (rootvg)
    Status: HEALTHY
    Total: 500 GB
    Used: 350 GB (70%)
    Free: 150 GB (30%)
    LVs: 5
    PVs: 2
    Sound: bundled:lvm-vg0

[2] data_vg (datavg)
    Status: WARNING *** WARNING ***
    Total: 2 TB
    Used: 1.7 TB (85%)
    Free: 300 GB (15%)
    LVs: 12
    PVs: 4
    Sound: bundled:lvm-data *** WARNING ***

Recent Events:

[1] data_vg: VG Full Warning (5 min ago)
       85% used > 80% threshold
       Sound: bundled:lvm-warning
  [2] vg0: LV Resized (1 hour ago)
       /dev/vg0/lv_home resized to 200GB
       Sound: bundled:lvm-resize
  [3] data_vg: PV Added (2 hours ago)
       /dev/sdd added to data_vg
       Sound: bundled:lvm-pv-add

LVM Statistics:
  Total VGs: 2
  Healthy: 1
  Warning: 1
  Total LVs: 17

Sound Settings:
  Warning: bundled:lvm-warning
  Critical: bundled:lvm-critical
  Resize: bundled:lvm-resize
  PV: bundled:lvm-pv

[Configure] [Add VG] [Test All]
```

---

## Audio Player Compatibility

LVM monitoring doesn't play sounds directly:
- Monitoring feature using vgs, lvs, pvs commands
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### LVM Monitor

```go
type LVMMonitor struct {
    config        *LVMMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lvmState      map[string]*LVMInfo
    lastEventTime map[string]time.Time
}

type LVMInfo struct {
    VGName     string
    Status     string // "healthy", "warning", "critical"
    TotalBytes int64
    UsedBytes  int64
    FreeBytes  int64
    UsedPercent float64
    LVCount    int
    PVCount    int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| vgs | System Tool | Free | Volume group status |
| lvs | System Tool | Free | Logical volume status |
| pvs | System Tool | Free | Physical volume status |

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
| Linux | Supported | Uses lvm2 tools |
