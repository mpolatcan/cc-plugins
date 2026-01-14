# Feature: Sound Event Forecasting

Forecast sound event patterns.

## Summary

Predict future sound event patterns based on historical data.

## Motivation

- Predict notification load
- Proactive optimization
- Capacity planning

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Forecast Types

| Type | Description | Horizon |
|------|-------------|---------|
| Hourly | Events per hour | Next 24h |
| Daily | Events per day | Next 7 days |
| Weekly | Events per week | Next 4 weeks |
| Peak | Peak event times | Today |

### Implementation

```go
type ForecastConfig struct {
    Enabled     bool    `json:"enabled"`
    Horizon     string  `json:"horizon"`    // 24h, 7d, 4w
    Confidence  float64 `json:"confidence"` // confidence threshold
    HistoricalDays int  `json:"historical_days"` // data to use
}

type Forecast struct {
    GeneratedAt   time.Time     `json:"generated_at"`
    Period        string        `json:"period"`
    Predictions   []Prediction  `json:"predictions"`
    Confidence    float64       `json:"confidence"`
    ModelAccuracy float64       `json:"model_accuracy"`
}

type Prediction struct {
    Time        time.Time `json:"time"`
    EventType   string    `json:"event_type"`
    Expected    float64   `json:"expected"`
    LowerBound  float64   `json:"lower_bound"`
    UpperBound  float64   `json:"upper_bound"`
    PeakProb    float64   `json:"peak_probability"`
}
```

### Commands

```bash
/ccbell:forecast                # Generate forecast
/ccbell:forecast hourly         # Hourly forecast
/ccbell:forecast daily          # Daily forecast
/ccbell:forecast weekly         # Weekly forecast
/ccbell:forecast today          # Today's predictions
/ccbell:forecast --json         # JSON output
/ccbell:forecast accuracy       # Show model accuracy
/ccbell:forecast visualize      # Show chart
```

### Output

```
$ ccbell:forecast hourly

=== Sound Event Forecast ===

Generated: Jan 15, 2024 10:30 AM
Period: Next 24 hours
Confidence: 78%
Model Accuracy: 82%

Hourly Predictions:

11:00 ████████████░░░░ 45 (peak)
12:00 ██████████░░░░░░ 38
13:00 ████████░░░░░░░░ 28
14:00 █████████░░░░░░░ 35
15:00 █████████████░░░ 52 (peak)
16:00 ████████████░░░░ 45
17:00 ██████████░░░░░░ 38
18:00 █████░░░░░░░░░░░ 18 (quiet)

By Event:
  stop:        ~350 events (avg 14.6/hr)
  permission:  ~120 events (avg 5/hr)
  subagent:    ~200 events (avg 8.3/hr)

Peak Times: 11:00, 15:00
Quiet Times: 18:00-07:00

[Visualize] [Daily] [Weekly]
```

---

## Audio Player Compatibility

Forecasting doesn't play sounds:
- Analysis feature
- No player changes required

---

## Implementation

### Time Series Analysis

```go
func (f *Forecaster) generateForecast() (*Forecast, error) {
    historical := f.getHistoricalData(f.config.HistoricalDays)

    // Build time series
    hourlyCounts := f.aggregateHourly(historical)

    // Simple moving average prediction
    predictions := []Prediction{}

    for hour := 0; hour < 24; hour++ {
        // Get historical average for this hour
        avg := f.getHourlyAverage(historical, hour)

        // Calculate confidence interval
        stdDev := f.getHourlyStdDev(historical, hour)
        margin := 1.96 * stdDev // 95% confidence

        predictions = append(predictions, Prediction{
            Time:       f.getPredictionTime(hour),
            Expected:   avg,
            LowerBound: math.Max(0, avg-margin),
            UpperBound: avg + margin,
        })
    }

    // Calculate model accuracy
    accuracy := f.calculateAccuracy(historical)

    return &Forecast{
        GeneratedAt: time.Now(),
        Predictions: predictions,
        Confidence:  f.calculateConfidence(historical),
        ModelAccuracy: accuracy,
    }, nil
}
```

### Pattern Detection

```go
func (f *Forecaster) detectPatterns(historical []AnalyticsEntry) []Pattern {
    patterns := []Pattern{}

    // Detect daily patterns
    dailyAvg := f.getDailyAverage(historical)
    peakDay := f.findPeakDay(dailyAvg)
    quietDay := f.findQuietDay(dailyAvg)

    patterns = append(patterns, Pattern{
        Type:        "daily",
        Description: fmt.Sprintf("Peak on %s, quietest on %s", peakDay, quietDay),
        PeakDay:     peakDay,
        QuietDay:    quietDay,
    })

    // Detect hourly patterns
    hourlyAvg := f.getHourlyAverage(historical)
    peakHour := f.findPeakHour(hourlyAvg)
    quietHour := f.findQuietHour(hourlyAvg)

    patterns = append(patterns, Pattern{
        Type:        "hourly",
        Description: fmt.Sprintf("Peak at %d:00, quietest at %d:00", peakHour, quietHour),
        PeakHour:    peakHour,
        QuietHour:   quietHour,
    })

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

- [Analytics integration](features/78-feat-sound-usage-analytics.md) - Historical data
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Event tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
