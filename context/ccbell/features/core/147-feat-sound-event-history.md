# Feature: Sound Event History

View and manage event history.

## Summary

Track and display historical sound events.

## Motivation

- Event audit trail
- Review past events
- Usage patterns

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### History Contents

| Field | Description | Example |
|-------|-------------|---------|
| Timestamp | When event occurred | 2024-01-15 10:30 |
| EventType | Type of event | stop |
| Sound | Sound played | bundled:stop |
| Volume | Playback volume | 0.5 |
| Duration | Sound duration | 1.2s |
| Status | Playback result | success/failed |

### Configuration

```go
type HistoryConfig struct {
    Enabled       bool   `json:"enabled"`
    MaxEntries    int    `json:"max_entries"` // 1000
    PerEvent      bool   `json:"per_event"`   // separate history
    IncludeFailed bool   `json:"include_failed"` // log failures
    Storage       string `json:"storage"`     // "memory", "file"
}

type HistoryEntry struct {
    ID          string    `json:"id"`
    Timestamp   time.Time `json:"timestamp"`
    EventType   string    `json:"event_type"`
    SoundID     string    `json:"sound_id"`
    SoundPath   string    `json:"sound_path"`
    Volume      float64   `json:"volume"`
    Duration    float64   `json:"duration_seconds"`
    Status      string    `json:"status"` // "success", "failed"
    Error       string    `json:"error,omitempty"`
}
```

### Commands

```bash
/ccbell:history                   # Show history
/ccbell:history --lines 20        # Recent 20
/ccbell:history event stop        # Filter by event
/ccbell:history today             # Today's events
/ccbell:history --json            # JSON output
/ccbell:history search "stop"     # Search events
/ccbell:history export            # Export history
/ccbell:history clear             # Clear history
/ccbell:history stats             # Show statistics
```

### Output

```
$ ccbell:history --lines 10

=== Sound Event History ===

Total: 1,234 events

Recent Events:

[1] 10:30:15 stop success (bundled:stop, 1.2s, 50%)
[2] 10:28:03 subagent success (custom:complete, 0.8s, 60%)
[3] 10:25:22 permission_prompt failed (error: not found)
[4] 10:15:01 idle_prompt success (bundled:idle, 0.5s, 30%)
[5] 10:00:00 stop success (bundled:stop, 1.2s, 50%)

[Export] [Search] [Clear] [Stats]
```

---

## Audio Player Compatibility

History doesn't play sounds:
- Tracking feature
- No player changes required

---

## Implementation

### History Tracking

```go
type HistoryManager struct {
    config  *HistoryConfig
    entries []*HistoryEntry
    mutex   sync.Mutex
}

func (m *HistoryManager) Record(eventType, soundID, soundPath string, volume float64, status string, err error) {
    if !m.config.Enabled {
        return
    }

    entry := &HistoryEntry{
        ID:        generateID(),
        Timestamp: time.Now(),
        EventType: eventType,
        SoundID:   soundID,
        SoundPath: soundPath,
        Volume:    volume,
        Status:    status,
    }

    if err != nil {
        entry.Error = err.Error()
    }

    m.mutex.Lock()
    m.entries = append([]*HistoryEntry{entry}, m.entries...)

    // Trim to max entries
    if len(m.entries) > m.config.MaxEntries {
        m.entries = m.entries[:m.config.MaxEntries]
    }
    m.mutex.Unlock()

    m.saveHistory()
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - History storage
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Playback tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
