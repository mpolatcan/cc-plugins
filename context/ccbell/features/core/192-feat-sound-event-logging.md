# Feature: Sound Event Logging

Enhanced event logging.

## Summary

Detailed logging of sound event playback and system state.

## Motivation

- Debugging
- Audit trail
- Performance analysis

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Log Levels

| Level | Description | Example |
|-------|-------------|---------|
| Debug | Detailed debug info | Sound path resolution |
| Info | Standard events | Event triggered |
| Warning | Non-fatal issues | Player not found |
| Error | Errors only | Playback failed |

### Configuration

```go
type LoggingConfig struct {
    Enabled       bool              `json:"enabled"`
    Level         string            `json:"level"` // "debug", "info", "warning", "error"
    Path          string            `json:"path"` // Log file path
    MaxSize       int               `json:"max_size_mb"` // 10 default
    MaxFiles      int               `json:"max_files"` // 5 default
    Format        string            `json:"format"` // "json", "text"
    IncludeStack  bool              `json:"include_stack"`
}

type LogEntry struct {
    Timestamp   time.Time `json:"timestamp"`
    Level       string    `json:"level"`
    Event       string    `json:"event,omitempty"`
    Message     string    `json:"message"`
    Details     map[string]interface{} `json:"details,omitempty"`
    Error       string    `json:"error,omitempty"`
    Stack       string    `json:"stack,omitempty"`
}
```

### Commands

```bash
/ccbell:log show                    # Show recent logs
/ccbell:log show --level error      # Show errors only
/ccbell:log show --event stop       # Show specific event
/ccbell:log tail                    # Tail logs in real-time
/ccbell:log level debug             # Set log level
/ccbell:log path /var/log/ccbell.log
/ccbell:log clear                   # Clear log file
/ccbell:log export                  # Export logs
```

### Output

```
$ ccbell:log show

=== Sound Event Logging ===

Level: info
Path: ~/.claude/ccbell.log
Format: text

[2024-01-15 10:30:45] INFO: Event stop triggered
  Sound: bundled:stop
  Volume: 0.5
  Platform: macOS

[2024-01-15 10:30:46] DEBUG: Sound path resolved: /Users/.../sounds/stop.aiff

[2024-01-15 10:30:46] INFO: Sound playback initiated
  Player: afplay
  Duration: ~2s

[2024-01-15 10:32:15] WARNING: In quiet hours, suppressing notification
  Event: permission_prompt

[2024-01-15 10:35:00] ERROR: Sound playback failed
  Error: file not found
  Path: /invalid/path.aiff

[Tail] [Export] [Clear] [Configure]
```

---

## Audio Player Compatibility

Logging doesn't play sounds:
- Logging feature
- No player changes required

---

## Implementation

### Logger

```go
type EventLogger struct {
    config   *LoggingConfig
    file     *os.File
    mutex    sync.Mutex
}

func (m *EventLogger) Log(level, event, message string, details map[string]interface{}) {
    entry := LogEntry{
        Timestamp: time.Now(),
        Level:     level,
        Event:     event,
        Message:   message,
        Details:   details,
    }

    m.mutex.Lock()
    defer m.mutex.Unlock()

    if m.shouldLog(level) {
        m.writeEntry(entry)
    }
}

func (m *EventLogger) LogError(event, message, errorMsg string, stack string) {
    entry := LogEntry{
        Timestamp: time.Now(),
        Level:     "error",
        Event:     event,
        Message:   message,
        Error:     errorMsg,
        Stack:     stack,
    }

    m.mutex.Lock()
    defer m.mutex.Unlock()

    m.writeEntry(entry)
}

func (m *EventLogger) writeEntry(entry LogEntry) {
    var line []byte
    switch m.config.Format {
    case "json":
        line, _ = json.Marshal(entry)
        line = append(line, '\n')
    default:
        line = m.formatText(entry)
    }

    m.file.Write(line)
    m.checkRotation()
}

func (m *EventLogger) formatText(entry LogEntry) []byte {
    var b strings.Builder
    b.WriteString(fmt.Sprintf("[%s] %s", entry.Timestamp.Format("2006-01-02 15:04:05"), entry.Level))

    if entry.Event != "" {
        b.WriteString(fmt.Sprintf(": Event %s", entry.Event))
    }

    b.WriteString(fmt.Sprintf(": %s", entry.Message))

    if entry.Error != "" {
        b.WriteString(fmt.Sprintf("\n  Error: %s", entry.Error))
    }

    if len(entry.Details) > 0 {
        b.WriteString("\n  Details:")
        for k, v := range entry.Details {
            b.WriteString(fmt.Sprintf("\n    %s: %v", k, v))
        }
    }

    b.WriteByte('\n')
    return []byte(b.String())
}

func (m *EventLogger) checkRotation() {
    if m.config.MaxSize <= 0 {
        return
    }

    info, _ := m.file.Stat()
    if info.Size() < int64(m.config.MaxSize)*1024*1024 {
        return
    }

    m.rotate()
}

func (m *EventLogger) rotate() {
    // Close current file
    m.file.Close()

    // Rename current to .1
    os.Rename(m.config.Path, m.config.Path+".1")

    // Open new file
    f, _ := os.OpenFile(m.config.Path, os.O_CREATE|os.O_WRONLY, 0644)
    m.file = f
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [Logger](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) - Existing logging
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event flow logging
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Logging config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
