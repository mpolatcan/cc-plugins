# Feature: Sound Event Log File Monitor

Play sounds for log file changes, error patterns, and warning detection.

## Summary

Monitor log files for new entries, error patterns, and critical warnings, playing sounds for log events.

## Motivation

- Log awareness
- Error detection
- Warning alerts
- Debug feedback
- System health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Log File Events

| Event | Description | Example |
|-------|-------------|---------|
| New Entry | New log line | new line |
| Error Found | Error pattern | "ERROR" |
| Warning Found | Warning pattern | "WARNING" |
| Critical | Critical pattern | "CRITICAL" |
| High Volume | Too many lines | > 100/min |
| File Rotated | Log rotated | rotated |

### Configuration

```go
type LogFileMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchLogs         []string          `json:"watch_logs"` // "/var/log/syslog", "~/logs/*.log"
    ErrorPatterns     []string          `json:"error_patterns"` // "ERROR", "Failed", "Exception"
    WarningPatterns   []string          `json:"warning_patterns"` // "WARNING", "Deprecat"
    SoundOnError      bool              `json:"sound_on_error"`
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnNew        bool              `json:"sound_on_new"`
    VolumeThreshold   int               `json:"volume_threshold_lines"` // 100 default
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:log status                   # Show log status
/ccbell:log add /var/log/syslog      # Add log file to watch
/ccbell:log add "~/logs/*.log"
/ccbell:log pattern ERROR            # Add error pattern
/ccbell:log sound error <sound>
/ccbell:log test                     # Test log sounds
```

### Output

```
$ ccbell:log status

=== Sound Event Log File Monitor ===

Status: Enabled
Volume Threshold: 100 lines/min
Error Patterns: 3
Warning Patterns: 2

Watched Logs:

[1] /var/log/syslog
    Status: WATCHING
    Lines Today: 1520
    Lines/min: 12
    Last Entry: Jan 14 10:30:15
    Sound: bundled:log-syslog

[2] /var/log/nginx/access.log
    Status: WATCHING
    Lines Today: 8500
    Lines/min: 85
    Last Entry: Jan 14 10:30:12
    Sound: bundled:log-nginx

[3] ~/logs/app.log
    Status: WATCHING
    Lines Today: 450
    Lines/min: 5
    Last Entry: Jan 14 10:29:58
    Sound: bundled:log-app

Recent Log Events:

[1] /var/log/syslog: ERROR (2 min ago)
       [systemd] Failed to start service
       Sound: bundled:log-error
  [2] /var/log/nginx/access.log: WARNING (15 min ago)
       [warn] Upstream timeout
       Sound: bundled:log-warning
  [3] ~/logs/app.log: New Entry (30 min ago)
       User login successful
       Sound: bundled:log-new

Pattern Matches Today:

  Errors: 5
  Warnings: 12
  Critical: 0

Log Statistics:
  Total Logs: 3
  Total Lines Today: 10470
  Error Rate: 0.05%

Sound Settings:
  Error: bundled:log-error
  Warning: bundled:log-warning
  New: bundled:log-new
  Critical: bundled:log-critical

[Configure] [Add Log] [Test All]
```

---

## Audio Player Compatibility

Log monitoring doesn't play sounds directly:
- Monitoring feature using tail/less
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Log File Monitor

```go
type LogFileMonitor struct {
    config          *LogFileMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    logState        map[string]*LogFileInfo
    lastEventTime   map[string]time.Time
}

type LogFileInfo struct {
    Path       string
    Size       int64
    LineCount  int
    LastLine   string
    LastCheck  time.Time
    ErrorCount int
    WarningCount int
}

func (m *LogFileMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.logState = make(map[string]*LogFileInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LogFileMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotLogState()

    for {
        select {
        case <-ticker.C:
            m.checkLogState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LogFileMonitor) snapshotLogState() {
    m.checkLogState()
}

func (m *LogFileMonitor) checkLogState() {
    for _, logPath := range m.config.WatchLogs {
        expandedPath := m.expandPath(logPath)

        // Handle glob patterns
        if strings.Contains(logPath, "*") {
            files := m.expandGlob(expandedPath)
            for _, file := range files {
                m.checkLogFile(file)
            }
        } else {
            m.checkLogFile(expandedPath)
        }
    }
}

func (m *LogFileMonitor) checkLogFile(filePath string) {
    info := m.readLogFile(filePath)
    if info == nil {
        return
    }

    m.processLogStatus(filePath, info)
}

func (m *LogFileMonitor) readLogFile(filePath string) *LogFileInfo {
    info := &LogFileInfo{
        Path:      filePath,
        LastCheck: time.Now(),
    }

    // Get file info
    fileInfo, err := os.Stat(filePath)
    if err != nil {
        return nil
    }
    info.Size = fileInfo.Size()

    // Read last few lines
    file, err := os.Open(filePath)
    if err != nil {
        return nil
    }
    defer file.Close()

    // Seek to end and read backwards for efficiency
    const maxLinesToRead = 100
    var lines []string
    scanner := bufio.NewScanner(file)

    for scanner.Scan() {
        lines = append(lines, scanner.Text())
        if len(lines) > maxLinesToRead {
            lines = lines[len(lines)-maxLinesToRead:]
        }
    }

    info.LineCount = len(lines)

    if len(lines) > 0 {
        info.LastLine = lines[len(lines)-1]
    }

    return info
}

func (m *LogFileMonitor) processLogStatus(filePath string, info *LogFileInfo) {
    lastInfo := m.logState[filePath]

    if lastInfo == nil {
        m.logState[filePath] = info
        return
    }

    // Check for new lines
    if info.LineCount > lastInfo.LineCount {
        newLines := info.LineCount - lastInfo.LineCount

        // Check for high volume
        if newLines >= m.config.VolumeThreshold {
            m.onHighVolume(filePath, newLines)
        }

        // Check for error/warning patterns in new lines
        m.checkPatterns(filePath, info, lastInfo)
    }

    // Check for file rotation
    if info.Size < lastInfo.Size && info.LineCount < lastInfo.LineCount {
        m.onLogRotated(filePath)
    }

    m.logState[filePath] = info
}

func (m *LogFileMonitor) checkPatterns(filePath string, info, lastInfo *LogFileInfo) {
    // Read only the new lines
    file, err := os.Open(filePath)
    if err != nil {
        return
    }
    defer file.Close()

    // Skip to the new lines
    skipCount := lastInfo.LineCount
    scanner := bufio.NewScanner(file)

    for scanner.Scan() && skipCount > 0 {
        skipCount--
    }

    // Check new lines for patterns
    for scanner.Scan() {
        line := scanner.Text()

        // Check error patterns
        for _, pattern := range m.config.ErrorPatterns {
            if strings.Contains(strings.ToUpper(line), strings.ToUpper(pattern)) {
                if m.config.SoundOnError {
                    m.onErrorFound(filePath, line, pattern)
                }
                info.ErrorCount++
                break
            }
        }

        // Check warning patterns
        for _, pattern := range m.config.WarningPatterns {
            if strings.Contains(strings.ToUpper(line), strings.ToUpper(pattern)) {
                if m.config.SoundOnWarning {
                    m.onWarningFound(filePath, line, pattern)
                }
                info.WarningCount++
                break
            }
        }
    }
}

func (m *LogFileMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
}

func (m *LogFileMonitor) expandGlob(pattern string) []string {
    var files []string

    matches, err := filepath.Glob(pattern)
    if err == nil {
        for _, match := range matches {
            if info, err := os.Stat(match); err == nil && !info.IsDir() {
                files = append(files, match)
            }
        }
    }

    return files
}

func (m *LogFileMonitor) onErrorFound(filePath, line, pattern string) {
    key := fmt.Sprintf("error:%s", filePath)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *LogFileMonitor) onWarningFound(filePath, line, pattern string) {
    key := fmt.Sprintf("warning:%s", filePath)
    if m.shouldAlert(key, 2*time.Minute) {
        sound := m.config.Sounds["warning"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LogFileMonitor) onHighVolume(filePath string, lines int) {
    key := fmt.Sprintf("volume:%s", filePath)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["volume"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *LogFileMonitor) onLogRotated(filePath string) {
    key := fmt.Sprintf("rotate:%s", filePath)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["rotate"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *LogFileMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| tail | System Tool | Free | File monitoring |
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
| Linux | Supported | Uses tail, grep |
