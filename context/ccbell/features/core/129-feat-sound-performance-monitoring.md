# Feature: Sound Performance Monitoring

Monitor sound playback performance.

## Summary

Track and analyze sound playback performance metrics.

## Motivation

- Identify slow playback
- Optimize performance
- Debug latency issues

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Metrics

| Metric | Description | Unit |
|--------|-------------|------|
| Latency | Time to start playback | ms |
| Duration | Sound duration | ms |
| CPU | CPU usage | % |
| Memory | Memory usage | MB |
| Drops | Buffer drops | count |

### Implementation

```go
type PerformanceMetrics struct {
    Timestamp   time.Time       `json:"timestamp"`
    EventType   string          `json:"event_type"`
    SoundID     string          `json:"sound_id"`
    Latency     time.Duration   `json:"latency"`
    Duration    time.Duration   `json:"duration"`
    CPUPercent  float64         `json:"cpu_percent"`
    MemoryMB    float64         `json:"memory_mb"`
    Drops       int             `json:"drops"`
}

type PerformanceSummary struct {
    Period          string                    `json:"period"`
    TotalPlays      int                       `json:"total_plays"`
    AvgLatency      time.Duration             `json:"avg_latency"`
    MinLatency      time.Duration             `json:"min_latency"`
    MaxLatency      time.Duration             `json:"max_latency"`
    P95Latency      time.Duration             `json:"p95_latency"`
    SlowestPlays    []PerformanceMetrics      `json:"slowest_plays"`
    ByEvent         map[string]EventMetrics   `json:"by_event"`
}
```

### Commands

```bash
/ccbell:perf                     # Show current metrics
/ccbell:perf --history           # Show historical data
/ccbell:perf --event stop        # Filter by event
/ccbell:perf --last 1h           # Last hour
/ccbell:perf --json              # JSON output
/ccbell:perf report              # Generate report
/ccbell:perf reset               # Reset metrics
/ccbell:perf monitor             # Real-time monitoring
```

### Output

```
$ ccbell:perf

=== Sound Performance ===

Last 24 hours

Total Plays: 1,234
Avg Latency: 45ms
Min Latency: 12ms
Max Latency: 890ms
P95 Latency: 120ms

By Event:
  stop:              456 plays, avg 42ms
  permission_prompt: 234 plays, avg 38ms
  idle_prompt:       198 plays, avg 52ms
  subagent:          346 plays, avg 48ms

Slowest Plays:
  [1] stop, bundled:stop, 890ms, 2h ago
  [2] subagent, custom:alert, 450ms, 5h ago
  [3] stop, bundled:stop, 320ms, 1d ago

[Monitor] [Report] [Reset]
```

---

## Audio Player Compatibility

Performance monitoring uses existing audio player:
- Wraps `player.Play()` with timing
- Same format support
- No player changes required

---

## Implementation

### Metrics Collection

```go
func (p *PerformanceManager) recordPlayback(eventType, soundID string, startTime time.Time) {
    latency := time.Since(startTime)

    // Get sound duration
    duration := p.getSoundDuration(soundID)

    metrics := &PerformanceMetrics{
        Timestamp: time.Now(),
        EventType: eventType,
        SoundID:   soundID,
        Latency:   latency,
        Duration:  duration,
    }

    p.metrics = append(p.metrics, metrics)

    // Keep last N metrics
    if len(p.metrics) > p.config.MaxMetrics {
        p.metrics = p.metrics[len(p.metrics)-p.config.MaxMetrics:]
    }

    p.saveMetrics()
}
```

### Summary Calculation

```go
func (p *PerformanceManager) calculateSummary(period time.Duration) *PerformanceSummary {
    cutoff := time.Now().Add(-period)
    recent := p.getMetricsSince(cutoff)

    if len(recent) == 0 {
        return &PerformanceSummary{}
    }

    // Calculate averages
    var totalLatency time.Duration
    for _, m := range recent {
        totalLatency += m.Latency
    }

    latencies := make([]time.Duration, len(recent))
    for i, m := range recent {
        latencies[i] = m.Latency
    }
    sort.Slice(latencies, func(i, j int) bool {
        return latencies[i] < latencies[j]
    })

    return &PerformanceSummary{
        Period:      period.String(),
        TotalPlays:  len(recent),
        AvgLatency:  totalLatency / time.Duration(len(recent)),
        MinLatency:  latencies[0],
        MaxLatency:  latencies[len(latencies)-1],
        P95Latency:  latencies[int(float64(len(latencies))*0.95)],
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Timing wrapper
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Metrics persistence

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
