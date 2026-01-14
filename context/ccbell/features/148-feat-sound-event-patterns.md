# Feature: Sound Event Patterns

Detect patterns in event sequences.

## Summary

Analyze and detect recurring patterns in events.

## Motivation

- Identify behavior patterns
- Predict events
- Optimize configurations

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Pattern Types

| Type | Description | Example |
|------|-------------|---------|
| Sequential | Event sequences | A -> B -> C |
| Temporal | Time-based patterns | Every 30min |
| Frequency | Frequency patterns | 5x/hour |
| Correlation | Related events | A before B |

### Configuration

```go
type PatternConfig struct {
    Enabled       bool     `json:"enabled"`
    MinOccurrences int     `json:"min_occurrences"` // 3
    WindowMinutes int      `json:"window_minutes"` // detection window
    PatternTypes  []string `json:"pattern_types"` // "sequential", "temporal", "frequency"
}

type DetectedPattern struct {
    ID          string    `json:"id"`
    Type        string    `json:"type"`
    Sequence    []string  `json:"sequence"`
    Occurrences int       `json:"occurrences"`
    Confidence  float64   `json:"confidence"` // 0-1
    FirstSeen   time.Time `json:"first_seen"`
    LastSeen    time.Time `json:"last_seen"`
    Interval    time.Duration `json:"interval,omitempty"`
}
```

### Commands

```bash
/ccbell:pattern detect              # Detect patterns
/ccbell:pattern list                # List detected patterns
/ccbell:pattern show <id>           # Show pattern details
/ccbell:pattern delete <id>         # Remove pattern
/ccbell:pattern export              # Export patterns
/ccbell:pattern clear               # Clear pattern cache
/ccbell:pattern status              # Show pattern status
/ccbell:pattern config              # Configure detection
```

### Output

```
$ ccbell:pattern detect

=== Sound Event Pattern Detection ===

Detected Patterns: 5

[1] Sequential Pattern
    Events: stop -> subagent -> permission_prompt
    Occurrences: 12
    Confidence: 95%
    Last seen: 2 hours ago
    [Details] [Export] [Delete]

[2] Temporal Pattern
    Interval: ~30 minutes
    Events: idle_prompt
    Occurrences: 48 (24h)
    Confidence: 88%
    [Details] [Export] [Delete]

[3] Frequency Pattern
    Events: stop
    Rate: 5-7 per hour
    Confidence: 82%
    [Details] [Export] [Delete]

[Configure] [Re-detect]
```

---

## Audio Player Compatibility

Pattern detection doesn't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Pattern Detection

```go
type PatternDetector struct {
    config  *PatternConfig
    events  []HistoryEntry
}

func (d *PatternDetector) Detect() ([]*DetectedPattern, error) {
    patterns := []*DetectedPattern{}

    // Detect sequential patterns
    if includes(d.config.PatternTypes, "sequential") {
        sequential := d.detectSequentialPatterns()
        patterns = append(patterns, sequential...)
    }

    // Detect temporal patterns
    if includes(d.config.PatternTypes, "temporal") {
        temporal := d.detectTemporalPatterns()
        patterns = append(patterns, temporal...)
    }

    // Detect frequency patterns
    if includes(d.config.PatternTypes, "frequency") {
        frequency := d.detectFrequencyPatterns()
        patterns = append(patterns, frequency...)
    }

    return patterns, nil
}

func (d *PatternDetector) detectSequentialPatterns() []*DetectedPattern {
    patterns := []*DetectedPattern{}

    // Find common sequences
    sequenceMap := make(map[string]int)

    for i := 0; i < len(d.events)-2; i++ {
        seq := fmt.Sprintf("%s -> %s -> %s",
            d.events[i].EventType,
            d.events[i+1].EventType,
            d.events[i+2].EventType)
        sequenceMap[seq]++
    }

    for seq, count := range sequenceMap {
        if count >= d.config.MinOccurrences {
            parts := strings.Split(seq, " -> ")
            patterns = append(patterns, &DetectedPattern{
                ID:         generateID(),
                Type:       "sequential",
                Sequence:   parts,
                Occurrences: count,
                Confidence: float64(count) / float64(len(d.events)),
            })
        }
    }

    return patterns
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

- [History feature](features/147-feat-sound-event-history.md) - Pattern data source
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event storage

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
