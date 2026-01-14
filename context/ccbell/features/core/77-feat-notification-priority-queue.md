# Feature: Notification Priority Queue

Queue notifications with priority levels.

## Summary

Handle multiple rapid notifications by queuing them with priority ordering.

## Motivation

- Prevent notification loss during bursts
- Priority-based notification order
- Graceful handling of high-frequency events

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Priority Levels

| Level | Value | Description |
|-------|-------|-------------|
| Critical | 100 | Permission prompts, errors |
| High | 75 | Subagent completion |
| Normal | 50 | Stop events |
| Low | 25 | Idle prompts |
| Background | 10 | Low priority |

### Configuration

```json
{
  "queue": {
    "enabled": true,
    "max_size": 20,
    "play_delay_ms": 500,
    "priorities": {
      "permission_prompt": 100,
      "subagent": 75,
      "stop": 50,
      "idle_prompt": 25
    },
    "drop_policy": "lowest",  // "lowest", "oldest", "newest"
    "merge_same": true
  }
}
```

### Implementation

```go
type PriorityQueue struct {
    mu       sync.Mutex
    items    []*QueuedNotification
    maxSize  int
    running  bool
}

type QueuedNotification struct {
    EventType   string
    SoundPath   string
    Volume      float64
    Priority    int
    Timestamp   time.Time
    Profile     string
}

func (q *PriorityQueue) Add(notification *QueuedNotification) {
    q.mu.Lock()
    defer q.mu.Unlock()

    // Check size limit
    if len(q.items) >= q.maxSize {
        q.dropOne(notification.Priority)
    }

    // Find insertion point (priority queue)
    insertIdx := sort.Search(len(q.items), func(i int) bool {
        return q.items[i].Priority < notification.Priority
    })

    q.items = append(q.items, &QueuedNotification{})
    copy(q.items[insertIdx+1:], q.items[insertIdx:])
    q.items[insertIdx] = notification

    // Start processor if not running
    if !q.running {
        q.running = true
        go q.process()
    }
}
```

### Queue Processing

```go
func (q *PriorityQueue) process() {
    for {
        q.mu.Lock()
        if len(q.items) == 0 {
            q.running = false
            q.mu.Unlock()
            return
        }

        item := q.items[0]
        q.items = q.items[1:]
        q.mu.Unlock()

        // Play notification
        player := audio.NewPlayer(pluginRoot)
        player.Play(item.SoundPath, item.Volume)

        // Wait before next
        time.Sleep(queueConfig.PlayDelayMs * time.Millisecond)
    }
}
```

### Commands

```bash
/ccbell:queue status              # Show queue status
/ccbell:queue list                # List queued items
/ccbell:queue clear               # Clear queue
/ccbell:queue pause               # Pause processing
/ccbell:queue resume              # Resume processing
/ccbell:queue max-size 20         # Set max queue size
```

### Output

```
$ ccbell:queue status

=== Notification Queue ===

Status: Running
Max size: 20
Current items: 5
Play delay: 500ms

Queued items:
[1] Critical permission_prompt  (2s ago)
[2] High subagent              (1s ago)
[3] Normal stop                (now)
[4] Normal stop                (1s waiting)
[5] Low idle_prompt            (3s waiting)

Processing: Critical permission_prompt
Next: High subagent
```

---

## Audio Player Compatibility

Priority queue uses existing audio player:
- Calls `player.Play()` for queued items
- Same format support
- No player changes required

---

## Implementation

### Merge Same Events

```go
func (q *PriorityQueue) addWithMerge(notification *QueuedNotification) {
    // Check if same event already queued
    for _, item := range q.items {
        if item.EventType == notification.EventType && queueConfig.MergeSame {
            // Skip - already queued
            return
        }
    }
    q.Add(notification)
}
```

### Drop Policy

```go
func (q *PriorityQueue) dropOne(newPriority int) {
    switch queueConfig.DropPolicy {
    case "lowest":
        // Remove lowest priority item
        q.items = q.items[len(q.items)-1]
    case "oldest":
        // Remove oldest item
        q.items = q.items[1:]
    case "newest":
        // Don't add new item (drop incoming)
        // Or remove most recent
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Queue integration
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-L113) - Playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State pattern

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Queue processing |
| Linux | ✅ Supported | Queue processing |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
