# Feature: Sound Event Error Log Monitor

Play sounds for error log entries and system warnings.

## Summary

Monitor system and application error logs, playing sounds when new errors or warnings are detected.

## Motivation

- Immediate error awareness
- Warning detection
- Log monitoring automation
- Issue detection alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Error Log Events

| Event | Description | Example |
|-------|-------------|---------|
| Error | New error logged | "Connection refused" |
| Warning | Warning logged | "Deprecated API" |
| Critical | Critical error | "Kernel panic" |
| Fatal | Fatal error | "Segmentation fault" |

### Configuration

```go
type ErrorLogMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchLogs      []string          `json:"watch_logs"`
    IgnorePatterns []string          `json:"ignore_patterns"` // Lines to skip
    SeverityLevel  string            `json:"severity_level"` // "error", "warning", "critical"
    SoundOnError   bool              `json:"sound_on_error"`
    SoundOnWarning bool              `json:"sound_on_warning"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 10 default
}

type ErrorLogEvent struct {
    LogFile    string
    Severity   string // "error", "warning", "critical", "fatal"
    Message    string
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:error-log status          # Show error log status
/ccbell:error-log add /var/log/system.log
/ccbell:error-log severity error
/ccbell:error-log sound error <sound>
/ccbell:error-log sound warning <sound>
/ccbell:error-log test            # Test error sounds
```

### Output

```
$ ccbell:error-log status

=== Sound Event Error Log Monitor ===

Status: Enabled
Error Sounds: Yes
Warning Sounds: Yes
Severity Level: error

Watched Logs: 3

[1] /var/log/system.log
    Last Entry: 5 min ago
    Errors Today: 3
    Warnings Today: 12
    Sound: bundled:stop

[2] /var/log/nginx/error.log
    Last Entry: 1 hour ago
    Errors Today: 0
    Warnings Today: 2
    Sound: bundled:stop

[3] /var/log/apache2/error.log
    Last Entry: 2 hours ago
    Errors Today: 1
    Warnings Today: 5
    Sound: bundled:stop

Recent Events:
  [1] system.log: ERROR (5 min ago)
       "Connection refused"
  [2] nginx/error.log: WARNING (1 hour ago)
       "Deprecated directive"
  [3] apache2/error.log: CRITICAL (2 hours ago)
       "Child process exited"

Sound Settings:
  Error: bundled:stop
  Warning: bundled:stop
  Critical: bundled:stop

[Configure] [Add Log] [Test All]
```

---

## Audio Player Compatibility

Error log monitoring doesn't play sounds directly:
- Monitoring feature using log file parsing
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Error Log Monitor

```go
type ErrorLogMonitor struct {
    config        *ErrorLogMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    logPositions  map[string]int64
}

func (m *ErrorLogMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.logPositions = make(map[string]int64)
    go m.monitor()
}

func (m *ErrorLogMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLogs()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ErrorLogMonitor) checkLogs() {
    for _, logPath := range m.config.WatchLogs {
        m.checkLogFile(logPath)
    }
}

func (m *ErrorLogMonitor) checkLogFile(logPath string) {
    file, err := os.Open(logPath)
    if err != nil {
        return
    }
    defer file.Close()

    // Get file size
    stat, err := file.Stat()
    if err != nil {
        return
    }

    lastPos := m.logPositions[logPath]

    if stat.Size() <= lastPos {
        return
    }

    // Read new content
    file.Seek(lastPos, 0)
    scanner := bufio.NewScanner(file)

    for scanner.Scan() {
        line := scanner.Text()
        event := m.parseLogLine(logPath, line)

        if event != nil {
            m.onLogEvent(event)
        }
    }

    m.logPositions[logPath] = stat.Size()
}

func (m *ErrorLogMonitor) parseLogLine(logPath, line string) *ErrorLogEvent {
    // Check ignore patterns
    for _, pattern := range m.config.IgnorePatterns {
        if strings.Contains(line, pattern) {
            return nil
        }
    }

    event := &ErrorLogEvent{
        LogFile:   logPath,
        Timestamp: time.Now(),
    }

    // Determine severity
    lineLower := strings.ToLower(line)
    if strings.Contains(lineLower, "fatal") || strings.Contains(lineLower, "panic") {
        event.Severity = "fatal"
    } else if strings.Contains(lineLower, "critical") || strings.Contains(lineLower, "error") {
        event.Severity = "error"
    } else if strings.Contains(lineLower, "warning") || strings.Contains(lineLower, "warn") {
        event.Severity = "warning"
    } else {
        return nil
    }

    event.Message = line

    return event
}

func (m *ErrorLogMonitor) onLogEvent(event *ErrorLogEvent) {
    switch event.Severity {
    case "fatal":
        m.onFatalError(event)
    case "error":
        if m.config.SoundOnError {
            m.onError(event)
        }
    case "warning":
        if m.config.SoundOnWarning {
            m.onWarning(event)
        }
    }
}

func (m *ErrorLogMonitor) onError(event *ErrorLogEvent) {
    sound := m.config.Sounds["error"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *ErrorLogMonitor) onWarning(event *ErrorLogEvent) {
    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ErrorLogMonitor) onFatalError(event *ErrorLogEvent) {
    sound := m.config.Sounds["fatal"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| os | Go Stdlib | Free | File operations |
| bufio | Go Stdlib | Free | File scanning |

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
| macOS | Supported | Uses log files |
| Linux | Supported | Uses log files |
| Windows | Not Supported | ccbell only supports macOS/Linux |
