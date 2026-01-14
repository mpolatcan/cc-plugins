# Feature: Notification Stacking 📚

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

When multiple events fire quickly (e.g., multiple `stop` events), queue them and play sequentially instead of overlapping chaos.

## Motivation

- Prevent overlapping sounds from multiple rapid events
- Ensure all notifications are heard
- Reduce audio chaos during high-activity periods
- Maintain notification quality over quantity

---

## Benefit

- **Clearer notifications**: Every sound is distinguishable, no overlaps
- **Complete coverage**: No notifications get lost in the chaos
- **Less stressful audio**: Smooth notification flow instead of audio pile-up
- **Better for focus**: Ordered notifications are less jarring than simultaneous ones

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Medium |
| **Category** | Notification Control |

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
| **Config** | Add | Add `stacking` section with max_pending, flush_interval |
| **Core Logic** | Add | Add `QueueManager` with Enqueue/Flush/Process methods |
| **New File** | Add | `internal/queue/stacking.go` for notification queuing |
| **Main Flow** | Modify | Change from fire-and-forget to queue-based |
| **Commands** | Add | New `stacking` command (status, clear, test) |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/stacking.md** | Add | New command documentation |
| **commands/configure.md** | Update | Add stacking configuration |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/queue/stacking.go:**
```go
type QueueManager struct {
    pending    []PendingNotification
    mutex      sync.Mutex
    maxPending int
    flushChan  chan struct{}
}

type PendingNotification struct {
    Event    string
    Sound    string
    Volume   float64
    QueuedAt time.Time
}

func (q *QueueManager) Enqueue(n PendingNotification) {
    q.mutex.Lock()
    defer q.mutex.Unlock()
    if len(q.pending) >= q.maxPending {
        q.pending = q.pending[1:]
    }
    q.pending = append(q.pending, n)
}

func (q *QueueManager) Flush() []PendingNotification {
    q.mutex.Lock()
    defer q.mutex.Unlock()
    pending := q.pending
    q.pending = nil
    return pending
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cfg := config.Load(homeDir)
    if cfg.Stacking.Enabled {
        queue := queue.NewQueueManager(cfg.Stacking.MaxPending)
        eventType := os.Args[1]
        eventCfg := cfg.GetEventConfig(eventType)
        queue.Enqueue(queue.PendingNotification{
            Event: eventType,
            Sound: *eventCfg.Sound,
            Volume: *eventCfg.Volume,
        })
        fmt.Printf("Queued (%d pending)\n", queue.Count())
    } else {
        // Original behavior
    }
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/stacking.md` for queue management |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.4.0+
- **Config Schema Change**: Adds `stacking` section to config
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/stacking.md` (new file with status, clear, test commands)
  - `plugins/ccbell/commands/configure.md` (update to reference stacking options)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag
- **Architecture Note**: Requires persistent queue manager (daemon or file-based)

### Implementation Checklist

- [ ] Create `commands/stacking.md` with queue management commands
- [ ] Update `commands/configure.md` with stacking configuration
- [ ] When ccbell v0.4.0+ releases, sync version to cc-plugins

---

## References

### ccbell Implementation Research

- [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Short-lived process model that needs to change
- [Current audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Uses `cmd.Start()` for non-blocking playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - For persistent queue storage option

---

[Back to Feature Index](index.md)
