# Feature: Sound Event Prioritization

Prioritize events over each other.

## Summary

Define priority levels for different event types.

## Motivation

- Critical notifications first
- Resource allocation
- User preferences

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Priority Levels

| Level | Value | Default Events |
|-------|-------|----------------|
| Critical | 100 | (user-defined) |
| High | 75 | permission_prompt |
| Normal | 50 | stop, subagent |
| Low | 25 | idle_prompt |
| Background | 10 | (user-defined) |

### Configuration

```go
type PriorityConfig struct {
    Enabled          bool              `json:"enabled"`
    DefaultPriority  int               `json:"default_priority"` // 50
    PerEvent         map[string]int    `json:"per_event"`        // event -> priority
    QueueBehavior    string            `json:"queue_behavior"`   // "priority", "fifo", "mixed"
    PreemptRunning   bool              `json:"preempt_running"`  // high priority preempts
    DropLowOnHighLoad bool             `json:"drop_low_on_high_load"`
}

type PriorityLevel struct {
    Name  string `json:"name"`
    Value int    `json:"value"`
    Color string `json:"color"` // for display
}
```

### Commands

```bash
/ccbell:priority list               # List priorities
/ccbell:priority set stop 50        # Set stop priority
/ccbell:priority set critical permission_prompt
/ccbell:priority set default 50     # Set default priority
/ccbell:priority queue priority     # Queue by priority
/ccbell:priority queue fifo         # Queue FIFO
/ccbell:priority preempt enable     # Allow preemption
/ccbell:priority status             # Show priority status
```

### Output

```
$ ccbell:priority list

=== Sound Event Priorities ===

Priority Levels:
  Critical (100): [permission_prompt]
  High (75): []
  Normal (50): [stop, subagent] (default)
  Low (25): [idle_prompt]
  Background (10): []

Queue Behavior: Priority

Current Queue:
  [1] Critical permission_prompt (waiting 0s)
  [2] High (empty)
  [3] Normal stop (waiting 1s)
  [4] Normal subagent (waiting 2s)
  [5] Low idle_prompt (waiting 5s)

[Configure] [Reorder] [Reset]
```

---

## Audio Player Compatibility

Prioritization works with existing audio player:
- Controls playback order
- Same format support
- No player changes required

---

## Implementation

### Priority Queue

```go
type PriorityQueue struct {
    mu     sync.Mutex
    queues map[int][]*QueuedEvent
    running bool
}

func (p *PriorityQueue) Add(event *QueuedEvent) {
    priority := p.getEventPriority(event.EventType)

    p.mu.Lock()
    defer p.mu.Unlock()

    p.queues[priority] = append(p.queues[priority], event)

    if !p.running {
        p.running = true
        go p.process()
    }
}

func (p *PriorityQueue) process() {
    for {
        priority := p.getHighestPriority()

        p.mu.Lock()
        if len(p.queues[priority]) == 0 {
            p.running = false
            p.mu.Unlock()
            return
        }

        event := p.queues[priority][0]
        p.queues[priority] = p.queues[priority][1:]
        p.mu.Unlock()

        p.playEvent(event)
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

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
