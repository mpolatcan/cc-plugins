# Feature: Sound Event Prediction

Predict when events will occur.

## Summary

Predict future events based on historical patterns.

## Motivation

- Proactive preparation
- Resource planning
- Anticipate needs

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Prediction Types

| Type | Description | Output |
|------|-------------|--------|
| Next Event | When next event | "in 5 minutes" |
| Peak Hours | Busiest times | 10AM-12PM |
| Daily Total | Expected daily count | ~100 events |
| Event Mix | Expected distribution | 40% stop |

### Configuration

```go
type PredictionConfig struct {
    Enabled       bool    `json:"enabled"`
    Horizon       string  `json:"horizon"` // "1h", "24h", "7d"
    ConfidenceThreshold float64 `json:"confidence_threshold"` // 0.7
    UsePatterns   bool    `json:"use_patterns"` // use detected patterns
    UpdateInterval int    `json:"update_interval_minutes"` // 60
}

type Prediction struct {
    GeneratedAt   time.Time `json:"generated_at"`
    EventType     string    `json:"event_type,omitempty"`
    PredictionType string   `json:"prediction_type"` // "next", "peak", "total", "mix"
    Value         string    `json:"value"`
    Confidence    float64   `json:"confidence"`
    BasedOn       string    `json:"based_on"`
    NextUpdate    time.Time `json:"next_update,omitempty"`
}
```

### Commands

```bash
/ccbell:predict                     # Generate predictions
/ccbell:predict next                # Next event prediction
/ccbell:predict peak                # Peak hours prediction
/ccbell:predict daily               # Daily prediction
/ccbell:predict mix                 # Event mix prediction
/ccbell:predict --json              # JSON output
/ccbell:predict accuracy            # Show prediction accuracy
/ccbell:predict clear               # Clear predictions
/ccbell:predict config              # Configure predictions
```

### Output

```
$ ccbell:predict

=== Sound Event Predictions ===

Generated: Jan 15, 2024 10:30 AM
Confidence: 78%

Next Event:
  stop in ~3 minutes
  Confidence: 82%

Peak Hours Today:
  10:00-12:00 (45% of daily events)
  14:00-16:00 (30% of daily events)

Daily Forecast:
  Total: ~95 events (range: 80-110)
  stop: ~35 (37%)
  subagent: ~30 (32%)
  permission_prompt: ~20 (21%)
  idle_prompt: ~10 (10%)

[Detailed] [History] [Configure]
```

---

## Audio Player Compatibility

Prediction doesn't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Prediction Engine

```go
type Predictor struct {
    config   *PredictionConfig
    history  []HistoryEntry
}

func (p *Predictor) Predict() ([]*Prediction, error) {
    predictions := []*Prediction{}

    // Predict next event
    nextPred := p.predictNextEvent()
    predictions = append(predictions, nextPred)

    // Predict peak hours
    peakPred := p.predictPeakHours()
    predictions = append(predictions, peakPred...)

    // Predict daily total
    dailyPred := p.predictDailyTotal()
    predictions = append(predictions, dailyPred)

    // Predict event mix
    mixPred := p.predictEventMix()
    predictions = append(predictions, mixPred)

    return predictions, nil
}

func (p *Predictor) predictNextEvent() *Prediction {
    // Calculate average time between events
    intervals := p.calculateIntervals()

    if len(intervals) == 0 {
        return &Prediction{
            PredictionType: "next",
            Value:          "unknown",
            Confidence:     0,
        }
    }

    avgInterval := average(intervals)
    lastEvent := p.history[len(p.history)-1]

    nextTime := lastEvent.Timestamp.Add(avgInterval)

    return &Prediction{
        PredictionType: "next",
        EventType:      "any",
        Value:          fmt.Sprintf("in %v", time.Until(nextTime).Round(time.Minute)),
        Confidence:     p.calculateConfidence(intervals),
        BasedOn:        "historical intervals",
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

- [Pattern feature](features/148-feat-sound-event-patterns.md) - Pattern data
- [History feature](features/147-feat-sound-event-history.md) - Historical data

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
