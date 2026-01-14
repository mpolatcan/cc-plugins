# Feature: Sound Event Statistics

Display event statistics and analytics.

## Summary

Track and display statistics about sound event playback.

## Motivation

- Usage analytics
- Pattern detection
- Performance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Statistics Types

| Statistic | Description | Example |
|-----------|-------------|---------|
| Count | Total events | 1,234 plays |
| By Type | Per-event stats | stop: 500 |
| Volume | Average volume | 0.65 |
| Time | Distribution | 9am-5pm peak |
| Duration | Total play time | 2 hours |

### Configuration

```go
type StatisticsConfig struct {
    Enabled       bool              `json:"enabled"`
    Retention     int               `json:"retention_days"` // 30 default
    TrackVolume   bool              `json:"track_volume"`
    TrackTiming   bool              `json:"track_timing"`
    ExportFormat  string            `json:"export_format"` // "json", "csv"
}

type Statistics struct {
    TotalPlays    int                  `json:"total_plays"`
    ByEvent       map[string]int       `json:"by_event"`
    ByDay         map[string]int       `json:"by_day"`
    ByHour        map[int]int          `json:"by_hour"`
    AverageVolume float64              `json:"average_volume"`
    TotalDuration time.Duration        `json:"total_duration"`
    TopVolumes    []VolumeStat         `json:"top_volumes"`
}

type VolumeStat struct {
    EventType   string
    Volume      float64
    Timestamp   time.Time
}
```

### Commands

```bash
/ccbell:stats show                  # Show statistics
/ccbell:stats show stop             # Show per-event stats
/ccbell:stats show today            # Today's stats
/ccbell:stats show week             # Weekly stats
/ccbell:stats show month            # Monthly stats
/ccbell:stats export                # Export to JSON
/ccbell:stats export csv            # Export to CSV
/ccbell:stats clear                 # Clear statistics
/ccbell:stats retention 30          # Set retention days
```

### Output

```
$ ccbell:stats show

=== Sound Event Statistics ===

Period: All time
Total Plays: 1,234

By Event:
  stop: 500 (40.5%)
  permission_prompt: 400 (32.4%)
  idle_prompt: 234 (19.0%)
  subagent: 100 (8.1%)

Volume:
  Average: 0.65
  Max: 1.0
  Min: 0.3

Time Distribution:
  Peak: 9am-11am (35%)
  Quiet: 2am-5am (2%)

Retention: 30 days
[Export] [Clear] [Configure]
```

---

## Audio Player Compatibility

Statistics don't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Statistics Manager

```go
type StatisticsManager struct {
    config   *StatisticsConfig
    stats    *Statistics
    mutex    sync.Mutex
}

func (m *StatisticsManager) Record(eventType string, volume float64) {
    m.mutex.Lock()
    defer m.mutex.Unlock()

    m.stats.TotalPlays++
    m.stats.ByEvent[eventType]++

    now := time.Now()
    day := now.Weekday().String()
    m.stats.ByDay[day]++
    m.stats.ByHour[now.Hour()]++

    if m.config.TrackVolume {
        m.updateAverageVolume(volume)
    }
}

func (m *StatisticsManager) GetStatistics(period string) *Statistics {
    m.mutex.Lock()
    defer m.mutex.Unlock()

    stats := &Statistics{
        TotalPlays: m.stats.TotalPlays,
        ByEvent:    make(map[string]int),
        ByDay:      make(map[string]int),
        ByHour:     make(map[int]int),
    }

    // Filter by period if needed
    cutoff := m.getCutoff(period)
    if cutoff.IsZero() {
        // Return all
        for k, v := range m.stats.ByEvent {
            stats.ByEvent[k] = v
        }
        for k, v := range m.stats.ByDay {
            stats.ByDay[k] = v
        }
        for k, v := range m.stats.ByHour {
            stats.ByHour[k] = v
        }
        stats.AverageVolume = m.stats.AverageVolume
    } else {
        // Filter by time
        // Implementation for time-based filtering
    }

    return stats
}

func (m *StatisticsManager) Export(format string) ([]byte, error) {
    stats := m.GetStatistics("all")

    switch format {
    case "json":
        return json.MarshalIndent(stats, "", "  ")
    case "csv":
        return m.exportCSV(stats)
    default:
        return nil, fmt.Errorf("unknown format: %s", format)
    }
}

func (m *StatisticsManager) exportCSV(stats *Statistics) ([]byte, error) {
    var b bytes.Buffer
    b.WriteString("event,count,percentage\n")

    total := float64(stats.TotalPlays)
    for event, count := range stats.ByEvent {
        pct := float64(count) / total * 100
        fmt.Fprintf(&b, "%s,%d,%.1f\n", event, count, pct)
    }

    return b.Bytes(), nil
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

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Playback tracking
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
