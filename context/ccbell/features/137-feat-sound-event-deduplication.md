# Feature: Sound Event Deduplication

Deduplicate similar sound events.

## Summary

Detect and merge similar or duplicate sound events.

## Motivation

- Reduce duplicate notifications
- Merge related events
- Clean event stream

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Deduplication Types

| Type | Description | Example |
|------|-------------|---------|
| Exact | Same sound, same event | Duplicate stop |
| Similar | Similar sounds | Different stop variants |
| Related | Related events | Stop + subagent |

### Configuration

```go
type DeduplicationConfig struct {
    Enabled         bool            `json:"enabled"`
    ExactMatch      bool            `json:"exact_match"`
    SimilarSound    bool            `json:"similar_sound"`
    SimilarityThreshold float64     `json:"similarity_threshold"` // 0.8
    TimeWindowMs    int             `json:"time_window_ms"`      // dedup window
    PerEvent        bool            `json:"per_event"`           // dedup per event
    MergePolicy     string          `json:"merge_policy"`        // "first", "last", "louder"
}

type DeduplicationEntry struct {
    EventType   string        `json:"event_type"`
    SoundID     string        `json:"sound_id"`
    FirstSeen   time.Time     `json:"first_seen"`
    LastSeen    time.Time     `json:"last_seen"`
    Count       int           `json:"count"`
}
```

### Commands

```bash
/ccbell:dedup enable                # Enable deduplication
/ccbell:dedup disable               # Disable deduplication
/ccbell:dedup set window 2000       # 2 second window
/ccbell:dedup set threshold 0.9     # 90% similarity
/ccbell:dedup status                # Show deduplication status
/ccbell:dedup history               # Show dedup history
/ccbell:dedup clear                 # Clear deduplication cache
/ccbell:dedup stats                 # Show deduplication statistics
```

### Output

```
$ ccbell:dedup status

=== Sound Deduplication ===

Status: Enabled
Window: 2s
Similarity: 90%

Deduplicated Events (Last Hour):
  stop: 12 duplicates merged
  permission_prompt: 5 duplicates merged
  subagent: 3 duplicates merged

Current Buffer:
  [stop] bundled:stop (1s ago) [1]
  [subagent] custom:complete (0.5s ago) [1]

Savings: 20 notifications (saved 45s of playback)

[Configure] [History] [Stats]
```

---

## Audio Player Compatibility

Deduplication doesn't play sounds:
- Reduces playback calls
- No player changes required

---

## Implementation

### Event Buffering

```go
type Deduplicator struct {
    config  *DeduplicationConfig
    buffer  map[string]*DeduplicationEntry
    mutex   sync.Mutex
}

func (d *Deduplicator) HandleEvent(eventType, soundID string) (*DeduplicationEntry, bool) {
    d.mutex.Lock()
    defer d.mutex.Unlock()

    key := d.getKey(eventType, soundID)

    // Check if similar event exists
    if existing, ok := d.buffer[key]; ok {
        if d.isWithinWindow(existing) {
            existing.Count++
            existing.LastSeen = time.Now()
            return existing, true // Deduplicated
        }
    }

    // Add new entry
    entry := &DeduplicationEntry{
        EventType:  eventType,
        SoundID:    soundID,
        FirstSeen:  time.Now(),
        LastSeen:   time.Now(),
        Count:      1,
    }
    d.buffer[key] = entry

    return entry, false // Not deduplicated
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Deduplication state
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
