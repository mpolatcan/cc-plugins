# Feature: Sound Event System Daemon Monitor

Play sounds for system daemon start, stop, and failure events.

## Summary

Monitor system daemons and services (launchd, systemd), playing sounds for service status changes.

## Motivation

- Service failure alerts
- Daemon restart detection
- System service awareness
- Startup completion feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### System Daemon Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Daemon launched | nginx started |
| Service Stopped | Daemon stopped | nginx stopped |
| Service Failed | Daemon crashed | nginx failed |
| Service Restarted | Daemon restarted | nginx restarted |
| System Rebooted | System rebooted | Boot complete |

### Configuration

```go
type SystemDaemonMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchServices    []string          `json:"watch_services"` // "nginx", "postgres"
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    SoundOnRestart   bool              `json:"sound_on_restart"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}

type SystemDaemonEvent struct {
    ServiceName string
    EventType   string // "started", "stopped", "failed", "restarted"
    ExitCode    int
    Reason      string
}
```

### Commands

```bash
/ccbell:daemon status                # Show daemon status
/ccbell:daemon add "nginx"           # Add service to watch
/ccbell:daemon remove "nginx"
/ccbell:daemon sound start <sound>
/ccbell:daemon sound fail <sound>
/ccbell:daemon test                  # Test daemon sounds
```

### Output

```
$ ccbell:daemon status

=== Sound Event System Daemon Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Fail Sounds: Yes

Watched Services: 4

[1] nginx
    Status: RUNNING
    PID: 12345
    Uptime: 5 days
    Sound: bundled:stop

[2] postgres
    Status: RUNNING
    PID: 23456
    Uptime: 5 days
    Sound: bundled:stop

[3] redis
    Status: STOPPED
    Last Run: 2 hours ago
    Exit Code: 1
    Error: Failed to bind port
    Sound: bundled:stop

[4] docker
    Status: RUNNING
    PID: 34567
    Uptime: 5 days
    Sound: bundled:stop

Recent Events:
  [1] nginx: Started (5 days ago)
  [2] redis: Failed (2 hours ago)
       Exit code: 1
  [3] postgres: Restarted (1 week ago)
       Reload completed

Sound Settings:
  Started: bundled:stop
  Stopped: bundled:stop
  Failed: bundled:stop
  Restarted: bundled:stop

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

System daemon monitoring doesn't play sounds directly:
- Monitoring feature using system service managers
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Daemon Monitor

```go
type SystemDaemonMonitor struct {
    config          *SystemDaemonMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serviceState    map[string]*ServiceStatus
}

type ServiceStatus struct {
    Name      string
    Running   bool
    PID       int
    StartTime time.Time
    ExitCode  int
}
```

```go
func (m *SystemDaemonMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]*ServiceStatus)
    go m.monitor()
}

func (m *SystemDaemonMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkServices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemDaemonMonitor) checkServices() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinServices()
    } else {
        m.checkLinuxServices()
    }
}

func (m *SystemDaemonMonitor) checkDarwinServices() {
    // Use launchctl to check services
    for _, service := range m.config.WatchServices {
        cmd := exec.Command("launchctl", "list", service)
        output, err := cmd.Output()

        status := &ServiceStatus{Name: service}
        status.Running = false

        if err == nil {
            // Parse output
            lines := strings.Split(string(output), "\n")
            for _, line := range lines {
                if strings.HasPrefix(line, "-") {
                    // Service is running
                    status.Running = true

                    // Extract PID if present
                    parts := strings.Fields(line)
                    if len(parts) > 0 {
                        if pid, err := strconv.Atoi(parts[0]); err == nil && pid > 0 {
                            status.PID = pid
                        }
                    }
                    break
                }
            }
        }

        m.evaluateService(service, status)
    }
}

func (m *SystemDaemonMonitor) checkLinuxServices() {
    // Use systemctl to check services
    for _, service := range m.config.WatchServices {
        cmd := exec.Command("systemctl", "is-active", service)
        output, err := cmd.Output()

        status := &ServiceStatus{Name: service}
        status.Running = false

        if err == nil {
            result := strings.TrimSpace(string(output))
            status.Running = (result == "active")
        }

        // Get PID if running
        if status.Running {
            pidCmd := exec.Command("systemctl", "show", service, "--property=MainPID", "--value")
            pidOutput, _ := pidCmd.Output()
            if pid, err := strconv.Atoi(strings.TrimSpace(string(pidOutput))); err == nil {
                status.PID = pid
            }
        }

        m.evaluateService(service, status)
    }
}

func (m *SystemDaemonMonitor) evaluateService(name string, status *ServiceStatus) {
    lastState := m.serviceState[name]

    if lastState == nil {
        // First time seeing this service
        m.serviceState[name] = status
        if status.Running {
            m.onServiceStarted(name)
        }
        return
    }

    // Detect state changes
    if !lastState.Running && status.Running {
        // Service started
        status.StartTime = time.Now()
        m.onServiceStarted(name)
    } else if lastState.Running && !status.Running {
        // Service stopped
        m.onServiceStopped(name, status.ExitCode)
    } else if lastState.Running && status.Running && lastState.PID != status.PID {
        // Service restarted (PID changed)
        m.onServiceRestarted(name)
    }

    m.serviceState[name] = status
}

func (m *SystemDaemonMonitor) onServiceStarted(name string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemDaemonMonitor) onServiceStopped(name string, exitCode int) {
    if !m.config.SoundOnStop {
        return
    }

    sound := m.config.Sounds["stopped"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemDaemonMonitor) onServiceFailed(name string, reason string) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *SystemDaemonMonitor) onServiceRestarted(name string) {
    if !m.config.SoundOnRestart {
        return
    }

    sound := m.config.Sounds["restarted"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| launchctl | System Tool | Free | macOS service manager |
| systemctl | System Tool | Free | Linux systemd |

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
