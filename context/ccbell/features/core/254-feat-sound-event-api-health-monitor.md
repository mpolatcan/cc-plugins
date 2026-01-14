# Feature: Sound Event API Health Monitor

Play sounds for API endpoint health status and availability changes.

## Summary

Monitor API endpoints, health check status, and service availability, playing sounds when endpoints go down or recover.

## Motivation

- Service outage alerts
- API recovery notifications
- Health check feedback
- Dependency monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### API Health Events

| Event | Description | Example |
|-------|-------------|---------|
| Endpoint Down | Service unreachable | 500 error |
| Endpoint Up | Service recovered | 200 OK |
| Slow Response | Latency > threshold | > 1s |
| SSL Expiring | Certificate expiring | 7 days left |

### Configuration

```go
type APIHealthMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    Endpoints      []string          `json:"endpoints"` // URLs to monitor
    Timeout        int               `json:"timeout_ms"` // 5000 default
    LatencyWarning int               `json:"latency_warning_ms"` // 1000 default
    CheckInterval  int               `json:"check_interval_sec"` // 30 default
    SoundOnDown    bool              `json:"sound_on_down"`
    SoundOnUp      bool              `json:"sound_on_up"`
    SoundOnSlow    bool              `json:"sound_on_slow"`
    Sounds         map[string]string `json:"sounds"`
}

type APIHealthEvent struct {
    URL           string
    StatusCode   int
    LatencyMs    int
    EventType    string // "down", "up", "slow", "ssl_warning"
    ErrorMessage string
}
```

### Commands

```bash
/ccbell:api-health status              # Show API health status
/ccbell:api-health add https://api.example.com
/ccbell:api-health remove https://api.example.com
/ccbell:api-health sound down <sound>
/ccbell:api-health sound up <sound>
/ccbell:api-health test                # Test API health sounds
```

### Output

```
$ ccbell:api-health status

=== Sound Event API Health Monitor ===

Status: Enabled
Check Interval: 30s
Timeout: 5s

Watched Endpoints: 3

[1] https://api.example.com
    Status: UP
    Latency: 45ms
    Last Check: 10s ago
    Sound: bundled:stop

[2] https://api.database.example.com
    Status: DOWN
    Latency: 5000ms+ (timeout)
    Last Check: 10s ago
    Error: connection timeout
    Sound: bundled:stop

[3] https://api.cache.example.com
    Status: UP
    Latency: 120ms
    Last Check: 10s ago
    Sound: bundled:stop

Recent Events:
  [1] api.database.example.com: DOWN (5 min ago)
       Connection timeout
  [2] api.example.com: SLOW (1 hour ago)
       Latency: 1500ms
  [3] api.cache.example.com: UP (2 hours ago)
       Recovered from DOWN

Sound Settings:
  Down: bundled:stop
  Up: bundled:stop
  Slow: bundled:stop

[Configure] [Add Endpoint] [Test All]
```

---

## Audio Player Compatibility

API health monitoring doesn't play sounds directly:
- Monitoring feature using HTTP client
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### API Health Monitor

```go
type APIHealthMonitor struct {
    config           *APIHealthMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    endpointState    map[string]*EndpointStatus
}

type EndpointStatus struct {
    URL           string
    LastStatus    string // "up", "down", "unknown"
    LastCheck     time.Time
    LastLatency   int
    DownSince     time.Time
    ConsecutiveDown int
}

func (m *APIHealthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.endpointState = make(map[string]*EndpointStatus)
    go m.monitor()
}

func (m *APIHealthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Second)
    defer ticker.Stop()

    // Initial check
    m.checkAllEndpoints()

    for {
        select {
        case <-ticker.C:
            m.checkAllEndpoints()
        case <-m.stopCh:
            return
        }
    }
}

func (m *APIHealthMonitor) checkAllEndpoints() {
    for _, endpoint := range m.config.Endpoints {
        m.checkEndpoint(endpoint)
    }
}

func (m *APIHealthMonitor) checkEndpoint(url string) {
    status := m.endpointState[url]
    if status == nil {
        status = &EndpointStatus{URL: url}
        m.endpointState[url] = status
    }

    // Perform health check
    result := m.performCheck(url)
    status.LastCheck = time.Now()
    status.LastLatency = result.LatencyMs

    // Determine if endpoint is up
    isUp := result.StatusCode >= 200 && result.StatusCode < 400

    // Evaluate state change
    if isUp {
        if status.LastStatus == "down" {
            // Recovered
            status.ConsecutiveDown = 0
            m.onEndpointUp(url, result)
        }
        status.LastStatus = "up"
    } else {
        status.ConsecutiveDown++
        if status.LastStatus == "up" || status.ConsecutiveDown >= 2 {
            // Just went down (require 2 consecutive failures to avoid flapping)
            status.LastStatus = "down"
            m.onEndpointDown(url, result)
        }
    }

    // Check for slow response
    if result.LatencyMs >= m.config.LatencyWarning {
        m.onSlowResponse(url, result)
    }
}

func (m *APIHealthMonitor) performCheck(url string) *CheckResult {
    result := &CheckResult{}

    client := &http.Client{
        Timeout: time.Duration(m.config.Timeout) * time.Millisecond,
    }

    start := time.Now()
    resp, err := client.Get(url)
    result.LatencyMs = int(time.Since(start).Milliseconds())

    if err != nil {
        result.StatusCode = 0
        result.ErrorMessage = err.Error()
        return result
    }
    defer resp.Body.Close()

    result.StatusCode = resp.StatusCode
    return result
}

func (m *APIHealthMonitor) onEndpointDown(url string, result *CheckResult) {
    if !m.config.SoundOnDown {
        return
    }

    // Debounce: only play if down for more than 10 seconds
    status := m.endpointState[url]
    if status != nil && time.Since(status.DownSince) < 10*time.Second {
        return
    }

    if status != nil && status.DownSince.IsZero() {
        status.DownSince = time.Now()
    }

    sound := m.config.Sounds["down"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *APIHealthMonitor) onEndpointUp(url string, result *CheckResult) {
    if !m.config.SoundOnUp {
        return
    }

    status := m.endpointState[url]
    if status != nil {
        status.DownSince = time.Time{}
    }

    sound := m.config.Sounds["up"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *APIHealthMonitor) onSlowResponse(url string, result *CheckResult) {
    if !m.config.SoundOnSlow {
        return
    }

    // Only alert on significant slowness (not every check)
    status := m.endpointState[url]
    if status != nil && status.LastLatency >= m.config.LatencyWarning {
        // Already notified recently
        return
    }

    sound := m.config.Sounds["slow"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| net/http | Go Stdlib | Free | HTTP client |
| url | Go Stdlib | Free | URL parsing |

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
| macOS | Supported | Uses HTTP client |
| Linux | Supported | Uses HTTP client |
| Windows | Not Supported | ccbell only supports macOS/Linux |
