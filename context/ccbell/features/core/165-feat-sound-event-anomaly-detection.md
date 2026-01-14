# Feature: Sound Event Anomaly Detection

Detect anomalies in event patterns.

## Summary

Detect unusual event patterns or behaviors.

## Motivation

- Detect issues early
- Security monitoring
- Performance anomalies

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Anomaly Types

| Type | Description | Example |
|------|-------------|---------|
| Rate Spike | Sudden increase | 10x normal rate |
| Volume Spike | Unusual volume | Volume > 0.9 |
| Pattern Break | Unusual sequence | Wrong event order |
| Silence | Unexpected silence | No events for 1 hour |

### Configuration

```go
type AnomalyConfig struct {
    Enabled       bool              `json:"enabled"`
    Detectors     map[string]*Detector `json:"detectors"`
    Sensitivity   float64           `json:"sensitivity"` // 0-1, higher = more sensitive
    BaselineWindow int              `json:"baseline_window_days"` // days for baseline
    AlertOnDetect bool              `json:"alert_on_detect"`
}

type Detector struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Type        string   `json:"type"` // "rate", "volume", "pattern", "silence"
    Threshold   float64  `json:"threshold"` // anomaly threshold
    WindowMin   int      `json:"window_minutes"` // detection window
    BaselineMultiplier float64 `json:"baseline_multiplier"` // vs baseline
    Enabled     bool     `json:"enabled"`
}

type DetectedAnomaly struct {
    ID          string    `json:"id"`
    DetectorID  string    `json:"detector_id"`
    Type        string    `json:"type"`
    DetectedAt  time.Time `json:"detected_at"`
    Severity    string    `json:"severity"` // "low", "medium", "high"
    Value       float64   `json:"value"`
    Baseline    float64   `json:"baseline"`
    Description string    `json:"description"`
}
```

### Commands

```bash
/ccbell:anomaly list                # List detectors
/ccbell:anomaly create "Rate Spike" --type rate --threshold 5
/ccbell:anomaly create "Volume Spike" --type volume --threshold 0.9
/ccbell:anomaly create "Silence" --type silence --window 60
/ccbell:anomaly sensitivity 0.8      # Set sensitivity
/ccbell:anomaly status              # Show anomaly status
/ccbell:anomaly history             # Show detection history
/ccbell:anomaly clear               # Clear anomaly history
/ccbell:anomaly test                # Test anomaly detection
```

### Output

```
$ ccbell:anomaly status

=== Sound Event Anomaly Detection ===

Status: Enabled
Sensitivity: 0.7
Baseline: 7 days

Detectors: 4

[1] Rate Spike
    Type: rate
    Threshold: 5x baseline
    Status: Active
    Detections: 2
    [Configure] [Disable] [Delete]

[2] Volume Spike
    Type: volume
    Threshold: 0.9
    Status: Active
    Detections: 0
    [Configure] [Disable] [Delete]

[3] Pattern Break
    Type: pattern
    Threshold: 0.3
    Status: Active
    Detections: 1
    [Configure] [Disable] [Delete]

[4] Silence
    Type: silence
    Window: 60min
    Status: Active
    Detections: 5
    [Configure] [Disable] [Delete]

Recent Anomalies:
  [1] Rate Spike - Jan 15, 10:30 AM (MEDIUM)
      Events: 450/min (baseline: 45/min, 10x)
      [Details] [Ignore]

[Configure] [History] [Clear]
```

---

## Audio Player Compatibility

Anomaly detection doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Anomaly Detection

```go
type AnomalyDetector struct {
    config   *AnomalyConfig
    history  []HistoryEntry
    baseline map[string]float64
}

func (d *AnomalyDetector) Detect() []*DetectedAnomaly {
    anomalies := []*DetectedAnomaly{}

    for _, detector := range d.config.Detectors {
        if !detector.Enabled {
            continue
        }

        switch detector.Type {
        case "rate":
            if anomaly := d.detectRateAnomaly(detector); anomaly != nil {
                anomalies = append(anomalies, anomaly)
            }
        case "volume":
            if anomaly := d.detectVolumeAnomaly(detector); anomaly != nil {
                anomalies = append(anomalies, anomaly)
            }
        case "silence":
            if anomaly := d.detectSilenceAnomaly(detector); anomaly != nil {
                anomalies = append(anomalies, anomaly)
            }
        case "pattern":
            if anomaly := d.detectPatternAnomaly(detector); anomaly != nil {
                anomalies = append(anomalies, anomaly)
            }
        }
    }

    return anomalies
}

func (d *AnomalyDetector) detectRateAnomaly(detector *Detector) *DetectedAnomaly {
    // Get current rate
    currentRate := d.getCurrentRate(detector.WindowMin)

    // Get baseline rate
    baselineKey := fmt.Sprintf("rate:%dmin", detector.WindowMin)
    baseline := d.baseline[baselineKey]

    if baseline == 0 {
        baseline = d.calculateBaseline(baselineKey)
    }

    ratio := currentRate / baseline

    if ratio >= detector.Threshold {
        return &DetectedAnomaly{
            ID:         generateID(),
            DetectorID: detector.ID,
            Type:       "rate",
            DetectedAt: time.Now(),
            Severity:   d.calculateSeverity(ratio, detector.Threshold),
            Value:      currentRate,
            Baseline:   baseline,
            Description: fmt.Sprintf("Rate %.0f/min is %.1fx baseline (%.0f/min)",
                currentRate, ratio, baseline),
        }
    }

    return nil
}

func (d *AnomalyDetector) calculateSeverity(ratio, threshold float64) string {
    if ratio >= threshold*2 {
        return "high"
    } else if ratio >= threshold*1.5 {
        return "medium"
    }
    return "low"
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

- [History feature](features/147-feat-sound-event-history.md) - Anomaly data source
- [Patterns feature](features/148-feat-sound-event-patterns.md) - Pattern baseline

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
