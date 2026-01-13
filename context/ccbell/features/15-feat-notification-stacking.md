# Feature: Notification Stacking

Queue rapid notifications and play them as a sequence.

## Summary

When multiple events fire quickly (e.g., multiple `stop` events), queue them and play sequentially instead of overlapping chaos.

## Technical Feasibility

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
