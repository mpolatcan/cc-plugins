# Feature: Sound Event Queuing

Queue events for ordered playback.

## Summary

Queue events and play them in order with control.

## Motivation

- Ordered playback
- Event sequencing
- Queue management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Queue Types

| Type | Description | Example |
|------|-------------|---------|
| FIFO | First in, first out | Standard queue |
| Priority | Priority-based | Critical first |
| LIFO | Last in, first out | Latest first |
| Custom | Custom ordering | User-defined |

### Configuration

```go
type QueueConfig struct {
    Enabled       bool   `json:"enabled"`
    QueueType     string `json:"queue_type"` // "fifo", "priority", "lifo"
    MaxSize       int    `json:"max_size"`   // 100
    OverflowPolicy string `json:"overflow_policy"` // "reject", "drop_oldest"
    AutoPlay      bool   `json:"auto_play"`  // auto-play queued
    PreserveOrder bool   `json:"preserve_order"` // keep event order
}

type QueuedEvent struct {
    ID        string    `json:"id"`
    EventType string    `json:"event_type"`
    SoundID   string    `json:"sound_id"`
    SoundPath string    `json:"sound_path"`
    Volume    float64   `json:"volume"`
    Priority  int       `json:"priority"` // for priority queue
    QueuedAt  time.Time `json:"queued_at"`
}
```

### Commands

```bash
/ccbell:queue status                # Show queue status
/ccbell:queue list                  # List queued events
/ccbell:queue add stop              # Add to queue
/ccbell:queue add permission_prompt priority=100
/ccbell:queue play                  # Play queue
/ccbell:queue clear                 # Clear queue
/ccbell:queue remove <id>           # Remove specific event
/ccbell:queue type priority         # Set queue type
/ccbell:queue max 50                # Set max size
```

### Output

```
$ ccbell:queue list

=== Sound Event Queue ===

Status: Active
Type: FIFO
Size: 5 / 100
Auto-play: Yes

Queued Events:

[1] stop (bundled:stop) - Queued 2s ago
[2] subagent (custom:complete) - Queued 1s ago
[3] permission_prompt (bundled:permission) - Queued 30s ago

[Play] [Remove All] [Configure]
```

---

## Audio Player Compatibility

Queuing uses existing audio player:
- Sequential `player.Play()` calls
- Same format support
- No player changes required

---

## Implementation

### Queue Management

```go
type EventQueue struct {
    config  *QueueConfig
    mutex   sync.Mutex
    events  []*QueuedEvent
    running bool
}

func (q *EventQueue) Add(event *QueuedEvent) {
    q.mutex.Lock()
    defer q.mutex.Unlock()

    // Check size
    if len(q.events) >= q.config.MaxSize {
        switch q.config.OverflowPolicy {
        case "drop_oldest":
            q.events = q.events[1:]
        case "reject":
            return
        }
    }

    q.events = append(q.events, event)

    if !q.running && q.config.AutoPlay {
        q.running = true
        go q.process()
    }
}

func (q *EventQueue) process() {
    for {
        q.mutex.Lock()
        if len(q.events) == 0 {
            q.running = false
            q.mutex.Unlock()
            return
        }

        event := q.events[0]
        q.events = q.events[1:]
        q.mutex.Unlock()

        player := audio.NewPlayer(q.pluginRoot)
        player.Play(event.SoundPath, event.Volume)
    }
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Queue playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Queue state

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
