# Feature: Sound Event Web Server Monitor

Play sounds for web server status changes, response code errors, and traffic spikes.

## Summary

Monitor web servers (nginx, Apache, etc.) for status changes, HTTP errors, and traffic anomalies, playing sounds for web server events.

## Motivation

- Web server awareness
- Error detection
- Traffic alerts
- Service health monitoring
- Performance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Web Server Events

| Event | Description | Example |
|-------|-------------|---------|
| Server Down | Service stopped | 503 |
| Server Up | Service started | 200 OK |
| High Traffic | Requests > threshold | > 1000/min |
| HTTP Error | 5xx error | 500 Internal |
| Slow Response | Latency > threshold | > 2s |
| SSL Expired | Certificate expired | expiring |

### Configuration

```go
type WebServerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServers      []string          `json:"watch_servers"` // "localhost:8080", "https://example.com"
    TrafficThreshold  int               `json:"traffic_threshold_rpm"` // 1000 default
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 2000 default
    ErrorThreshold    int               `json:"error_threshold_count"` // 5 default
    SoundOnDown       bool              `json:"sound_on_down"`
    SoundOnUp         bool              `json:"sound_on_up"`
    SoundOnError      bool              `json:"sound_on_error"`
    SoundOnHighTraffic bool             `json:"sound_on_high_traffic"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:web status                  # Show web server status
/ccbell:web add localhost:8080      # Add server to watch
/ccbell:web traffic 1000            # Set traffic threshold
/ccbell:web sound down <sound>
/ccbell:web test                    # Test web sounds
```

### Output

```
$ ccbell:web status

=== Sound Event Web Server Monitor ===

Status: Enabled
Traffic Threshold: 1000 RPM
Latency Threshold: 2000ms

Server Status:

[1] http://localhost:8080 (nginx)
    Status: UP
    Response: 200 OK
    Latency: 45ms
    Requests/min: 850
    Error Rate: 0.1%
    Sound: bundled:web-nginx

[2] https://api.example.com (API)
    Status: UP
    Response: 200 OK
    Latency: 120ms
    Requests/min: 2500 *** HIGH TRAFFIC ***
    Error Rate: 0.5%
    Sound: bundled:web-api *** WARNING ***

[3] http://localhost:3000 (Node.js)
    Status: DOWN *** DOWN ***
    Response: -
    Latency: -
    Requests/min: 0
    Error Rate: -
    Sound: bundled:web-node *** FAILED ***

Traffic Overview:

  localhost:8080: 850 RPM (Normal)
  api.example.com: 2500 RPM (High)
  localhost:3000: 0 RPM (Down)

Recent Events:
  [1] localhost:3000: Server Down (5 min ago)
       Connection refused
       Sound: bundled:web-down
  [2] api.example.com: High Traffic (10 min ago)
       2500 RPM > 1000 threshold
       Sound: bundled:web-traffic
  [3] localhost:8080: Server Up (1 hour ago)
       nginx started
       Sound: bundled:web-up

Server Statistics:
  Total Servers: 3
  Up: 2
  Down: 1
  Avg Latency: 82ms

Sound Settings:
  Up: bundled:web-up
  Down: bundled:web-down
  Error: bundled:web-error
  Traffic: bundled:web-traffic

[Configure] [Add Server] [Test All]
```

---

## Audio Player Compatibility

Web server monitoring doesn't play sounds directly:
- Monitoring feature using curl/nginx status
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Web Server Monitor

```go
type WebServerMonitor struct {
    config          *WebServerMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serverState     map[string]*ServerInfo
    lastEventTime   map[string]time.Time
}

type ServerInfo struct {
    URL           string
    Name          string
    Type          string // "nginx", "apache", "node", "generic"
    Status        string // "up", "down", "unknown"
    ResponseCode  int
    Latency       time.Duration
    RequestsPerMin int
    ErrorRate     float64
    LastCheck     time.Time
}

func (m *WebServerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serverState = make(map[string]*ServerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *WebServerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotServerState()

    for {
        select {
        case <-ticker.C:
            m.checkServerState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *WebServerMonitor) snapshotServerState() {
    m.checkServerState()
}

func (m *WebServerMonitor) checkServerState() {
    for _, server := range m.config.WatchServers {
        info := m.checkServer(server)
        if info != nil {
            m.processServerStatus(info)
        }
    }
}

func (m *WebServerMonitor) checkServer(serverURL string) *ServerInfo {
    info := &ServerInfo{
        URL:       serverURL,
        Name:      m.extractName(serverURL),
        LastCheck: time.Now(),
    }

    // Detect server type
    info.Type = m.detectServerType(serverURL)

    // Perform health check
    start := time.Now()
    cmd := exec.Command("curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
        "-m", "10", serverURL)
    output, err := cmd.CombinedOutput()
    info.Latency = time.Since(start)

    if err != nil {
        info.Status = "down"
        info.ResponseCode = 0
        return info
    }

    codeStr := strings.TrimSpace(string(output))
    code, err := strconv.Atoi(codeStr)
    if err != nil {
        info.Status = "unknown"
        return info
    }

    info.ResponseCode = code

    if code >= 200 && code < 400 {
        info.Status = "up"
    } else if code >= 400 {
        info.Status = "error"
    } else {
        info.Status = "unknown"
    }

    // Get more details based on server type
    if info.Type == "nginx" {
        m.getNginxStatus(info)
    } else if info.Type == "apache" {
        m.getApacheStatus(info)
    }

    return info
}

func (m *WebServerMonitor) detectServerType(serverURL string) string {
    // Try to detect from common patterns
    if strings.Contains(serverURL, "nginx") {
        return "nginx"
    }
    if strings.Contains(serverURL, "apache") {
        return "apache"
    }
    if strings.Contains(serverURL, ":3000") || strings.Contains(serverURL, ":5000") {
        return "node"
    }
    return "generic"
}

func (m *WebServerMonitor) extractName(serverURL string) string {
    // Extract name from URL
    u, err := url.Parse(serverURL)
    if err != nil {
        return serverURL
    }

    host := u.Hostname()
    if host == "localhost" || host == "127.0.0.1" {
        return u.Host // include port
    }
    return host
}

func (m *WebServerMonitor) getNginxStatus(info *ServerInfo) {
    // Check nginx status page if available
    statusURL := strings.TrimSuffix(info.URL, "/") + "/nginx_status"
    cmd := exec.Command("curl", "-s", "-m", "5", statusURL)
    output, err := cmd.Output()

    if err != nil {
        return
    }

    outputStr := string(output)
    // Parse nginx status: Active connections, requests, etc.
    re := regexp.MustEach(`Active connections: (\d+)`)
    matches := re.FindStringSubmatch(outputStr)
    if len(matches) >= 2 {
        // We have active connections
    }
}

func (m *WebServerMonitor) getApacheStatus(info *ServerInfo) {
    // Check apache status page if available
    statusURL := strings.TrimSuffix(info.URL, "/") + "/server-status"
    cmd := exec.Command("curl", "-s", "-m", "5", statusURL)
    output, err := cmd.Output()

    if err != nil {
        return
    }

    outputStr := string(output)
    // Parse apache status
    if strings.Contains(outputStr, "Total Accesses") {
        info.Type = "apache"
    }
}

func (m *WebServerMonitor) processServerStatus(info *ServerInfo) {
    lastInfo := m.serverState[info.URL]

    if lastInfo == nil {
        m.serverState[info.URL] = info
        if info.Status == "up" && m.config.SoundOnUp {
            m.onServerUp(info)
        } else if info.Status == "down" && m.config.SoundOnDown {
            m.onServerDown(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        switch info.Status {
        case "up":
            if m.config.SoundOnUp {
                m.onServerUp(info)
            }
        case "down":
            if m.config.SoundOnDown {
                m.onServerDown(info)
            }
        case "error":
            if m.config.SoundOnError {
                m.onServerError(info)
            }
        }
    }

    // Check for high traffic
    if info.RequestsPerMin >= m.config.TrafficThreshold &&
       lastInfo.RequestsPerMin < m.config.TrafficThreshold {
        if m.config.SoundOnHighTraffic {
            m.onHighTraffic(info)
        }
    }

    m.serverState[info.URL] = info
}

func (m *WebServerMonitor) onServerUp(info *ServerInfo) {
    key := fmt.Sprintf("up:%s", info.URL)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["up"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *WebServerMonitor) onServerDown(info *ServerInfo) {
    key := fmt.Sprintf("down:%s", info.URL)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *WebServerMonitor) onServerError(info *ServerInfo) {
    key := fmt.Sprintf("error:%s", info.URL)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["error"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *WebServerMonitor) onHighTraffic(info *ServerInfo) {
    key := fmt.Sprintf("traffic:%s", info.URL)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["high_traffic"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *WebServerMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| nginx | System Tool | Free | Web server (optional) |
| apache | System Tool | Free | Web server (optional) |

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
