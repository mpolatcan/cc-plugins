# Feature: Sound Event Hardware RAID Monitor

Play sounds for hardware RAID array status changes, disk failures, and rebuilding events.

## Summary

Monitor hardware RAID controllers (LSI, Adaptec, Dell PERC) for array status, disk health, and rebuild progress, playing sounds for RAID events.

## Motivation

- RAID awareness
- Disk failure alerts
- Array degradation
- Rebuild completion
- Storage redundancy

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Hardware RAID Events

| Event | Description | Example |
|-------|-------------|---------|
| Array Degraded | Disk failed | degraded |
| Array Critical | Multiple failed | critical |
| Disk Failed | Physical disk failed | disk 2 failed |
| Rebuild Started | Rebuild begun | 0% complete |
| Rebuild Progress | Progress update | 50% complete |
| Rebuild Complete | Rebuild finished | 100% complete |

### Configuration

```go
type HardwareRAIDMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchControllers  []string          `json:"watch_controllers"` // "lsi", "adaptec", "perc", "*"
    RebuildThreshold  int               `json:"rebuild_threshold"` // 50% for progress alerts
    SoundOnDegraded   bool              `json:"sound_on_degraded"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnRebuild    bool              `json:"sound_on_rebuild"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:raid status                 # Show RAID status
/ccbell:raid add lsi                # Add controller to watch
/ccbell:raid sound degraded <sound>
/ccbell:raid test                   # Test RAID sounds
```

### Output

```
$ ccbell:raid status

=== Sound Event Hardware RAID Monitor ===

Status: Enabled
Watch Controllers: all
Rebuild Threshold: 50%

RAID Array Status:

[1] LSI MegaRAID (slot 0)
    Status: DEGRADED *** WARNING ***
    Array: RAID 5 (4 disks)
    Disks: 3/4 (1 failed)
    Capacity: 2 TB
    Rebuild: Not running
    Sound: bundled:raid-lsi *** WARNING ***

[2] Adaptec RAID 71605
    Status: HEALTHY
    Array: RAID 10 (8 disks)
    Disks: 8/8
    Capacity: 8 TB
    Rebuild: 67% complete (ETA: 2h)
    Sound: bundled:raid-adaptec

Recent Events:

[1] LSI MegaRAID: Disk Failed (5 min ago)
       Disk 2 (ST4000NM0033) failed
       Sound: bundled:raid-failed
  [2] Adaptec RAID 71605: Rebuild Progress (10 min ago)
       67% complete, ETA: 2h
       Sound: bundled:raid-rebuild
  [3] LSI MegaRAID: Array Degraded (30 min ago)
       Array degraded, 1 disk failed
       Sound: bundled:raid-degraded

RAID Statistics:
  Total Arrays: 2
  Healthy: 1
  Degraded: 1
  Disks Total: 12
  Disks Failed: 1

Sound Settings:
  Degraded: bundled:raid-degraded
  Failed: bundled:raid-failed
  Rebuild: bundled:raid-rebuild
  Complete: bundled:raid-complete

[Configure] [Add Controller] [Test All]
```

---

## Audio Player Compatibility

RAID monitoring doesn't play sounds directly:
- Monitoring feature using storcli, arcconf, perccli
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Hardware RAID Monitor

```go
type HardwareRAIDMonitor struct {
    config        *HardwareRAIDMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    raidState     map[string]*RAIDInfo
    lastEventTime map[string]time.Time
}

type RAIDInfo struct {
    Controller  string
    ArrayName   string
    Status      string // "healthy", "degraded", "critical", "rebuilding"
    RAIDLevel   string
    TotalDisks  int
    FailedDisks int
    RebuildProgress int
    Capacity    string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| storcli | System Tool | Free | LSI RAID controller |
| arcconf | System Tool | Free | Adaptec RAID controller |
| perccli | System Tool | Free | Dell PERC controller |
| mdadm | System Tool | Free | Linux software RAID |

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
| macOS | Supported | Uses system_profiler |
| Linux | Supported | Uses storcli, arcconf, mdadm |
