# Feature: Sound Event Log Rotation Monitor

Play sounds for log rotation events, compression, and archive management.

## Summary

Monitor log rotation (logrotate, newsyslog) for rotation events, compression status, and archive creation, playing sounds for rotation events.

## Motivation

- Log awareness
- Rotation detection
- Archive management
- Disk space saving
- Compliance tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Log Rotation Events

| Event | Description | Example |
|-------|-------------|---------|
| Log Rotated | Log rotated | rotated |
| Log Compressed | Gzip compressed | .gz created |
| Log Deleted | Old log deleted | deleted |
| Rotation Error | Rotation failed | error |
| Archive Created | Archive made | archived |
| Size Threshold | Size limit hit | > 100MB |

### Configuration

```go
type LogRotationMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchLogs        []string          `json:"watch_logs"` // "/var/log/*.log", "*"
    SoundOnRotate    bool              `json:"sound_on_rotate"`
    SoundOnCompress  bool              `json:"sound_on_compress"`
    SoundOnDelete    bool              `json:"sound_on_delete"`
    SoundOnError     bool              `json:"sound_on_error"`
    SizeThresholdMB  int               `json:"size_threshold_mb"` // 100 default
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 300 default
}
```

### Commands

```bash
/ccbell:logrot status               # Show log rotation status
/ccbell:logrot add /var/log         # Add log path to watch
/ccbell:logrot sound rotate <sound>
/ccbell:logrot test                 # Test log rotation sounds
```

### Output

```
$ ccbell:logrot status

=== Sound Event Log Rotation Monitor ===

Status: Enabled
Watch Logs: /var/log/*.log
Size Threshold: 100 MB

Log Rotation Status:

[1] /var/log/syslog
    Status: ACTIVE
    Size: 45 MB
    Rotated: Today 02:00
    Compressed: Yes (.1.gz)
    Last Rotation: 8 hours ago
    Sound: bundled:logrot-syslog

[2] /var/log/nginx/access.log
    Status: ACTIVE
    Size: 120 MB *** LARGE ***
    Rotated: Daily
    Compressed: Yes
    Last Rotation: 8 hours ago
    Sound: bundled:logrot-nginx *** WARNING ***

[3] /var/log/mysql/slow.log
    Status: ACTIVE
    Size: 15 MB
    Rotated: Weekly
    Compressed: Yes
    Last Rotation: 2 days ago
    Sound: bundled:logrot-mysql

Recent Events:

[1] /var/log/nginx/access.log: Size Threshold (5 min ago)
       120 MB > 100 MB
       Sound: bundled:logrot-size
  [2] /var/log/syslog: Rotated (8 hours ago)
       Daily rotation completed
       Sound: bundled:logrot-rotate
  [3] /var/log/syslog: Compressed (8 hours ago)
       syslog.1.gz created
       Sound: bundled:logrot-compress

Log Rotation Statistics:
  Total Logs: 3
  Active: 3
  Rotated Today: 1
  Compressed Today: 1

Sound Settings:
  Rotate: bundled:logrot-rotate
  Compress: bundled:logrot-compress
  Delete: bundled:logrot-delete
  Size: bundled:logrot-size

[Configure] [Add Log] [Test All]
```

---

## Audio Player Compatibility

Log rotation monitoring doesn't play sounds directly:
- Monitoring feature using logrotate, ls, stat
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Log Rotation Monitor

```go
type LogRotationMonitor struct {
    config        *LogRotationMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    logState      map[string]*LogInfo
    lastEventTime map[string]time.Time
}

type LogInfo struct {
    Path          string
    Status        string // "active", "rotated", "compressed"
    SizeBytes     int64
    LastModified  time.Time
    LastRotated   time.Time
    Compressed    bool
    ArchivePath   string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| logrotate | System Tool | Free | Log rotation |
| ls | System Tool | Free | File listing |
| stat | System Tool | Free | File status |

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
| macOS | Supported | Uses newsyslog, ls |
| Linux | Supported | Uses logrotate, ls |
