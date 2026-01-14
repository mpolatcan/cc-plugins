# Feature: Sound Event Service Monitor

Play sounds for system service status changes, failures, and restarts.

## Summary

Monitor systemd services (and launchd on macOS) for status changes, failures, and dependency issues, playing sounds for service events.

## Motivation

- Service awareness
- Failure detection
- Restart notifications
- Dependency awareness
- Service health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Service Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Service is running | active: running |
| Service Stopped | Service is stopped | inactive: dead |
| Service Failed | Service failed | failed |
| Service Restarted | Service was restarted | restart count |
| Service Reloaded | Config reloaded | active: reloading |
| Dependency Broken | Dependency missing | dependency failed |

### Configuration

```go
type ServiceMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchServices   []string          `json:"watch_services"` // "nginx", "postgresql", "*"
    SoundOnStart    bool              `json:"sound_on_start"`
    SoundOnStop     bool              `json:"sound_on_stop"`
    SoundOnFailed   bool              `json:"sound_on_failed"`
    SoundOnRestart  bool              `json:"sound_on_restart"`
    SoundOnReload   bool              `json:"sound_on_reload"`
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:service status              # Show service status
/ccbell:service add nginx           # Add service to watch
/ccbell:service sound failed <sound>
/ccbell:service test                # Test service sounds
```

### Output

```
$ ccbell:service status

=== Sound Event Service Monitor ===

Status: Enabled
Watch Services: all

Service Status:

[1] nginx (systemd)
    Status: ACTIVE
    State: running
    Since: Jan 14 08:00
    Restarts: 0
    Sound: bundled:service-nginx

[2] postgresql (systemd)
    Status: ACTIVE
    State: running
    Since: Jan 14 07:30
    Restarts: 0
    Sound: bundled:service-postgres

[3] redis (systemd)
    Status: FAILED *** FAILED ***
    State: failed
    Since: -
    Restarts: 3
    Exit Code: exit_code=255
    Sound: bundled:service-redis *** FAILED ***

[4] docker (systemd)
    Status: ACTIVE
    State: running
    Since: Jan 14 07:00
    Restarts: 0
    Sound: bundled:service-docker

Recent Events:

[1] redis: Service Failed (5 min ago)
       Exit code 255
       Sound: bundled:service-failed
  [2] redis: Service Restarted (10 min ago)
       Restart count: 3
       Sound: bundled:service-restart
  [3] nginx: Service Reloaded (1 hour ago)
       Configuration reloaded
       Sound: bundled:service-reload

Service Statistics:
  Total Services: 4
  Running: 3
  Failed: 1
  Restarts Today: 3

Sound Settings:
  Start: bundled:service-start
  Stop: bundled:service-stop
  Failed: bundled:service-failed
  Restart: bundled:service-restart

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Service monitoring doesn't play sounds directly:
- Monitoring feature using systemctl, launchctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Service Monitor

```go
type ServiceMonitor struct {
    config        *ServiceMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    serviceState  map[string]*ServiceInfo
    lastEventTime map[string]time.Time
}

type ServiceInfo struct {
    Name       string
    Active     string // "active", "inactive", "failed"
    Sub        string // "running", "dead", "failed", "reloading"
    Since      time.Time
    MainPID    int
    Restarts   int
    ExecMainExitCode int
}

func (m *ServiceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]*ServiceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ServiceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotServiceState()

    for {
        select {
        case <-ticker.C:
            m.checkServiceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ServiceMonitor) snapshotServiceState() {
    m.checkServiceState()
}

func (m *ServiceMonitor) checkServiceState() {
    for _, serviceName := range m.config.WatchServices {
        info := m.getServiceInfo(serviceName)
        if info != nil {
            m.processServiceStatus(info)
        }
    }
}

func (m *ServiceMonitor) getServiceInfo(serviceName string) *ServiceInfo {
    info := &ServiceInfo{
        Name: serviceName,
    }

    cmd := exec.Command("systemctl", "show", serviceName, "--no-pager")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    return m.parseSystemctlOutput(string(output), serviceName)
}

func (m *ServiceMonitor) parseSystemctlOutput(output string, serviceName string) *ServiceInfo {
    info := &ServiceInfo{
        Name: serviceName,
    }

    lines := strings.Split(output, "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, "=", 2)
        if len(parts) < 2 {
            continue
        }

        key := parts[0]
        value := parts[1]

        switch key {
        case "ActiveState":
            info.Active = value
        case "SubState":
            info.Sub = value
        case "ActiveEnterTimestamp":
            if value != "" {
                info.Since, _ = time.Parse("Mon 2006-01-02 15:04:05 MST", value)
            }
        case "MainPID":
            info.MainPID, _ = strconv.Atoi(value)
        case "RestartCount":
            info.Restarts, _ = strconv.Atoi(value)
        case "ExecMainExitCode":
            info.ExecMainExitCode, _ = strconv.Atoi(value)
        }
    }

    return info
}

func (m *ServiceMonitor) processServiceStatus(info *ServiceInfo) {
    lastInfo := m.serviceState[info.Name]

    if lastInfo == nil {
        m.serviceState[info.Name] = info

        if info.Active == "active" && info.Sub == "running" {
            if m.config.SoundOnStart {
                m.onServiceStarted(info)
            }
        } else if info.Active == "failed" {
            if m.config.SoundOnFailed {
                m.onServiceFailed(info)
            }
        }
        return
    }

    // Check for state changes
    if info.Active != lastInfo.Active || info.Sub != lastInfo.Sub {
        // Service started
        if info.Active == "active" && info.Sub == "running" {
            if lastInfo.Active != "active" || lastInfo.Sub != "running" {
                if m.config.SoundOnStart {
                    m.onServiceStarted(info)
                }
            }
        }

        // Service stopped
        if info.Active == "inactive" && lastInfo.Active == "active" {
            if m.config.SoundOnStop {
                m.onServiceStopped(info)
            }
        }

        // Service failed
        if info.Active == "failed" && lastInfo.Active != "failed" {
            if m.config.SoundOnFailed {
                m.onServiceFailed(info)
            }
        }

        // Service reloaded
        if info.Sub == "reloading" && lastInfo.Sub != "reloading" {
            if m.config.SoundOnReload {
                m.onServiceReloaded(info)
            }
        }
    }

    // Check for restarts
    if info.Restarts > lastInfo.Restarts {
        if m.config.SoundOnRestart && m.shouldAlert(info.Name+"restart", 2*time.Minute) {
            m.onServiceRestarted(info)
        }
    }

    m.serviceState[info.Name] = info
}

func (m *ServiceMonitor) onServiceStarted(info *ServiceInfo) {
    key := fmt.Sprintf("start:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ServiceMonitor) onServiceStopped(info *ServiceInfo) {
    key := fmt.Sprintf("stop:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ServiceMonitor) onServiceFailed(info *ServiceInfo) {
    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *ServiceMonitor) onServiceRestarted(info *ServiceInfo) {
    sound := m.config.Sounds["restart"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ServiceMonitor) onServiceReloaded(info *ServiceInfo) {
    sound := m.config.Sounds["reload"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *ServiceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| systemctl | System Tool | Free | Systemd control |
| launchctl | System Tool | Free | macOS launchd |

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
