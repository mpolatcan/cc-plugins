# Feature: Sound Event Metrics

Collect and report event metrics.

## Summary

Collect detailed metrics about event processing and playback.

## Motivation

- Performance monitoring
- Usage analytics
- Capacity planning

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Metrics Types

| Metric | Description | Unit |
|--------|-------------|------|
| Events Processed | Total events | count |
| Playback Success | Successful plays | count |
| Playback Failures | Failed plays | count |
| Average Latency | Avg playback time | ms |
| Events by Type | Per-event counts | count |
| Time Distribution | Events by hour | histogram |

### Configuration

```go
type MetricsConfig struct {
    Enabled       bool     `json:"enabled"`
    IntervalSec   int      `json:"interval_sec"` // collection interval
    RetentionDays int      `json:"retention_days"`
    IncludeEvents bool     `json:"include_events"` // include event data
    IncludeTiming bool     `json:"include_timing"` // include timing
    Storage       string   `json:"storage"` // "memory", "file"
}

type Metrics struct {
    Timestamp       time.Time `json:"timestamp"`
    TotalEvents     int       `json:"total_events"`
    SuccessfulPlays int       `json:"successful_plays"`
    FailedPlays     int       `json:"failed_plays"`
    AvgLatencyMs    float64   `json:"avg_latency_ms"`
    ByEvent         map[string]int `json:"by_event"`
    ByHour          map[int]int `json:"by_hour"` // 0-23
    ByDay           map[int]int `json:"by_day"` // 0-6
}
```

### Commands

```bash
/ccbell:metrics                   # Show current metrics
/ccbell:metrics --json            # JSON output
/ccbell:metrics today             # Today's metrics
/ccbell:metrics hourly            # Hourly breakdown
/ccbell:metrics by-event          # By event type
/ccbell:metrics reset             # Reset metrics
/ccbell:metrics export            # Export metrics
/ccbell:metrics config            # Configure metrics
```

### Output

```
$ ccbell:metrics

=== Sound Event Metrics ===

Period: Last 24 hours

Summary:
  Total Events: 1,234
  Successful: 1,230 (99.7%)
  Failed: 4 (0.3%)
  Avg Latency: 45ms

By Event:
  stop:              456 (37%)
  subagent:          346 (28%)
  permission_prompt: 234 (19%)
  idle_prompt:       198 (16%)

By Hour:
  00-06: ████░░░░░░░░░░░ 89
  06-12: ████████████████ 456
  12-18: ████████████░░░░ 423
  18-24: ████████░░░░░░░░ 266

[Export] [Reset] [Configure]
```

---

## Audio Player Compatibility

Metrics don't play sounds:
- Collection feature
- No player changes required

---

## Implementation

### Metrics Collection

```go
type MetricsCollector struct {
    config  *MetricsConfig
    current *Metrics
    mutex   sync.Mutex
}

func (c *MetricsCollector) Record(eventType string, success bool, latencyMs int64) {
    c.mutex.Lock()
    defer c.mutex.Unlock()

    c.current.TotalEvents++
    c.current.ByEvent[eventType]++

    now := time.Now()
    c.current.ByHour[now.Hour()]++
    c.current.ByDay[int(now.Weekday())]++

    if success {
        c.current.SuccessfulPlays++
    } else {
        c.current.FailedPlays++
    }

    // Update average latency
    totalLatency := int64(c.current.AvgLatencyMs*float64(c.current.SuccessfulPlays-1)) + latencyMs
    c.current.AvgLatencyMs = float64(totalLatency) / float64(c.current.SuccessfulPlays)
}

func (c *MetricsCollector) GetMetrics() *Metrics {
    c.mutex.Lock()
    defer c.mutex.Unlock()

    // Return a copy
    copy := *c.current
    return &copy
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Metrics storage
- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Latency tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
