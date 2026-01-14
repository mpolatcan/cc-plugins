# Feature: Sound Event Service Health Monitor

Play sounds for service health check failures and recovery events.

## Summary

Monitor service health endpoints, response times, and availability status, playing sounds for service health events.

## Motivation

- Service availability awareness
- Health check alerts
- Response time warnings
- Recovery notifications
- Service dependency tracking

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Service Health Events

| Event | Description | Example |
|-------|-------------|---------|
| Health Check Pass | Service is healthy | HTTP 200 OK |
| Health Check Fail | Service unhealthy | HTTP 503 |
| Response Slow | Response time high | > 2s response |
| Service Down | Service not responding | Connection refused |
| Service Recovered | Service back online | Recovered from fail |
| Certificate Expiring | SSL cert expiring soon | 7 days left |

### Configuration

```go
type ServiceHealthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Services          []ServiceConfig   `json:"services"`
    ResponseThreshold int               `json:"response_threshold_ms"` // 2000 default
    WarningThreshold  int               `json:"warning_threshold_ms"` // 1000 default
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnRecover    bool              `json:"sound_on_recover"]
    SoundOnSlow       bool              `json:"sound_on_slow"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type ServiceConfig struct {
    Name     string `json:"name"`
    URL      string `json:"url"` // http://localhost:8080/health
    Type     string `json:"type"` // "http", "tcp", "exec"
    Expected string `json:"expected"` // "200", "connected"
}

type ServiceHealthEvent struct {
    Service     string
    Status      string // "healthy", "unhealthy", "slow", "down"
    ResponseMs  int
    HTTPStatus  int
    Error       string
    EventType   string // "fail", "recover", "slow", "cert"
}
```

### Commands

```bash
/ccbell:health status                 # Show service health status
/ccbell:health add myapp              # Add service to watch
/ccbell:health remove myapp
/ccbell:health threshold 2000         # Set response threshold ms
/ccbell:health sound fail <sound>
/ccbell:health test                   # Test health sounds
```

### Output

```
$ ccbell:health status

=== Sound Event Service Health Monitor ===

Status: Enabled
Response Warning: 1000ms
Response Critical: 2000ms
Fail Sounds: Yes
Recover Sounds: Yes

Monitored Services: 4

[1] webapp (http://localhost:8080/health)
    Status: HEALTHY
    Response: 45 ms
    HTTP: 200
    Uptime: 5 days
    Sound: bundled:health-webapp

[2] api (http://localhost:9000/health)
    Status: UNHEALTHY
    Response: 5000 ms
    HTTP: 503
    Uptime: 2 hours
    Error: Connection timeout
    Sound: bundled:health-api

[3] postgres (tcp://localhost:5432)
    Status: HEALTHY
    Response: 5 ms
    Connected: Yes
    Sound: bundled:health-db

[4] redis (tcp://localhost:6379)
    Status: SLOW
    Response: 1200 ms
    Warning: Above 1000ms threshold
    Sound: bundled:health-cache

Recent Events:
  [1] api: Health Check Failed (5 min ago)
       HTTP 503 Service Unavailable
  [2] redis: Response Slow (10 min ago)
       1200ms > 1000ms threshold
  [3] api: Service Recovered (1 hour ago)
       Health check passing again

Service Statistics:
  Total Services: 4
  Healthy: 3
  Unhealthy: 1
  Avg Response: 150 ms

Sound Settings:
  Fail: bundled:health-fail
  Recover: bundled:health-recover
  Slow: bundled:health-slow

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Service health monitoring doesn't play sounds directly:
- Monitoring feature using curl/netcat
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Service Health Monitor

```go
type ServiceHealthMonitor struct {
    config          *ServiceHealthMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serviceState    map[string]*ServiceStatus
    lastEventTime   map[string]time.Time
}

type ServiceStatus struct {
    Name         string
    URL          string
    Type         string
    Status       string // "healthy", "unhealthy", "unknown"
    ResponseMs   int
    HTTPStatus   int
    LastCheck    time.Time
    FailCount    int
}

func (m *ServiceHealthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]*ServiceStatus)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ServiceHealthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.checkAllServices()

    for {
        select {
        case <-ticker.C:
            m.checkAllServices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ServiceHealthMonitor) checkAllServices() {
    for _, svc := range m.config.Services {
        m.checkService(&svc)
    }
}

func (m *ServiceHealthMonitor) checkService(svc *ServiceConfig) {
    key := svc.Name
    status := &ServiceStatus{
        Name:      svc.Name,
        URL:       svc.URL,
        Type:      svc.Type,
        LastCheck: time.Now(),
    }

    switch svc.Type {
    case "http":
        m.checkHTTPService(svc, status)
    case "tcp":
        m.checkTCPService(svc, status)
    case "exec":
        m.checkExecService(svc, status)
    }

    lastStatus := m.serviceState[key]
    if lastStatus == nil {
        m.serviceState[key] = status
        return
    }

    // Evaluate status changes
    m.evaluateStatusChange(key, status, lastStatus)
    m.serviceState[key] = status
}

func (m *ServiceHealthMonitor) checkHTTPService(svc *ServiceConfig, status *ServiceStatus) {
    start := time.Now()

    cmd := exec.Command("curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
        "-m", "10", "--connect-timeout", "5", svc.URL)
    output, err := cmd.Output()

    status.ResponseMs = int(time.Since(start).Milliseconds())

    if err != nil {
        status.Status = "unhealthy"
        status.Error = err.Error()
        return
    }

    httpStatus, _ := strconv.Atoi(strings.TrimSpace(string(output)))
    status.HTTPStatus = httpStatus

    if httpStatus >= 200 && httpStatus < 400 {
        status.Status = "healthy"
    } else if httpStatus >= 400 {
        status.Status = "unhealthy"
    }

    // Check response time
    if status.ResponseMs >= m.config.ResponseThreshold {
        status.Status = "slow"
    } else if status.ResponseMs >= m.config.WarningThreshold {
        // Still healthy but slow
    }
}

func (m *ServiceHealthMonitor) checkTCPService(svc *ServiceConfig, status *ServiceStatus) {
    // Extract host and port from URL
    // tcp://localhost:5432 -> localhost:5432
    addr := strings.TrimPrefix(svc.URL, "tcp://")

    start := time.Now()

    cmd := exec.Command("nc", "-z", "-w", "5", strings.Split(addr, ":")[0],
        strings.Split(addr, ":")[1])
    err := cmd.Run()

    status.ResponseMs = int(time.Since(start).Milliseconds())

    if err != nil {
        status.Status = "unhealthy"
        status.Error = "Connection failed"
    } else {
        status.Status = "healthy"
    }
}

func (m *ServiceHealthMonitor) checkExecService(svc *ServiceConfig, status *ServiceStatus) {
    start := time.Now()

    cmd := exec.Command("sh", "-c", svc.URL)
    err := cmd.Run()

    status.ResponseMs = int(time.Since(start).Milliseconds())

    if err != nil {
        status.Status = "unhealthy"
        status.Error = err.Error()
    } else {
        status.Status = "healthy"
    }
}

func (m *ServiceHealthMonitor) evaluateStatusChange(key string, newStatus *ServiceStatus, lastStatus *ServiceStatus) {
    // Check for failure
    if lastStatus.Status == "healthy" && newStatus.Status != "healthy" {
        if newStatus.Status == "unhealthy" {
            m.onServiceFail(newStatus)
        } else if newStatus.Status == "slow" {
            m.onServiceSlow(newStatus)
        }
    }

    // Check for recovery
    if lastStatus.Status != "healthy" && newStatus.Status == "healthy" {
        m.onServiceRecovered(newStatus)
    }
}

func (m *ServiceHealthMonitor) onServiceFail(status *ServiceStatus) {
    if !m.config.SoundOnFail {
        return
    }

    status.FailCount++

    key := fmt.Sprintf("fail:%s", status.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *ServiceHealthMonitor) onServiceSlow(status *ServiceStatus) {
    if !m.config.SoundOnSlow {
        return
    }

    key := fmt.Sprintf("slow:%s", status.Name)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["slow"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ServiceHealthMonitor) onServiceRecovered(status *ServiceStatus) {
    if !m.config.SoundOnRecover {
        return
    }

    key := fmt.Sprintf("recover:%s", status.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["recover"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ServiceHealthMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| curl | System Tool | Free | HTTP health checks |
| nc | System Tool | Free | TCP connection checks |

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
| macOS | Supported | Uses curl, nc |
| Linux | Supported | Uses curl, nc |
