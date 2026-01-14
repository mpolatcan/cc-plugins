# Feature: Sound Event Batching

Batch multiple events together.

## Summary

Collect and play multiple events in a batch.

## Motivation

- Reduce interruptions
- Batch similar notifications
- User control

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Batching Modes

| Mode | Description | Example |
|------|-------------|---------|
| Time-based | Batch for N seconds | 5s window |
| Count-based | Batch N events | 3 events |
| Manual | User triggers batch | Manual play |
| Smart | Smart batching | Same event |

### Configuration

```go
type BatchConfig struct {
    Enabled         bool              `json:"enabled"`
    Mode            string            `json:"mode"` // "time", "count", "manual", "smart"
    TimeWindowMs    int               `json:"time_window_ms"` // 5000
    CountThreshold  int               `json:"count_threshold"` // 3
    MaxBatchSize    int               `json:"max_batch_size"` // 10
    PlayPolicy      string            `json:"play_policy"` // "sequential", "overlay", "first"
    PerEvent        map[string]BatchSettings `json:"per_event"`
}

type BatchSettings struct {
    Enabled     bool   `json:"enabled"`
    Mode        string `json:"mode"`
    TimeWindowMs int  `json:"time_window_ms"`
    CountThreshold int `json:"count_threshold"`
}

type BatchedEvent struct {
    ID        string    `json:"id"`
    Events    []*QueuedEvent `json:"events"`
    CreatedAt time.Time `json:"created_at"`
    Count     int       `json:"count"`
}
```

### Commands

```bash
/ccbell:batch enable                # Enable batching
/ccbell:batch disable               # Disable batching
/ccbell:batch mode time 5000        # 5 second window
/ccbell:batch mode count 3          # Batch 3 events
/ccbell:batch mode smart            # Smart batching
/ccbell:batch play                  # Play batched events
/ccbell:batch clear                 # Clear batch
/ccbell:batch status                # Show batch status
```

### Output

```
$ ccbell:batch status

=== Sound Event Batching ===

Status: Enabled
Mode: Time (5s window)
Current Batch: 2 events (waiting 3s)

Batched Events:
  [1] stop (bundled:stop) 2s ago
  [2] subagent (custom:complete) 1s ago

Auto-play in: 3s
[Play Now] [Clear] [Configure]
```

---

## Audio Player Compatibility

Batching uses existing audio player:
- Plays events in sequence or batch
- Same format support
- No player changes required

---

## Implementation

### Batch Processing

```go
type Batcher struct {
    config  *BatchConfig
    buffer  []*QueuedEvent
    timer   *time.Timer
    mutex   sync.Mutex
    cond    *sync.Cond
}

func (b *Batcher) Add(event *QueuedEvent) {
    b.mutex.Lock()
    defer b.mutex.Unlock()

    b.buffer = append(b.buffer, event)

    // Reset timer
    if b.timer != nil {
        b.timer.Stop()
    }

    switch b.config.Mode {
    case "time":
        b.timer = time.AfterFunc(time.Duration(b.config.TimeWindowMs)*time.Millisecond, b.flush)
    case "count":
        if len(b.buffer) >= b.config.CountThreshold {
            b.flush()
        }
    }
}

func (b *Batcher) flush() {
    b.mutex.Lock()
    events := b.buffer
    b.buffer = nil
    b.mutex.Unlock()

    b.playBatch(events)
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Batch playback
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Batch state

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
