# Feature: Notification Stacking 📚

## Summary

When multiple events fire quickly, queue them and play sequentially instead of overlapping.

## Benefit

- **Clearer notifications**: Every sound is distinguishable
- **Complete coverage**: No notifications get lost in chaos
- **Less stressful audio**: Smooth notification flow
- **Better for focus**: Ordered notifications are less jarring

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Nice to Have |
| **Complexity** | Medium |
| **Category** | Notification Control |

## Technical Feasibility

### Configuration

```json
{
  "stacking": {
    "enabled": true,
    "max_queue": 10,
    "play_delay": "500ms",
    "drop_policy": "oldest"
  }
}
```

### Implementation

```go
type QueueManager struct {
    pending    []PendingNotification
    mutex      sync.Mutex
    maxPending int
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
```

### Commands

```bash
/ccbell:stacking status
/ccbell:stacking clear
/ccbell:stacking test
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | `stacking` section |
| **Core Logic** | Add | `QueueManager` with Enqueue/Flush |
| **New File** | Add | `internal/queue/stacking.go` |
| **Commands** | Add | `stacking` command |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/stacking.md** | Add | New command doc |
| **commands/configure.md** | Update | Add stacking section |
| **scripts/ccbell.sh** | Version sync | Match ccbell release |

## References

- [Current main.go](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)
- [Audio player](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go)
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go)

---

[Back to Feature Index](index.md)
