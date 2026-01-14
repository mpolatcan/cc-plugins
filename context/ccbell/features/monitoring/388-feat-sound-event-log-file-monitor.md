# Feature: Sound Event Log File Monitor

Play sounds for log file patterns, errors, and critical messages.

## Summary

Monitor log files for error patterns, warning keywords, and critical events, playing sounds for log events.

## Motivation

- Error detection
- System monitoring
- Application health
- Pattern matching alerts
- Log analysis automation

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
| Error Detected | Error keyword found | ERROR |
| Warning Found | Warning keyword | WARNING |
| Critical Alert | Critical message | CRITICAL |
| Pattern Match | Regex match | timeout |
| File Rotated | Log rotation | log rotate |
| New Log File | New file detected | new file |

### Configuration

```go
type LogFileMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchFiles        []string          `json:"watch_files"` // "/var/log/syslog", "/var/log/nginx/*.log"
    Keywords          []string          `json:"keywords"` // "ERROR", "WARNING", "FATAL"
    Patterns          []string          `json:"patterns"` // regex patterns
    ExcludePatterns   []string          `json:"exclude_patterns"`
    SoundOnError      bool              `json:"sound_on_error"`
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:log status                     # Show log status
/ccbell:log add /var/log/syslog        # Add log file
/ccbell:log add-pattern "ERROR|WARN"   # Add pattern
/ccbell:log remove /var/log/syslog
/ccbell:log sound error <sound>
/ccbell:log test                       # Test log sounds
```

### Output

```
$ ccbell:log status

=== Sound Event Log File Monitor ===

Status: Enabled
Error Sounds: Yes
Warning Sounds: Yes
Critical Sounds: Yes

Watched Files: 4
Watched Patterns: 3

Watched Log Files:

[1] /var/log/syslog
    Size: 125 MB
    Lines Today: 15,000
    Errors: 45
    Warnings: 120
    Sound: bundled:log-syslog

[2] /var/log/nginx/error.log
    Size: 2.5 MB
    Lines Today: 500
    Errors: 12
    Warnings: 5
    Sound: bundled:log-nginx

[3] /var/log/postgresql/postgresql.log
    Size: 8 MB
    Lines Today: 1,200
    Errors: 2
    Warnings: 8
    Sound: bundled:log-postgres

[4] /var/log/messages
    Size: 45 MB
    Lines Today: 8,000
    Errors: 25
    Warnings: 60
    Sound: bundled:log-messages

Recent Events:
  [1] /var/log/nginx/error.log: Error (5 min ago)
       "connection refused"
  [2] /var/log/syslog: Warning (10 min ago)
       "memory low"
  [3] /var/log/postgresql.log: Critical (1 hour ago)
       "database connection failed"

Log Statistics:
  Total Errors Today: 84
  Total Warnings: 193
  Total Critical: 3

Sound Settings:
  Error: bundled:log-error
  Warning: bundled:log-warning
  Critical: bundled:log-critical

[Configure] [Add File] [Test All]
```

---

## Audio Player Compatibility

Log monitoring doesn't play sounds directly:
- Monitoring feature using tail/grep
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
    fileState       map[string]*LogFileInfo
    lastEventTime   map[string]time.Time
}

type LogFileInfo struct {
    Path       string
    Size       int64
    LineCount  int64
    LastLine   string
    LastCheck  time.Time
}

func (m *LogFileMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.fileState = make(map[string]*LogFileInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *LogFileMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFileState()

    for {
        select {
        case <-ticker.C:
            m.checkLogFiles()
        case <-m.stopCh:
            return
        }
    }
}

func (m *LogFileMonitor) snapshotFileState() {
    for _, path := range m.config.WatchFiles {
        m.checkLogFile(path)
    }
}

func (m *LogFileMonitor) checkLogFiles() {
    for _, path := range m.config.WatchFiles {
        m.checkLogFile(path)
    }
}

func (m *LogFileMonitor) checkLogFile(path string) {
    expandedPath := m.expandPath(path)

    // Check if file exists
    fileInfo, err := os.Stat(expandedPath)
    if err != nil {
        return
    }

    lastInfo := m.fileState[expandedPath]
    currentSize := fileInfo.Size()

    // Get line count
    cmd := exec.Command("wc", "-l", expandedPath)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    parts := strings.Fields(string(output))
    lineCount, _ := strconv.ParseInt(parts[0], 10, 64)

    // Get new lines
    var newLines []string
    if lastInfo != nil {
        newLines = m.getNewLines(expandedPath, lastInfo.Size, currentSize)
    } else {
        // First time - only check last few lines
        newLines = m.getLastLines(expandedPath, 100)
    }

    // Process new lines
    for _, line := range newLines {
        m.processLogLine(expandedPath, line)
    }

    // Update state
    m.fileState[expandedPath] = &LogFileInfo{
        Path:      expandedPath,
        Size:      currentSize,
        LineCount: lineCount,
        LastCheck: time.Now(),
    }
}

func (m *LogFileMonitor) getNewLines(path string, lastSize, currentSize int64) []string {
    if currentSize <= lastSize {
        return nil
    }

    cmd := exec.Command("sed", fmt.Sprintf("-n '%d,$p'", lastLineNumber(path, lastSize)), path)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    // Remove empty last line
    if len(lines) > 0 && lines[len(lines)-1] == "" {
        lines = lines[:len(lines)-1]
    }

    return lines
}

func (m *LogFileMonitor) getLastLines(path string, n int) []string {
    cmd := exec.Command("tail", fmt.Sprintf("-n %d", n), path)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    if len(lines) > 0 && lines[len(lines)-1] == "" {
        lines = lines[:len(lines)-1]
    }

    return lines
}

func (m *LogFileMonitor) processLogLine(path, line string) {
    line = strings.TrimSpace(line)
    if line == "" {
        return
    }

    severity := m.detectSeverity(line)

    switch severity {
    case "error":
        if m.config.SoundOnError {
            m.onLogEvent(path, line, "error")
        }
    case "warning":
        if m.config.SoundOnWarning {
            m.onLogEvent(path, line, "warning")
        }
    case "critical":
        if m.config.SoundOnCritical {
            m.onLogEvent(path, line, "critical")
        }
    }

    // Check custom patterns
    for _, pattern := range m.config.Patterns {
        if m.matchesPattern(line, pattern) {
            m.onPatternMatch(path, line, pattern)
        }
    }
}

func (m *LogFileMonitor) detectSeverity(line string) string {
    upper := strings.ToUpper(line)

    if strings.Contains(upper, "CRITICAL") || strings.Contains(upper, "FATAL") || strings.Contains(upper, "PANIC") {
        return "critical"
    }
    if strings.Contains(upper, "ERROR") || strings.Contains(upper, "ERR") || strings.Contains(upper, "FAILED") {
        return "error"
    }
    if strings.Contains(upper, "WARNING") || strings.Contains(upper, "WARN") || strings.Contains(upper, "ATTENTION") {
        return "warning"
    }

    return "none"
}

func (m *LogFileMonitor) matchesPattern(line, pattern string) bool {
    re, err := regexp.Compile(pattern)
    if err != nil {
        return false
    }
    return re.MatchString(line)
}

func (m *LogFileMonitor) onLogEvent(path, line, severity string) {
    key := fmt.Sprintf("%s:%s", path, severity)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds[severity]
        if sound != "" {
            volume := 0.5
            if severity == "critical" {
                volume = 0.7
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *LogFileMonitor) onPatternMatch(path, line, pattern string) {
    key := fmt.Sprintf("pattern:%s:%s", path, pattern)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["pattern"]
        if sound != "" {
            m.player.Play(sound, 0.5)
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

func (m *LogFileMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}

func lastLineNumber(path string, size int64) int {
    // Approximate - in production, use more accurate method
    return 1
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| tail | System Tool | Free | Log tailing |
| grep | System Tool | Free | Pattern matching |
| sed | System Tool | Free | Text processing |
| wc | System Tool | Free | Line counting |

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
| macOS | Supported | Uses tail, grep, sed |
| Linux | Supported | Uses tail, grep, sed |
