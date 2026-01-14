# Feature: Sound Event Logging

Log all sound events.

## Summary

Comprehensive logging of sound events and playback.

## Motivation

- Audit trail
- Debugging
- Usage tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Log Contents

| Field | Description | Example |
|-------|-------------|---------|
| Timestamp | When event occurred | 2024-01-15 10:30:15 |
| EventType | Type of event | stop |
| SoundID | Sound that played | bundled:stop |
| Volume | Playback volume | 0.5 |
| Duration | Sound duration | 1.234s |
| Status | Playback status | success/failed |
| Latency | Time to start | 45ms |

### Configuration

```go
type LoggingConfig struct {
    Enabled       bool     `json:"enabled"`
    LogFile       string   `json:"log_file"`
    MaxSizeMB     int      `json:"max_size_mb"`
    MaxFiles      int      `json:"max_files"`
    Format        string   `json:"format"` // "json", "text", "csv"
    IncludeFields []string `json:"include_fields"`
    PerEvent      bool     `json:"per_event"` // separate logs per event
}

type LogEntry struct {
    Timestamp   time.Time `json:"timestamp"`
    EventType   string    `json:"event_type"`
    SoundID     string    `json:"sound_id"`
    SoundPath   string    `json:"sound_path"`
    Volume      float64   `json:"volume"`
    Duration    float64   `json:"duration_seconds"`
    Status      string    `json:"status"` // "success", "failed"
    Error       string    `json:"error,omitempty"`
    LatencyMs   int64     `json:"latency_ms"`
    Platform    string    `json:"platform"`
}
```

### Commands

```bash
/ccbell:log enable                  # Enable logging
/ccbell:log disable                 # Disable logging
/ccbell:log set file ~/.ccbell.log  # Set log file
/ccbell:log set format json         # JSON format
/ccbell:log set size 10             # 10MB max
/ccbell:log show                    # Show recent logs
/ccbell:log tail                    # Tail log file
/ccbell:log clear                   # Clear logs
/ccbell:log export                  # Export logs
```

### Output

```
$ ccbell:log show --lines 10

=== Sound Event Log ===

Format: JSON
File: ~/.ccbell.log (1.2 MB)

[2024-01-15 10:30:15.123] stop success
  bundled:stop, vol=0.5, dur=1.2s, latency=45ms

[2024-01-15 10:28:03.456] subagent success
  custom:complete, vol=0.6, dur=0.8s, latency=52ms

[2024-01-15 10:15:22.789] permission_prompt failed
  bundled:permission_prompt, error="sound not found"

[2024-01-15 10:00:01.012] idle_prompt success
  bundled:idle_prompt, vol=0.3, dur=0.5s, latency=38ms

...

[Export] [Clear] [Configure]
```

---

## Audio Player Compatibility

Logging doesn't play sounds:
- Records playback information
- No player changes required

---

## Implementation

### Log Writing

```go
type Logger struct {
    config  *LoggingConfig
    file    *os.File
    encoder *json.Encoder
}

func (l *Logger) Log(entry *LogEntry) error {
    if !l.config.Enabled {
        return nil
    }

    switch l.config.Format {
    case "json":
        return l.encoder.Encode(entry)
    case "text":
        return l.writeText(entry)
    case "csv":
        return l.writeCSV(entry)
    }

    return nil
}

func (l *Logger) writeText(entry *LogEntry) error {
    line := fmt.Sprintf("[%s] %s %s vol=%.2f dur=%.1fs latency=%dms\n",
        entry.Timestamp.Format("2006-01-02 15:04:05.000"),
        entry.EventType,
        entry.Status,
        entry.Volume,
        entry.Duration,
        entry.LatencyMs,
    )

    _, err := l.file.WriteString(line)
    return err
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
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event logging

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
