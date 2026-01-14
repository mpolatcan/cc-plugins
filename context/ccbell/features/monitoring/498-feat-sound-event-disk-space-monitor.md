# Feature: Sound Event Disk Space Monitor

Play sounds for disk space warnings, critical thresholds, and partition full events.

## Summary

Monitor disk usage across partitions and volumes for warning and critical thresholds, playing sounds when space is running low.

## Motivation

- Storage awareness
- Prevention of disk full issues
- Capacity planning
- Performance optimization
- Data protection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Disk Space Events

| Event | Description | Example |
|-------|-------------|---------|
| Warning Level | > 80% used | 85% used |
| Critical Level | > 90% used | 95% used |
| Near Full | < 5GB free | 4GB free |
| Completely Full | 100% used | full |
| Inode Warning | > 80% inodes | 85% inodes |
| Inode Critical | > 90% inodes | 95% inodes |

### Configuration

```go
type DiskSpaceMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchPaths       []string          `json:"watch_paths"` // "/", "/home", "*"
    WarningPercent   int               `json:"warning_percent"` // 80 default
    CriticalPercent  int               `json:"critical_percent"` // 90 default
    WarningGB        int               `json:"warning_gb_free"` // 5 default
    SoundOnWarning   bool              `json:"sound_on_warning"`
    SoundOnCritical  bool              `json:"sound_on_critical"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:diskspace status            # Show disk usage
/ccbell:diskspace add /var          # Add path to watch
/ccbell:diskspace warning 80        # Set warning threshold
/ccbell:diskspace test              # Test disk sounds
```

### Output

```
$ ccbell:diskspace status

=== Sound Event Disk Space Monitor ===

Status: Enabled
Warning: 80%
Critical: 90%
Warning Free Space: 5 GB

Disk Usage:

[1] / (root)
    Total: 100 GB
    Used: 85 GB (85%) *** WARNING ***
    Free: 15 GB
    Inodes: 72% used
    Sound: bundled:diskspace-root *** WARNING ***

[2] /home
    Total: 500 GB
    Used: 450 GB (90%) *** CRITICAL ***
    Free: 50 GB
    Inodes: 45% used
    Sound: bundled:diskspace-home *** CRITICAL ***

[3] /var
    Total: 200 GB
    Used: 160 GB (80%)
    Free: 40 GB
    Inodes: 60% used
    Sound: bundled:diskspace-var

[4] /tmp
    Total: 50 GB
    Used: 48 GB (96%) *** CRITICAL ***
    Free: 2 GB *** NEAR FULL ***
    Inodes: 88% used
    Sound: bundled:diskspace-tmp *** CRITICAL ***

Recent Events:

[1] /home: Critical Level (5 min ago)
       90% used (450/500 GB)
       Sound: bundled:diskspace-critical
  [2] /tmp: Warning Level (10 min ago)
       85% used
       Sound: bundled:diskspace-warning
  [3] /: Warning Level (1 hour ago)
       85% used
       Sound: bundled:diskspace-warning

Disk Statistics:
  Total Disks: 4
  Healthy: 1
  Warning: 1
  Critical: 2
  Total Used: 743 GB
  Total Free: 107 GB

Sound Settings:
  Warning: bundled:diskspace-warning
  Critical: bundled:diskspace-critical
  Near Full: bundled:diskspace-near-full

[Configure] [Add Path] [Test All]
```

---

## Audio Player Compatibility

Disk space monitoring doesn't play sounds directly:
- Monitoring feature using df, lsblk
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Disk Space Monitor

```go
type DiskSpaceMonitor struct {
    config        *DiskSpaceMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    diskState     map[string]*DiskInfo
    lastEventTime map[string]time.Time
}

type DiskInfo struct {
    Path         string
    TotalBytes   int64
    UsedBytes    int64
    FreeBytes    int64
    UsedPercent  float64
    InodePercent float64
    Status       string // "healthy", "warning", "critical"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| df | System Tool | Free | Disk free (POSIX) |
| lsblk | System Tool | Free | List block devices |
| stat | System Tool | Free | File system stats |

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
| Linux | Supported | Uses df, lsblk, stat |
