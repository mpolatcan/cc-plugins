# Feature: Sound Event Log Monitor

Play sounds for specific log patterns, error detection, and security events.

## Summary

Monitor system and application logs for specific patterns, error conditions, and security events, playing sounds when matching patterns are detected.

## Motivation

- Error detection
- Security alerting
- Debugging assistance
- Anomaly detection
- Real-time monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Log Events

| Event | Description | Example |
|-------|-------------|---------|
| Error Detected | Error pattern matched | ERROR |
| Warning Detected | Warning pattern | WARNING |
| Failed Login | Failed authentication | Failed password |
| Kernel Oops | Kernel error | Oops |
| Service Error | Service failure | service failed |
| Custom Pattern | User-defined regex | custom |

### Configuration

```go
type LogMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchLogs         []LogSource       `json:"watch_logs"`
    Patterns          []LogPattern      `json:"patterns"`
    SoundOnMatch      bool              `json:"sound_on_match"`
    DebounceSeconds   int               `json:"debounce_seconds"` // 10 default
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type LogSource struct {
    Path     string // "/var/log/syslog", "journalctl"
    Type     string // "file", "journald"
}

type LogPattern struct {
    Name      string
    Pattern   string // regex pattern
    Level     string // "error", "warning", "info"
    Exclude   string // exclude pattern
}
```

### Commands

```bash
/ccbell:log status                  # Show log monitor status
/ccbell:log add /var/log/app.log    # Add log file to watch
/ccbell:log pattern "ERROR.*failed" # Add pattern
/ccbell:log sound match <sound>
/ccbell:log test                    # Test log sounds
```

### Output

```
$ ccbell:log status

=== Sound Event Log Monitor ===

Status: Enabled
Debounce: 10 seconds

Watch Logs:

[1] /var/log/syslog
    Type: file
    Last Position: line 54321
    Sound: bundled:log-syslog

[2] /var/log/nginx/error.log
    Type: file
    Last Position: line 1234
    Sound: bundled:log-nginx

[3] journalctl -p err
    Type: journald
    Last Position: cursor_xxx
    Sound: bundled:log-journal

Patterns:

[1] Errors
    Pattern: ERROR|Error|error
    Level: error
    Matches: 15
    Sound: bundled:log-error

[2] Failed Logins
    Pattern: Failed password|Authentication failure
    Level: security
    Matches: 3
    Sound: bundled:log-security

[3] Nginx Errors
    Pattern: \[error\].*client
    Level: error
    Matches: 8
    Sound: bundled:log-nginx-error

Recent Events:

[1] /var/log/nginx/error.log (5 min ago)
       [error] 1234#1234: *123 connect() failed
       Sound: bundled:log-error
  [2] journalctl (10 min ago)
       Failed password for root from 192.168.1.100
       Sound: bundled:log-security
  [3] /var/log/syslog (30 min ago)
       [ERROR] Database connection failed
       Sound: bundled:log-error

Log Statistics:
  Total Patterns: 3
  Total Matches: 26
  Errors: 15
  Security: 3
  Warnings: 8

Sound Settings:
  Error: bundled:log-error
  Security: bundled:log-security
  Warning: bundled:log-warning

[Configure] [Add Log] [Add Pattern] [Test All]
```

---

## Audio Player Compatibility

Log monitoring doesn't play sounds directly:
- Monitoring feature using tail, journalctl, grep
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Log Monitor

```go
type LogMonitor struct {
    config        *LogMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    logState      map[string]*LogState
    matchCounts   map[string]int
    lastEventTime time.Time
}

type LogState struct {
    Path         string
    LastPosition int64 // line number or file offset
    LastModified time.Time
}

type LogMatch struct {
    Pattern  string
    Line     string
    LineNum  int
    Timestamp time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| tail | System Tool | Free | Follow log files |
| journalctl | System Tool | Free | systemd journal |
| grep | System Tool | Free | Pattern matching |

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
| macOS | Supported | Uses tail, grep |
| Linux | Supported | Uses tail, journalctl, grep |
