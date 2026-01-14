# Feature: Sound Event Directory Watch Monitor

Play sounds for directory changes, quota limits, and access events.

## Summary

Monitor directories for access, quota status, and structural changes, playing sounds for directory events.

## Motivation

- Directory awareness
- Access monitoring
- Quota alerts
- Structure changes
- Access control

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Directory Watch Events

| Event | Description | Example |
|-------|-------------|---------|
| Quota Exceeded | Over quota | > 100% |
| Quota Warning | Near quota | > 80% |
| Directory Accessed | Accessed | accessed |
| Subdir Created | New subdir | created |
| Subdir Deleted | Subdir removed | removed |
| Permission Denied | Access blocked | denied |

### Configuration

```go
type DirectoryWatchMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchDirs       []string          `json:"watch_dirs"` // paths to monitor
    QuotaPercent    int               `json:"quota_percent"` // 80 default
    SoundOnQuota    bool              `json:"sound_on_quota"`
    SoundOnAccess   bool              `json:"sound_on_access"`
    SoundOnDeny     bool              `json:"sound_on_deny"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:dirwatch status             # Show directory status
/ccbell:dirwatch add /home          # Add directory to watch
/ccbell:dirwatch quota 80           # Set quota threshold
/ccbell:dirwatch sound quota <sound>
/ccbell:dirwatch test               # Test dirwatch sounds
```

### Output

```
$ ccbell:dirwatch status

=== Sound Event Directory Watch Monitor ===

Status: Enabled
Watch Directories: /home, /var/www
Quota Threshold: 80%

Directory Status:

[1] /home (ZFS)
    Status: HEALTHY
    Used: 450 GB / 1 TB (45%)
    Files: 125,432
    Subdirs: 1,234
    Sound: bundled:dirwatch-home

[2] /var/www (ext4)
    Status: WARNING *** WARNING ***
    Used: 85 GB / 100 GB (85%)
    Files: 15,678
    Subdirs: 456
    Quota: 85% *** NEAR QUOTA ***
    Sound: bundled:dirwatch-www *** WARNING ***

Recent Events:

[1] /var/www: Quota Warning (5 min ago)
       85% > 80% threshold
       Sound: bundled:dirwatch-quota
  [2] /home/user: Directory Accessed (1 hour ago)
       /home/user/docs accessed
       Sound: bundled:dirwatch-access
  [3] /var/www: Permission Denied (2 hours ago)
       Access denied to /var/www/private
       Sound: bundled:dirwatch-deny

Directory Statistics:
  Total Directories: 2
  Healthy: 1
  Near Quota: 1
  Access Events Today: 15

Sound Settings:
  Quota: bundled:dirwatch-quota
  Access: bundled:dirwatch-access
  Deny: bundled:dirwatch-deny
  Create: bundled:dirwatch-create

[Configure] [Add Directory] [Test All]
```

---

## Audio Player Compatibility

Directory monitoring doesn't play sounds directly:
- Monitoring feature using du, quota, inotifywait
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Directory Watch Monitor

```go
type DirectoryWatchMonitor struct {
    config        *DirectoryWatchMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    dirState      map[string]*DirInfo
    lastEventTime map[string]time.Time
}

type DirInfo struct {
    Path       string
    Status     string // "healthy", "warning", "critical"
    UsedBytes  int64
    TotalBytes int64
    UsedPercent float64
    FileCount  int64
    SubdirCount int64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| du | System Tool | Free | Disk usage |
| quota | System Tool | Free | Quota management |
| inotifywait | System Tool | Free | Directory events |

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
| macOS | Supported | Uses du, fswatch |
| Linux | Supported | Uses du, quota, inotifywait |
