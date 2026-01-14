# Feature: Sound Event Aggregation

Aggregate multiple events into single notifications.

## Summary

Group multiple similar events into a single notification.

## Motivation

- Reduce notification spam
- Batch similar events
- Smart aggregation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Aggregation Rules

| Rule | Description | Example |
|------|-------------|---------|
| Same event | Group same event type | 3 stop events -> 1 |
| Time window | Within time window | All in 1 min |
| Smart | Smart grouping | Related events |

### Configuration

```go
type AggregationConfig struct {
    Enabled         bool              `json:"enabled"`
    WindowSec       int               `json:"window_sec"`       // aggregation window
    MaxGroup        int               `json:"max_group"`        // max events to group
    SameEventRules  []SameEventRule   `json:"same_event_rules"`
    SmartRules      []SmartRule       `json:"smart_rules"`
    OnAggregate     string            `json:"on_aggregate"`     // action when aggregated
}

type SameEventRule struct {
    EventType  string `json:"event_type"`
    MaxCount   int    `json:"max_count"`    // aggregate after N
    WindowSec  int    `json:"window_sec"`
}

type AggregatedEvent struct {
    ID          string    `json:"id"`
    OriginalIDs []string  `json:"original_ids"`
    EventType   string    `json:"event_type"`
    Count       int       `json:"count"`
    FirstTime   time.Time `json:"first_time"`
    LastTime    time.Time `json:"last_time"`
    SoundID     string    `json:"sound_id"`
    Volume      float64   `json:"volume"`
}
```

### Commands

```bash
/ccbell:aggregate enable            # Enable aggregation
/ccbell:aggregate disable           # Disable aggregation
/ccbell:aggregate window 60         # 60 second window
/ccbell:aggregate max 5             # Max 5 per group
/ccbell:aggregate rule stop 3 60    # Stop: aggregate 3 in 60s
/ccbell:aggregate status            # Show aggregation status
/ccbell:aggregate history           # Show aggregation history
/ccbell:aggregate flush             # Flush pending events
```

### Output

```
$ ccbell:aggregate status

=== Sound Event Aggregation ===

Status: Enabled
Window: 60s
Max per group: 5

Rules:
  stop: aggregate after 3, window 60s
  permission_prompt: aggregate after 2, window 30s

Pending Events: 2
  [stop] bundled:stop x2 (45s waiting)

Aggregated This Hour: 12
  Stop: 8 groups (24 events -> 8 notifications)
  Permission: 4 groups (8 events -> 4 notifications)

[Configure] [History] [Flush] [Disable]
```

---

## Audio Player Compatibility

Aggregation works with existing audio player:
- Reduces `player.Play()` calls
- Same format support
- No player changes required

---

## Implementation

### Event Buffering

```go
type Aggregator struct {
    config  *AggregationConfig
    pending map[string][]*BufferedEvent
    mutex   sync.Mutex
}

func (a *Aggregator) HandleEvent(event *BufferedEvent) {
    a.mutex.Lock()
    defer a.mutex.Unlock()

    rule := a.getRule(event.EventType)
    if rule == nil {
        // No aggregation rule, play immediately
        a.playEvent(event)
        return
    }

    // Add to pending
    a.pending[event.EventType] = append(a.pending[event.EventType], event)

    // Check if we should aggregate
    pending := a.pending[event.EventType]
    if len(pending) >= rule.MaxCount {
        a.aggregateAndPlay(event.EventType)
    }
}

func (a *Aggregator) aggregateAndPlay(eventType string) {
    pending := a.pending[eventType]
    if len(pending) == 0 {
        return
    }

    // Create aggregated event
    aggregated := &AggregatedEvent{
        ID:          generateID(),
        OriginalIDs: make([]string, len(pending)),
        EventType:   eventType,
        Count:       len(pending),
        FirstTime:   pending[0].Timestamp,
        LastTime:    pending[len(pending)-1].Timestamp,
        SoundID:     pending[0].SoundID,
        Volume:      pending[0].Volume,
    }

    for i, e := range pending {
        aggregated.OriginalIDs[i] = e.ID
    }

    // Clear pending
    a.pending[eventType] = nil

    // Play aggregated event
    a.playAggregated(aggregated)
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Aggregated playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
