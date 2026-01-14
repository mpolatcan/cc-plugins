# Feature: Sound Event Priority Queue

Manage event playback priority.

## Summary

Priority queue for events so higher priority events can interrupt lower priority ones.

## Motivation

- Interrupt low-priority with high-priority
- Queue management
- Event prioritization

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Priority Levels

| Level | Description | Example |
|-------|-------------|---------|
| Critical | Must play immediately | Error alerts |
| High | Important events | Stop response |
| Normal | Standard events | Default |
| Low | Non-urgent | Background |

### Configuration

```go
type PriorityConfig struct {
    Enabled       bool              `json:"enabled"`
    DefaultPriority string         `json:"default_priority"` // "normal"
    QueueSize     int               `json:"queue_size"` // 10 max queued
    AllowInterrupt bool             `json:"allow_interrupt"`
}

type PriorityEvent struct {
    EventType   string
    Priority    string
    Sound       string
    Volume      float64
    Timestamp   time.Time
}

type PriorityQueue struct {
    events    []*PriorityEvent
    mutex     sync.Mutex
    cond      *sync.Cond
}
```

### Commands

```bash
/ccbell:priority status             # Show queue status
/ccbell:priority set default normal # Set default priority
/ccbell:priority set stop critical  # Set stop priority
/ccbell:priority list               # List queued events
/ccbell:priority clear              # Clear queue
/ccbell:priority enable interrupt   # Enable interruption
/ccbell:priority disable            # Disable priority queue
```

### Output

```
$ ccbell:priority status

=== Sound Event Priority Queue ===

Status: Enabled
Default Priority: Normal
Queue Size: 5
Allow Interrupt: Yes

Queue:
  [1] permission_prompt (normal) - waiting
  [2] idle_prompt (low) - waiting
  [3] stop (high) - next to play

Priority Levels:
  Critical: Error alerts, system events
  High: stop, subagent
  Normal: permission_prompt
  Low: idle_prompt

[Configure] [Clear] [List]
```

---

## Audio Player Compatibility

Priority queue works with all audio players:
- Uses existing playback
- No player changes required

---

## Implementation

### Priority Queue Manager

```go
type PriorityManager struct {
    config   *PriorityConfig
    player   *audio.Player
    queue    *PriorityQueue
    running  bool
    stopCh   chan struct{}
}

func (m *PriorityManager) Add(event *PriorityEvent) {
    m.queue.mutex.Lock()
    defer m.queue.mutex.Unlock()

    if len(m.queue.events) >= m.config.QueueSize {
        // Remove lowest priority if queue full
        m.queue.events = m.queue.events[1:]
    }

    m.queue.events = append(m.queue.events, event)
    m.queue.cond.Signal()
}

func (m *PriorityManager) process() {
    for {
        m.queue.mutex.Lock()
        for len(m.queue.events) == 0 {
            m.queue.cond.Wait()
        }

        // Sort by priority
        sort.Slice(m.queue.events, func(i, j int) bool {
            return m.getPriorityValue(m.queue.events[i].Priority) >
                   m.getPriorityValue(m.queue.events[j].Priority)
        })

        event := m.queue.events[0]
        m.queue.events = m.queue.events[1:]
        m.queue.mutex.Unlock()

        // Play event
        m.player.Play(event.Sound, event.Volume)
    }
}

func (m *PriorityManager) getPriorityValue(priority string) int {
    switch priority {
    case "critical": return 4
    case "high": return 3
    case "normal": return 2
    case "low": return 1
    default: return 0
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

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
