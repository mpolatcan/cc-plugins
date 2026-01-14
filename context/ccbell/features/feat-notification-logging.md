# Feature: Notification Logging 📋

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Maintain a detailed log of all notification events for debugging and analysis.

## Motivation:

- Debug notification issues
- Track notification history
- Analyze patterns over time

---

## Benefit

- **Historical visibility**: Review what notifications fired and when
- **Pattern recognition**: Identify trends in Claude Code usage
- **Audit trail**: Track notification behavior for troubleshooting
- **Data-driven optimization**: Use log data to refine notification settings

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Logging |

---

## Technical Feasibility

### Log Format

```
2026-01-14 10:32:05 [INFO]  stop      /Users/me/.claude/ccbell/sounds/stop.aiff   vol=0.50
2026-01-14 10:32:08 [INFO]  permission  bundled:permission_prompt.aiff           vol=0.70
2026-01-14 10:32:15 [INFO]  idle      bundled:idle_prompt.aiff                   vol=0.50 suppressed=quiet_hours
```

### Implementation

```go
type NotificationLogger struct {
    path      string
    maxSize   int64
    maxFiles  int
    formatter *Formatter
}

type LogEntry struct {
    Timestamp   time.Time
    Level       string
    EventType   string
    Sound       string
    Volume      float64
    Profile     string
    Reason      string  // "played", "suppressed_quiet_hours", "suppressed_cooldown"
}
```

### Log Writing

```go
func (l *NotificationLogger) Log(entry LogEntry) error {
    // Check log rotation
    if l.needsRotation() {
        if err := l.rotate(); err != nil {
            return err
        }
    }

    line := l.formatter.Format(entry)
    f, err := os.OpenFile(l.path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
    if err != nil {
        return err
    }
    defer f.Close()

    _, err = f.WriteString(line + "\n")
    return err
}
```

### Log Rotation

```go
func (l *NotificationLogger) needsRotation() bool {
    info, err := os.Stat(l.path)
    if err != nil {
        return false
    }
    return info.Size() > l.maxSize
}

func (l *NotificationLogger) rotate() error {
    // Rename current log
    timestamp := time.Now().Format("2006-01-02_15-04-05")
    newPath := fmt.Sprintf("%s.%s.log", l.path, timestamp)

    if err := os.Rename(l.path, newPath); err != nil {
        return err
    }

    // Clean old files
    l.cleanOldFiles()

    return nil
}
```

### Configuration

```json
{
  "logging": {
    "enabled": true,
    "path": "~/.claude/ccbell/notification.log",
    "level": "info",  // "debug", "info", "warn", "error"
    "max_size_mb": 10,
    "max_files": 5,
    "include_suppressed": true
  }
}
```

### Commands

```bash
/ccbell:log tail               # Show recent logs
/ccbell:log tail -f            # Follow log file
/ccbell:log show --today       # Today's logs
/ccbell:log show stop          # Stop event logs
/ccbell:log clear              # Clear log file
/ccbell:log stats              # Log statistics
```

### Log Statistics

```
$ /ccbell:log stats

=== Notification Log Statistics ===

Total events: 1,234
Played:       1,100 (89.1%)
Suppressed:   134 (10.9%)

By event:
  stop:              800 (64.8%)
  permission_prompt: 200 (16.2%)
  idle_prompt:       150 (12.2%)
  subagent:          84 (6.8%)

Suppression reasons:
  quiet_hours:       100
  cooldown:          30
  disabled:          4
```

---

## Audio Player Compatibility

Notification logging doesn't interact with audio playback:
- Logs after decision to play
- No player changes required
- Purely I/O operation

---

## Implementation

### Formatter

```go
type Formatter struct {
    Format string  // "json", "text"
}

func (f *Formatter) Format(entry LogEntry) string {
    switch f.Format {
    case "json":
        return f.formatJSON(entry)
    default:
        return f.formatText(entry)
    }
}

func (f *Formatter) formatText(entry LogEntry) string {
    return fmt.Sprintf("%s [%s]  %-16s %-45s vol=%.2f",
        entry.Timestamp.Format("2006-01-02 15:04:05"),
        entry.Level,
        entry.EventType,
        entry.Sound,
        entry.Volume)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `logging` section with path, format, retention options |
| **Core Logic** | Add | Add `Logger` struct with Append() and Rotate() methods |
| **New File** | Add | `internal/logger/notification.go` for notification logging |
| **Commands** | Add | New `log` command (tail, show, clear, stats) |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/log.md** | Add | New command documentation |
| **commands/status.md** | Update | Add logging status |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/logger/notification.go:**
```go
type NotificationLog struct {
    Path        string
    MaxSizeMB   int
    MaxFiles    int
    entries     []LogEntry
    mutex       sync.Mutex
}

type LogEntry struct {
    Timestamp   time.Time `json:"timestamp"`
    Event       string    `json:"event"`
    Sound       string    `json:"sound"`
    Volume      float64   `json:"volume"`
    Duration    float64   `json:"duration_seconds"`
    Cooldown    bool      `json:"cooldown"`
    QuietHours  bool      `json:"quiet_hours"`
}

func (l *NotificationLog) Append(entry LogEntry) error {
    l.mutex.Lock()
    defer l.mutex.Unlock()

    l.entries = append(l.entries, entry)

    // Write to file
    data, _ := json.Marshal(entry)
    _, err := os.OpenFile(l.Path, os.O_APPEND|os.O_CREATE, 0644)
    // ... file write with rotation check
    return err
}

func (l *NotificationLog) Tail(n int) []LogEntry {
    l.mutex.Lock()
    defer l.mutex.Unlock()

    if len(l.entries) <= n {
        return l.entries
    }
    return l.entries[len(l.entries)-n:]
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    if len(os.Args) > 1 && os.Args[1] == "log" {
        handleLogCommand(os.Args[2:])
        return
    }

    // After playing sound
    if cfg.Logging.Enabled {
        logEntry := logger.LogEntry{
            Timestamp:  time.Now(),
            Event:      eventType,
            Sound:      eventCfg.Sound,
            Volume:     *eventCfg.Volume,
            Duration:   duration.Seconds(),
            Cooldown:   inCooldown,
            QuietHours: inQuietHours,
        }
        cfg.Logging.Append(logEntry)
    }
}
```

---

## References

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State pattern
- [Logger pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go) - Existing logger

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/log.md` for log viewing commands |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `logging` section to config
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/log.md` (new file with tail, show, clear, stats commands)
  - `plugins/ccbell/commands/status.md` (update to reference logging status)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/log.md` with log viewing commands
- [ ] Update `commands/status.md` with logging status
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | File I/O |
| Linux | ✅ Supported | File I/O |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

---

[Back to Feature Index](index.md)
