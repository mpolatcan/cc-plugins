# Feature: Sound Event RAID Health Monitor

Play sounds for RAID array status changes, disk failures, and rebuild events.

## Summary

Monitor RAID arrays for status changes, disk failures, degraded state, and rebuild completion, playing sounds for RAID health events.

## Motivation

- Storage reliability
- Failure alerts
- Rebuild tracking
- Array health
- Data protection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Medium |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### RAID Health Events

| Event | Description | Example |
|-------|-------------|---------|
| Array Degraded | Disk failed | degraded |
| Array Healthy | Rebuild complete | healthy |
| Disk Failed | Drive failure | sda failed |
| Disk Added | Drive replaced | sda added |
| Rebuild Started | Resync begun | rebuilding |
| Rebuild Complete | Resync finished | rebuilt |

### Configuration

```go
type RAIDHealthMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchArrays      []string          `json:"watch_arrays"` // "/dev/md0", "*"
    SoundOnDegraded  bool              `json:"sound_on_degraded"`
    SoundOnHealthy   bool              `json:"sound_on_healthy"`
    SoundOnFailed    bool              `json:"sound_on_failed"`
    SoundOnRebuild   bool              `json:"sound_on_rebuild"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:raid status                # Show RAID status
/ccbell:raid add /dev/md0          # Add array to watch
/ccbell:raid sound degraded <sound>
/ccbell:raid test                  # Test RAID sounds
```

### Output

```
$ ccbell:raid status

=== Sound Event RAID Health Monitor ===

Status: Enabled
Watch Arrays: all

RAID Array Status:

[1] /dev/md0 (RAID 5)
    Status: DEGRADED *** WARNING ***
    Disks: 4 total, 3 active
    Capacity: 12 TB (3 x 4 TB)
    Used: 8 TB
    Rebuild: 45% complete
    ETA: 2 hours
    Sound: bundled:raid-md0 *** WARNING ***

[2] /dev/md1 (RAID 1)
    Status: HEALTHY *** ACTIVE ***
    Disks: 2 total, 2 active
    Capacity: 1 TB (2 x 1 TB)
    Used: 500 GB
    Rebuild: N/A
    Sound: bundled:raid-md1 *** ACTIVE ***

[3] /dev/md2 (RAID 10)
    Status: HEALTHY
    Disks: 4 total, 4 active
    Capacity: 4 TB (4 x 1 TB)
    Used: 2 TB
    Rebuild: N/A
    Sound: bundled:raid-md2

Recent Events:

[1] /dev/md0: Disk Failed (5 min ago)
       sdc removed from array
       Sound: bundled:raid-failed
  [2] /dev/md0: Rebuild Started (10 min ago)
       Resync started at 45% complete
       Sound: bundled:raid-rebuild
  [3] /dev/md1: Rebuild Complete (1 hour ago)
       Array fully synchronized
       Sound: bundled:raid-healthy

RAID Statistics:
  Total Arrays: 3
  Healthy: 2
  Degraded: 1
  Failed Disks: 1
  Rebuilding: 1

Sound Settings:
  Degraded: bundled:raid-degraded
  Healthy: bundled:raid-healthy
  Failed: bundled:raid-failed
  Rebuild: bundled:raid-rebuild

[Configure] [Add Array] [Test All]
```

---

## Audio Player Compatibility

RAID monitoring doesn't play sounds directly:
- Monitoring feature using mdadm, smartctl, megacli
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### RAID Health Monitor

```go
type RAIDHealthMonitor struct {
    config        *RAIDHealthMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    arrayState    map[string]*ArrayInfo
    lastEventTime map[string]time.Time
}

type ArrayInfo struct {
    Device     string
    Level      string // "0", "1", "5", "6", "10"
    Status     string // "healthy", "degraded", "failed"
    DisksTotal int
    DisksActive int
    Capacity   int64 // bytes
    Used       int64 // bytes
    RebuildPct float64
    ETA        int // seconds remaining
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| mdadm | System Tool | Free | Linux software RAID |
| smartctl | System Tool | Free | SMART disk monitoring |
| megacli | System Tool | Free | LSI MegaRAID |
| storcli | System Tool | Free | Broadcom RAID |

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
| macOS | Limited | Limited RAID support (mdm/Apple RAID) |
| Linux | Supported | Uses mdadm, smartctl, megacli |
