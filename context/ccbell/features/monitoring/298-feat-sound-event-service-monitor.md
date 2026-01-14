# Feature: Sound Event Service Monitor

Play sounds for system service state changes.

## Summary

Monitor system service status, crashes, and restarts, playing sounds for service events.

## Motivation

- Service failure alerts
- Auto-restart feedback
- Service health awareness
- Dependency failure detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Service Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Service launched | nginx running |
| Service Stopped | Service stopped | nginx stopped |
| Service Restarted | Service restarted | nginx restarted |
| Service Failed | Service crashed | nginx failed |
| Service Enabled | Auto-start enabled | nginx enabled |

### Configuration

```go
type ServiceMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchServices  []string          `json:"watch_services"` // "nginx", "postgres"
    SoundOnStart   bool              `json:"sound_on_start"`
    SoundOnStop    bool              `json:"sound_on_stop"`
    SoundOnFail    bool              `json:"sound_on_fail"`
    SoundOnRestart bool              `json:"sound_on_restart"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 10 default
}

type ServiceEvent struct {
    ServiceName string
    State       string // "running", "stopped", "failed", "restarting"
    PID         int
    ExitCode    int
    EventType   string
}
```

### Commands

```bash
/ccbell:service status                # Show service status
/ccbell:service add nginx             # Add service to watch
/ccbell:service remove nginx
/ccbell:service sound start <sound>
/ccbell:service sound fail <sound>
/ccbell:service test                  # Test service sounds
```

### Output

```
$ ccbell:service status

=== Sound Event Service Monitor ===

Status: Enabled
Stop Sounds: Yes
Fail Sounds: Yes

Watched Services: 3

[1] nginx
    State: Running (PID: 1234)
    Last Start: 5 min ago
    Restarts: 0
    Sound: bundled:stop

[2] postgres
    State: Running (PID: 5678)
    Last Start: 1 hour ago
    Restarts: 2
    Sound: bundled:stop

[3] redis
    State: FAILED (PID: --)
    Exit Code: 1
    Last Start: 2 hours ago
    Restarts: 5
    Sound: bundled:service-fail

Recent Events:
  [1] redis: Service Failed (5 min ago)
       Exit code: 1
  [2] nginx: Service Started (5 min ago)
       PID: 1234
  [3] postgres: Service Restarted (1 hour ago)
       PID: 5678 -> 5679

Sound Settings:
  Start: bundled:stop
  Stop: bundled:stop
  Fail: bundled:service-fail
  Restart: bundled:stop

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Service monitoring doesn't play sounds directly:
- Monitoring feature using service managers
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Service Monitor

```go
type ServiceMonitor struct {
    config          *ServiceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serviceState    map[string]string
    servicePID      map[int]string
    serviceRestart  map[string]int
}

func (m *ServiceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]string)
    m.servicePID = make(map[int]string)
    m.serviceRestart = make(map[string]int)
    go m.monitor()
}

func (m *ServiceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Snapshot initial state
    m.snapshotServiceStates()

    for {
        select {
        case <-ticker.C:
            m.checkServiceStates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ServiceMonitor) snapshotServiceStates() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinServices()
    } else {
        m.snapshotLinuxServices()
    }
}

func (m *ServiceMonitor) snapshotDarwinServices() {
    // Use launchctl list for running services
    for _, service := range m.config.WatchServices {
        m.checkDarwinService(service)
    }
}

func (m *ServiceMonitor) snapshotLinuxServices() {
    // Use systemctl for systemd services
    for _, service := range m.config.WatchServices {
        m.checkLinuxService(service)
    }
}

func (m *ServiceMonitor) checkServiceStates() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinServices()
    } else {
        m.checkLinuxServices()
    }
}

func (m *ServiceMonitor) checkDarwinServices() {
    for _, service := range m.config.WatchServices {
        m.checkDarwinService(service)
    }
}

func (m *ServiceMonitor) checkLinuxServices() {
    for _, service := range m.config.WatchServices {
        m.checkLinuxService(service)
    }
}

func (m *ServiceMonitor) checkDarwinService(service string) {
    // Check if service is loaded
    cmd := exec.Command("launchctl", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    state := m.parseLaunchctlList(string(output), service)

    if state != "" {
        m.onServiceStateChange(service, state)
    }
}

func (m *ServiceMonitor) checkLinuxService(service string) {
    // Get service status
    cmd := exec.Command("systemctl", "is-active", service)
    output, err := cmd.Output()

    state := "unknown"
    if err == nil {
        state = strings.TrimSpace(string(output))
        if state == "active" {
            state = "running"
        }
    } else if strings.Contains(err.Error(), "inactive") {
        state = "stopped"
    } else if strings.Contains(err.Error(), "failed") {
        state = "failed"
    }

    m.onServiceStateChange(service, state)
}

func (m *ServiceMonitor) parseLaunchctlList(output string, service string) string {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, service) && !strings.HasPrefix(line, "-") {
            if strings.Contains(line, "0") {
                return "running"
            }
            return "stopped"
        }
    }
    return ""
}

func (m *ServiceMonitor) onServiceStateChange(service string, newState string) {
    lastState := m.serviceState[service]

    if lastState == "" {
        // Initial state
        m.serviceState[service] = newState
        return
    }

    if lastState == newState {
        return
    }

    // Detect restart (stopped then running quickly)
    if lastState == "stopped" && newState == "running" {
        m.serviceRestart[service]++
        m.onServiceRestarted(service)
    } else if newState == "running" {
        m.onServiceStarted(service)
    } else if newState == "stopped" {
        m.onServiceStopped(service)
    } else if newState == "failed" {
        m.onServiceFailed(service)
    }

    m.serviceState[service] = newState
}

func (m *ServiceMonitor) onServiceStarted(service string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ServiceMonitor) onServiceStopped(service string) {
    if !m.config.SoundOnStop {
        return
    }

    sound := m.config.Sounds["stop"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ServiceMonitor) onServiceRestarted(service string) {
    if !m.config.SoundOnRestart {
        return
    }

    sound := m.config.Sounds["restart"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ServiceMonitor) onServiceFailed(service string) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["fail"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| launchctl | System Tool | Free | macOS service management |
| systemctl | System Tool | Free | Linux systemd services |

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
| macOS | Supported | Uses launchctl |
| Linux | Supported | Uses systemctl |
| Windows | Not Supported | ccbell only supports macOS/Linux |
