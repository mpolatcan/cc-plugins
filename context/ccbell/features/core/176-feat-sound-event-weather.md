# Feature: Sound Event Weather

Play sounds based on weather conditions.

## Summary

Play different sounds based on weather conditions from local or online weather sources.

## Motivation

- Weather awareness
- Environment-based notifications
- Seasonal sound patterns

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Weather Triggers

| Trigger | Description | Example |
|---------|-------------|---------|
| Temperature | Temperature thresholds | Above 30°C, below 0°C |
| Condition | Weather conditions | Rain, snow, sunny |
| Humidity | Humidity level | Above 80% |
| Wind | Wind speed | Above 30 km/h |
| Alert | Weather warnings | Storm, flood |

### Configuration

```go
type WeatherConfig struct {
    Enabled     bool              `json:"enabled"`
    Location    string            `json:"location"` // City or coordinates
    Source      string            `json:"source"` // "local", "openweathermap"
    APIKey      string            `json:"api_key,omitempty"`
    CheckInterval int            `json:"check_interval_minutes"` // 15 default
    Sounds      map[string]string `json:"sounds"` // trigger -> sound
    Triggers    []*WeatherTrigger `json:"triggers"`
}

type WeatherTrigger struct {
    ID          string  `json:"id"`
    Type        string  `json:"type"` // "temp_above", "temp_below", "condition", "humidity", "wind", "alert"
    Threshold   float64 `json:"threshold,omitempty"`
    Condition   string  `json:"condition,omitempty"` // "rain", "snow", "sunny"
    Sound       string  `json:"sound"`
    Volume      float64 `json:"volume,omitempty"`
    Enabled     bool    `json:"enabled"`
}
```

### Commands

```bash
/ccbell:weather status               # Show current weather
/ccbell:weather set location "San Francisco"
/ccbell:weather sound rain <sound>
/ccbell:weather sound snow <sound>
/ccbell:weather sound sunny <sound>
/ccbell:weather trigger temp_above 30 <sound>
/ccbell:weather trigger temp_below 0 <sound>
/ccbell:weather enable               # Enable weather monitoring
/ccbell:weather disable              # Disable weather monitoring
/ccbell:weather test                 # Test all weather sounds
```

### Output

```
$ ccbell:weather status

=== Sound Event Weather ===

Status: Enabled
Location: San Francisco
Source: Local (wttr.in)
Check Interval: 15min

Current Weather:
  Temperature: 18°C (64°F)
  Condition: Partly Cloudy
  Humidity: 65%
  Wind: 12 km/h

Active Triggers:
  [1] Rain Alert
      Condition: rain
      Sound: bundled:stop
      Status: Inactive

  [2] Cold Warning
      Temp Below: 0°C
      Sound: bundled:stop
      Status: Inactive

  [3] Heat Alert
      Temp Above: 35°C
      Sound: bundled:stop
      Status: Inactive

[Configure] [Test All] [Disable]
```

---

## Audio Player Compatibility

Weather monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Weather Monitoring

```go
type WeatherManager struct {
    config   *WeatherConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastState *WeatherState
}

type WeatherState struct {
    Temperature float64
    Condition   string
    Humidity    float64
    WindSpeed   float64
    Alert       string
}

func (m *WeatherManager) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *WeatherManager) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Minute)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkWeather()
        case <-m.stopCh:
            return
        }
    }
}

func (m *WeatherManager) checkWeather() {
    state, err := m.getWeather()
    if err != nil {
        log.Debug("Failed to get weather: %v", err)
        return
    }

    for _, trigger := range m.config.Triggers {
        if !trigger.Enabled {
            continue
        }

        if m.checkTrigger(trigger, state) {
            m.playWeatherEvent(trigger, state)
        }
    }

    m.lastState = state
}

func (m *WeatherManager) getWeather() (*WeatherState, error) {
    // Use local weather service (wttr.in)
    url := fmt.Sprintf("https://wttr.in/%s?format=j1", m.config.Location)
    resp, err := http.Get(url)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    // Parse JSON response
    var result WeatherAPIResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }

    return &WeatherState{
        Temperature: parseTemp(result.CurrentCondition[0].TempC),
        Condition:   result.CurrentCondition[0].WeatherDesc[0].Value,
        Humidity:    parseHumidity(result.CurrentCondition[0].Humidity),
        WindSpeed:   parseWind(result.CurrentCondition[0].WindspeedKmph),
    }, nil
}

func (m *WeatherManager) checkTrigger(trigger *WeatherTrigger, state *WeatherState) bool {
    switch trigger.Type {
    case "temp_above":
        return state.Temperature > trigger.Threshold
    case "temp_below":
        return state.Temperature < trigger.Threshold
    case "condition":
        return strings.Contains(strings.ToLower(state.Condition), strings.ToLower(trigger.Condition))
    case "humidity":
        return state.Humidity > trigger.Threshold
    case "wind":
        return state.WindSpeed > trigger.Threshold
    case "alert":
        return state.Alert != "" && trigger.Condition == state.Alert
    }
    return false
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| wttr.in | Web Service | Free | No API key required |
| http | Go Stdlib | Free | HTTP client |
| json | Go Stdlib | Free | JSON parsing |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | HTTP-based weather |
| Linux | ✅ Supported | HTTP-based weather |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
