# Feature: Sound Event API Endpoint Monitor

Play sounds for API endpoint failures, response time degradation, and HTTP errors.

## Summary

Monitor REST API endpoints for availability, response times, and error rates, playing sounds for API events.

## Motivation

- API availability awareness
- Performance monitoring
- Error detection
- Health check feedback
- Service reliability

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
| Endpoint Down | Unreachable | 503 |
| Endpoint Up | Back online | 200 |
| Slow Response | Latency > threshold | > 1s |
| HTTP Error | 4xx or 5xx | 500 |
| Rate Limited | Too many requests | 429 |
| SSL Error | Certificate problem | SSL |

### Configuration

```go
type APIEndpointMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchEndpoints    []string          `json:"watch_endpoints"` // "https://api.example.com/health"
    Timeout           int               `json:"timeout_sec"` // 10 default
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 1000 default
    ExpectedStatus    int               `json:"expected_status"` // 200 default
    SoundOnDown       bool              `json:"sound_on_down"`
    SoundOnUp         bool              `json:"sound_on_up"`
    SoundOnSlow       bool              `json:"sound_on_slow"`
    SoundOnError      bool              `json:"sound_on_error"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:api status                  # Show API status
/ccbell:api add https://api.example.com/health
/ccbell:api latency 1000            # Set latency threshold
/ccbell:api sound down <sound>
/ccbell:api test                    # Test API sounds
```

### Output

```
$ ccbell:api status

=== Sound Event API Endpoint Monitor ===

Status: Enabled
Timeout: 10s
Latency Threshold: 1000ms

Endpoint Status:

[1] https://api.example.com/health
    Status: UP
    Response: 200 OK
    Latency: 45ms
    Uptime: 99.9%
    Checks Today: 1440
    Sound: bundled:api-health

[2] https://api.example.com/users
    Status: UP
    Response: 200 OK
    Latency: 120ms
    Uptime: 99.8%
    Checks Today: 1440
    Sound: bundled:api-users

[3] https://api.example.com/legacy
    Status: DOWN *** DOWN ***
    Response: 503 Service Unavailable
    Latency: -
    Uptime: 95.2%
    Checks Today: 1440
    Sound: bundled:api-legacy *** FAILED ***

[4] https://payment.example.com/api
    Status: SLOW *** SLOW ***
    Response: 200 OK
    Latency: 2500ms *** HIGH LATENCY ***
    Uptime: 99.5%
    Checks Today: 720
    Sound: bundled:api-payment *** WARNING ***

API Health Summary:

  Total Endpoints: 4
  Healthy: 3
  Down: 1
  Avg Latency: 422ms

Recent Events:
  [1] https://api.example.com/legacy: Down (5 min ago)
       503 Service Unavailable
       Sound: bundled:api-down
  [2] https://payment.example.com/api: Slow (10 min ago)
       2500ms > 1000ms threshold
       Sound: bundled:api-slow
  [3] https://api.example.com/health: Up (1 hour ago)
       200 OK
       Sound: bundled:api-up

API Statistics:
  Checks Today: 4320
  Failures: 12
  Avg Response: 422ms

Sound Settings:
  Up: bundled:api-up
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
    endpointState   map[string]*EndpointInfo
    lastEventTime   map[string]time.Time
}

type EndpointInfo struct {
    URL          string
    Name         string
    Status       string // "up", "down", "slow", "unknown"
    ResponseCode int
    Latency      time.Duration
    Uptime       float64
    ChecksTotal  int
    ChecksFailed int
    LastCheck    time.Time
}

func (m *APIEndpointMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.endpointState = make(map[string]*EndpointInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *APIEndpointMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotEndpointState()

    for {
        select {
        case <-ticker.C:
            m.checkEndpointState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *APIEndpointMonitor) snapshotEndpointState() {
    m.checkEndpointState()
}

func (m *APIEndpointMonitor) checkEndpointState() {
    for _, endpoint := range m.config.WatchEndpoints {
        info := m.checkEndpoint(endpoint)
        if info != nil {
            m.processEndpointStatus(info)
        }
    }
}

func (m *APIEndpointMonitor) checkEndpoint(endpointURL string) *EndpointInfo {
    info := &EndpointInfo{
        URL:       endpointURL,
        Name:      m.extractName(endpointURL),
        LastCheck: time.Now(),
    }

    // Perform health check with curl
    cmd := exec.Command("curl", "-s", "-o", "/dev/null",
        "-w", "%{http_code}|%{time_total}",
        "-m", strconv.Itoa(m.config.Timeout),
        endpointURL)

    start := time.Now()
    output, err := cmd.CombinedOutput()
    info.Latency = time.Since(start)

    if err != nil {
        info.Status = "down"
        info.ChecksFailed++
        info.ChecksTotal++
        return info
    }

    // Parse response
    outputStr := strings.TrimSpace(string(output))
    parts := strings.Split(outputStr, "|")

    if len(parts) >= 2 {
        code, _ := strconv.Atoi(parts[0])
        info.ResponseCode = code

        // Parse latency
        latencySec, _ := strconv.ParseFloat(parts[1], 64)
        info.Latency = time.Duration(latencySec * float64(time.Second))
    }

    // Determine status
    if info.ResponseCode >= 200 && info.ResponseCode < 300 {
        info.Status = "up"
    } else if info.ResponseCode >= 400 || info.ResponseCode == 0 {
        info.Status = "down"
    } else {
        info.Status = "unknown"
    }

    // Check for slow response
    if info.Latency.Milliseconds() >= int64(m.config.LatencyThreshold) {
        info.Status = "slow"
    }

    info.ChecksTotal++
    if info.Status == "down" {
        info.ChecksFailed++
    }

    // Calculate uptime
    if info.ChecksTotal > 0 {
        info.Uptime = float64(info.ChecksTotal-info.ChecksFailed) / float64(info.ChecksTotal) * 100
    }

    return info
}

func (m *APIEndpointMonitor) extractName(url string) string {
    u, err := url.Parse(url)
    if err != nil {
        return url
    }

    path := u.Path
    if path == "/" || path == "" {
        return u.Host
    }

    return strings.TrimPrefix(path, "/")
}

func (m *APIEndpointMonitor) processEndpointStatus(info *EndpointInfo) {
    lastInfo := m.endpointState[info.URL]

    if lastInfo == nil {
        m.endpointState[info.URL] = info

        if info.Status == "up" && m.config.SoundOnUp {
            m.onEndpointUp(info)
        } else if info.Status == "down" && m.config.SoundOnDown {
            m.onEndpointDown(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "up":
            if m.config.SoundOnUp {
                m.onEndpointUp(info)
            }
        case "down":
            if m.config.SoundOnDown {
                m.onEndpointDown(info)
            }
        case "slow":
            if m.config.SoundOnSlow {
                m.onEndpointSlow(info)
            }
        }
    }

    // Check for HTTP errors
    if info.ResponseCode >= 400 && lastInfo.ResponseCode < 400 {
        if m.config.SoundOnError {
            m.onHTTPError(info)
        }
    }

    m.endpointState[info.URL] = info
}

func (m *APIEndpointMonitor) onEndpointUp(info *EndpointInfo) {
    key := fmt.Sprintf("up:%s", info.URL)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["up"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *APIEndpointMonitor) onEndpointDown(info *EndpointInfo) {
    key := fmt.Sprintf("down:%s", info.URL)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *APIEndpointMonitor) onEndpointSlow(info *EndpointInfo) {
    key := fmt.Sprintf("slow:%s", info.URL)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *APIEndpointMonitor) onHTTPError(info *EndpointInfo) {
    key := fmt.Sprintf("error:%s:%d", info.URL, info.ResponseCode)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
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
