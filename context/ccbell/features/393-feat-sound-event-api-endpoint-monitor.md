# Feature: Sound Event API Endpoint Monitor

Play sounds for API endpoint failures, response time thresholds, and status code changes.

## Summary

Monitor API endpoints for availability, response times, and HTTP status codes, playing sounds for API events.

## Motivation

- API health alerts
- Performance monitoring
- Error detection
- Uptime tracking
- Service degradation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### API Endpoint Events

| Event | Description | Example |
|-------|-------------|---------|
| Endpoint Down | Connection failed | timeout |
| Slow Response | Response > threshold | > 500ms |
| Status Changed | HTTP status changed | 200 -> 500 |
| 5xx Error | Server error | 500, 503 |
| 4xx Error | Client error | 401, 404 |
| Certificate Expired | SSL cert issue | expired |

### Configuration

```go
type APIEndpointMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Endpoints         []APIEndpointConfig `json:"endpoints"`
    Timeout           int               `json:"timeout_ms"` // 5000 default
    SlowThreshold     int               `json:"slow_threshold_ms"` // 500 default
    ExpectedStatus    []int             `json:"expected_status"` // 200, 201
    SoundOnDown       bool              `json:"sound_on_down"`
    SoundOnSlow       bool              `json:"sound_on_slow"`
    SoundOnError      bool              `json:"sound_on_error"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type APIEndpointConfig struct {
    Name       string `json:"name"` // "API"
    URL        string `json:"url"` // "https://api.example.com/health"
    Method     string `json:"method"` // "GET"
    Headers    map[string]string `json:"headers"`
}
```

### Commands

```bash
/ccbell:api status                     # Show API status
/ccbell:api add "https://api.example.com/health"  # Add endpoint
/ccbell:api remove "https://api.example.com/health"
/ccbell:api timeout 5000               # Set timeout
/ccbell:api sound down <sound>
/ccbell:api sound slow <sound>
/ccbell:api test                       # Test API sounds
```

### Output

```
$ ccbell:api status

=== Sound Event API Endpoint Monitor ===

Status: Enabled
Timeout: 5000ms
Slow Threshold: 500ms

Monitored Endpoints: 4

Endpoint Status:

[1] API (https://api.example.com/health)
    Status: 200 OK
    Response Time: 45ms
    Last Check: 5 min ago
    Uptime: 99.9%
    Sound: bundled:api-main

[2] Auth (https://auth.example.com/ready)
    Status: 200 OK
    Response Time: 120ms
    Last Check: 5 min ago
    Uptime: 99.5%
    Sound: bundled:api-auth

[3] Database (https://db.example.com/health)
    Status: 503 Service Unavailable
    Response Time: 250ms
    Last Check: 5 min ago
    Uptime: 95.0%
    Sound: bundled:api-db *** DOWN ***

[4] Payments (https://payments.example.com/api/v1/health)
    Status: 200 OK
    Response Time: 350ms
    Last Check: 5 min ago
    Uptime: 99.8%
    Sound: bundled:api-payments

Recent Events:
  [1] Database: Endpoint Down (5 min ago)
       Status: 503 Service Unavailable
  [2] Payments: Slow Response (1 hour ago)
       850ms > 500ms threshold
  [3] Auth: Slow Response (2 hours ago)
       650ms > 500ms threshold

API Statistics:
  Total Checks: 5000
  Failed: 12
  Slow: 45
  Uptime: 99.7%

Sound Settings:
  Down: bundled:api-down
  Slow: bundled:api-slow
  Error: bundled:api-error

[Configure] [Add Endpoint] [Test All]
```

---

## Audio Player Compatibility

API monitoring doesn't play sounds directly:
- Monitoring feature using curl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### API Endpoint Monitor

```go
type APIEndpointMonitor struct {
    config          *APIEndpointMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    endpointState   map[string]*APIEndpointInfo
    lastEventTime   map[string]time.Time
}

type APIEndpointInfo struct {
    Name           string
    URL            string
    StatusCode     int
    ResponseTime   int64 // milliseconds
    LastCheck      time.Time
    ConsecutiveFails int
    IsDown         bool
}

func (m *APIEndpointMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.endpointState = make(map[string]*APIEndpointInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *APIEndpointMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkEndpoints()
        case <-m.stopCh:
            return
        }
    }
}

func (m *APIEndpointMonitor) checkEndpoints() {
    for _, endpoint := range m.config.Endpoints {
        m.checkEndpoint(&endpoint)
    }
}

func (m *APIEndpointMonitor) checkEndpoint(config *APIEndpointConfig) {
    startTime := time.Now()

    // Build curl command
    args := []string{
        "-s", "-w", "%{http_code}|%{time_total}",
        "-o", "/dev/null",
        "-m", strconv.Itoa(m.config.Timeout / 1000),
    }

    if config.Method != "GET" {
        args = append(args, "-X", config.Method)
    }

    for k, v := range config.Headers {
        args = append(args, "-H", fmt.Sprintf("%s: %s", k, v))
    }

    args = append(args, config.URL)

    cmd := exec.Command("curl", args...)
    output, err := cmd.Output()

    responseTime := time.Since(startTime).Milliseconds()

    info := &APIEndpointInfo{
        Name:         config.Name,
        URL:          config.URL,
        ResponseTime: responseTime,
        LastCheck:    time.Now(),
    }

    if err != nil {
        info.StatusCode = 0
        info.IsDown = true
    } else {
        // Parse output: "200|0.045"
        outputStr := strings.TrimSpace(string(output))
        parts := strings.SplitN(outputStr, "|", 2)
        if len(parts) >= 2 {
            info.StatusCode, _ = strconv.Atoi(parts[0])
        }
        info.IsDown = info.StatusCode >= 400 || info.StatusCode == 0
    }

    m.processEndpointStatus(config.Name, info)
}

func (m *APIEndpointMonitor) processEndpointStatus(name string, info *APIEndpointInfo) {
    lastInfo := m.endpointState[name]

    if lastInfo == nil {
        m.endpointState[name] = info
        return
    }

    // Check for down status
    if info.IsDown && !lastInfo.IsDown {
        info.ConsecutiveFails = lastInfo.ConsecutiveFails + 1
        if info.ConsecutiveFails >= 3 {
            m.onEndpointDown(name, info)
        }
    } else if !info.IsDown {
        info.ConsecutiveFails = 0
    }

    // Check for recovery
    if !info.IsDown && lastInfo.IsDown && lastInfo.ConsecutiveFails >= 3 {
        m.onEndpointRecovered(name, info)
    }

    // Check for slow response
    if info.ResponseTime >= int64(m.config.SlowThreshold) {
        if lastInfo.ResponseTime < int64(m.config.SlowThreshold) {
            m.onSlowResponse(name, info)
        }
    }

    // Check for status code changes
    if lastInfo.StatusCode != info.StatusCode && lastInfo.StatusCode != 0 {
        if info.StatusCode >= 500 {
            m.onServerError(name, info)
        } else if info.StatusCode >= 400 {
            m.onClientError(name, info)
        }
    }

    m.endpointState[name] = info
}

func (m *APIEndpointMonitor) onEndpointDown(name string, info *APIEndpointInfo) {
    if !m.config.SoundOnDown {
        return
    }

    key := fmt.Sprintf("down:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *APIEndpointMonitor) onEndpointRecovered(name string, info *APIEndpointInfo) {
    // Optional: sound when endpoint recovers
}

func (m *APIEndpointMonitor) onSlowResponse(name string, info *APIEndpointInfo) {
    if !m.config.SoundOnSlow {
        return
    }

    key := fmt.Sprintf("slow:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *APIEndpointMonitor) onServerError(name string, info *APIEndpointInfo) {
    if !m.config.SoundOnError {
        return
    }

    key := fmt.Sprintf("error:%s:%d", name, info.StatusCode)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *APIEndpointMonitor) onClientError(name string, info *APIEndpointInfo) {
    // Optional: sound for 4xx errors
}

func (m *APIEndpointMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| curl | System Tool | Free | HTTP client |

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
| macOS | Supported | Uses curl |
| Linux | Supported | Uses curl |
