# Feature: Notification Stacking

Queue rapid notifications and play them as a sequence.

## Summary

When multiple events fire quickly (e.g., multiple `stop` events), queue them and play sequentially instead of overlapping chaos.

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Current Architecture Analysis

The current `cmd/ccbell/main.go` is a short-lived process:
1. Each invocation is independent
2. Uses `cmd.Start()` for non-blocking playback
3. No inter-process communication

**Key Finding**: Notification stacking requires either:
- A persistent daemon process, OR
- External queue management (e.g., files, Redis)

### Queue Implementation

```go
type NotificationQueue struct {
    pending   []QueuedNotification
    mutex     sync.Mutex
    processing bool
    maxSize   int
}

type QueuedNotification struct {
    Event   string
    Sound   string
    Time    time.Time
}

func (q *NotificationQueue) Add(event, sound string) {
    q.mutex.Lock()
    defer q.mutex.Unlock()

    if len(q.pending) >= q.maxSize {
        // Drop oldest or new? Configurable
        q.pending = q.pending[1:]
    }
    q.pending = append(q.pending, QueuedNotification{
        Event: event,
        Sound: sound,
        Time:  time.Now(),
    })

    if !q.processing {
        go q.process()
    }
}
```

### Sequential Playback

```go
func (q *NotificationQueue) process() {
    q.mutex.Lock()
    q.processing = true
    defer q.mutex.Unlock()

    for len(q.pending) > 0 {
        item := q.pending[0]
        q.pending = q.pending[1:]

        // Play with small delay between
        c.playSound(item.Sound)
        time.Sleep(500 * time.Millisecond)
    }

    q.processing = false
}
```

---

## Feasibility Research

### Audio Player Compatibility

Notification stacking requires changes to the execution model:
- Current: Independent process per event
- Required: Persistent queue manager

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Daemon | Internal | Free | Requires new process |
| or File Queue | Local storage | Free | Simpler, less reliable |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | With daemon |
| Linux | ✅ Supported | With daemon |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

### Architectural Options

| Option | Pros | Cons |
|--------|------|------|
| **File-based queue** | Simple, no daemon | Race conditions possible |
| **Daemon process** | Reliable, real-time | Complex, requires auto-start |
| **External (Redis)** | Robust | Requires external service |

**Recommendation:** Start with file-based queue for simplicity.

---

## Configuration

```json
{
  "stacking": {
    "enabled": true,
    "max_queue": 10,
    "play_delay": "500ms",
    "drop_policy": "oldest" // or "newest"
  }
}
```

## Commands

```bash
/ccbell:stacking status
/ccbell:stacking clear
/ccbell:stacking test
```

---

## References

- [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
