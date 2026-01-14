# Feature: Sound Event Humidity

Play sounds based on humidity levels.

## Summary

Play different sounds based on ambient humidity levels from sensors.

## Motivation

- Environment awareness
- Weather integration
- Comfort notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Humidity Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| High | High humidity | > 80% |
| Low | Low humidity | < 30% |
| Optimal | In optimal range | 40-60% |
| Change | Rapid change | > 10%/hour |

### Configuration

```go
type HumidityConfig struct {
    Enabled       bool              `json:"enabled"`
    Source        string            `json:"source"` // "sensor", "weather"
    CheckInterval int              `json:"check_interval_minutes"` // 15 default
    Thresholds    *HumidityThresholds `json:"thresholds"`
    Sounds        map[string]string `json:"sounds"`
}

type HumidityThresholds struct {
    High        float64 `json:"high_percent"` // 0-100
    Low         float64 `json:"low_percent"` // 0-100
    OptimalMin  float64 `json:"optimal_min"`
    OptimalMax  float64 `json:"optimal_max"`
    ChangeRate  float64 `json:"change_rate_percent_per_hour"`
}

type HumidityState struct {
    Humidity     float64 // 0-100
    Temperature  float64 // Associated temperature
    Source       string
    LastUpdate   time.Time
}
```

### Commands

```bash
/ccbell:humidity status              # Show current humidity
/ccbell:humidity sound high <sound>
/ccbell:humidity sound low <sound>
/ccbell:humidity sound optimal <sound>
/ccbell:humidity threshold high 80   # Set high threshold
/ccbell:humidity threshold low 30    # Set low threshold
/ccbell:humidity enable              # Enable humidity monitoring
/ccbell:humidity disable             # Disable humidity monitoring
/ccbell:humidity test                # Test humidity sounds
```

### Output

```
$ ccbell:humidity status

=== Sound Event Humidity ===

Status: Enabled
Source: Local Weather (wttr.in)
Check Interval: 15min

Current Humidity:
  Humidity: 65%
  Temperature: 22°C
  Status: OPTIMAL

Thresholds:
  High: 80%
  Low: 30%
  Optimal: 40-60%

Sounds:
  High: bundled:stop
  Low: bundled:stop
  Optimal: bundled:stop
  Change: bundled:stop

Status: OPTIMAL
[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Humidity monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Humidity Monitor

```go
type HumidityMonitor struct {
    config   *HumidityConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState *HumidityState
    lastStatus string
}

func (m *HumidityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *HumidityMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkHumidity()
        case <-m.stopCh:
            return
        }
    }
}

func (m *HumidityMonitor) checkHumidity() {
    state, err := m.getHumidity()
    if err != nil {
        log.Debug("Failed to get humidity: %v", err)
        return
    }

    status := m.calculateStatus(state)
    if status != m.lastStatus {
        m.playHumidityEvent(status)
    }

    // Check for rapid change
    if m.lastState != nil && m.config.Thresholds.ChangeRate > 0 {
        changeRate := math.Abs(state.Humidity-m.lastState.Humidity) /
            time.Since(m.lastState.LastUpdate).Hours()
        if changeRate >= m.config.Thresholds.ChangeRate {
            m.playHumidityEvent("change")
        }
    }

    m.lastState = state
    m.lastStatus = status
}

func (m *HumidityMonitor) getHumidity() (*HumidityState, error) {
    // Try local sensor first (DHT22, etc.)
    if m.config.Source == "sensor" {
        return m.readSensor()
    }

    // Use weather service as fallback
    return m.getWeatherHumidity()
}

func (m *HumidityMonitor) readSensor() (*HumidityState, error) {
    // Raspberry Pi DHT11/DHT22 sensor
    // Read from /sys/bus/i2c/devices/*/hwmon/*/humidity*

    paths := []string{
        "/sys/bus/i2c/devices/1-0076/humidity1_input",
        "/sys/devices/virtual/dht/dht/0/humidity",
    }

    for _, path := range paths {
        if data, err := os.ReadFile(path); err == nil {
            humidity, _ := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
            return &HumidityState{
                Humidity:   humidity / 1000, // Convert to percentage
                Source:     "sensor",
                LastUpdate: time.Now(),
            }, nil
        }
    }

    return m.getWeatherHumidity()
}

func (m *HumidityMonitor) getWeatherHumidity() (*HumidityState, error) {
    // Use wttr.in for humidity
    url := "https://wttr.in/?format=j1"
    resp, err := http.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    var result WeatherAPIResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }

    humidity, _ := strconv.ParseFloat(result.CurrentCondition[0].Humidity, 64)
    tempC, _ := strconv.ParseFloat(result.CurrentCondition[0].TempC, 64)

    return &HumidityState{
        Humidity:    humidity,
        Temperature: tempC,
        Source:      "weather",
        LastUpdate:  time.Now(),
    }, nil
}

func (m *HumidityMonitor) calculateStatus(state *HumidityState) string {
    if state.Humidity >= m.config.Thresholds.High {
        return "high"
    }
    if state.Humidity <= m.config.Thresholds.Low {
        return "low"
    }
    if state.Humidity >= m.config.Thresholds.OptimalMin &&
       state.Humidity <= m.config.Thresholds.OptimalMax {
        return "optimal"
    }
    return "moderate"
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| wttr.in | Web Service | Free | Weather data |
| sysfs | Filesystem | Free | Local sensor access |
| http | Go Stdlib | Free | HTTP client |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | HTTP-based weather |
| Linux | ✅ Supported | HTTP-based weather + sensors |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
