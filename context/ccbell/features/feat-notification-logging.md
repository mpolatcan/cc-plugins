# Feature: Notification Logging 📋

## Summary

Maintain a detailed log of all notification events for debugging and analysis.

## Benefit

- **Historical visibility**: Review what notifications fired and when
- **Pattern recognition**: Identify trends in Claude Code usage
- **Audit trail**: Track notification behavior for troubleshooting
- **Data-driven optimization**: Refine settings based on log data

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Category** | Logging |

## Technical Feasibility

### Log Format

```
2026-01-14 10:32:05 [INFO]  stop      ~/.claude/ccbell/sounds/stop.aiff   vol=0.50
2026-01-14 10:32:08 [INFO]  permission  bundled:permission_prompt.aiff   vol=0.70
2026-01-14 10:32:15 [INFO]  idle      bundled:idle_prompt.aiff           suppressed=quiet_hours
```

### Configuration

```json
{
  "logging": {
    "enabled": true,
    "path": "~/.claude/ccbell/notification.log",
    "level": "info",
    "max_size_mb": 10,
    "max_files": 5
  }
}
```

### Implementation

```go
type NotificationLog struct {
    Path      string
    MaxSizeMB int
    MaxFiles  int
}

type LogEntry struct {
    Timestamp  time.Time
    Event      string
    Sound      string
    Volume     float64
    Reason     string  // "played", "suppressed_quiet_hours", "suppressed_cooldown"
}

func (l *NotificationLog) Append(entry LogEntry) error {
    data, _ := json.Marshal(entry)
    f, _ := os.OpenFile(l.Path, os.O_APPEND|os.O_CREATE, 0644)
    defer f.Close()
    _, err := f.WriteString(string(data) + "\n")
    return err
}
```

### Commands

```bash
/ccbell:log tail               # Show recent logs
/ccbell:log show --today       # Today's logs
/ccbell:log clear              # Clear log file
/ccbell:log stats              # Log statistics
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `logging` section |
| **Core Logic** | Add | `Logger` with Append/Rotate |
| **New File** | Add | `internal/logger/notification.go` |
| **Commands** | Add | `log` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/log.md** | Add | New command doc |
| **commands/status.md** | Update | Add logging status |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)
- [Logger pattern](https://github.com/mpolatcan/ccbell/blob/main/internal/logger/logger.go)

---

[Back to Feature Index](index.md)
