# Feature: Sound Event Docker Container Monitor

Play sounds for Docker container lifecycle events and health status changes.

## Summary

Monitor Docker container status, health checks, restart events, and container events, playing sounds for Docker container events.

## Motivation

- Container awareness
- Health check alerts
- Restart detection
- Resource exhaustion warnings
- Image pull notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Docker Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Started | Container started | web server started |
| Container Stopped | Container stopped | api gateway stopped |
| Container Restarted | Container restarted | db container restarted |
| Health Check Failed | Health check failed | unhealthy status |
| Container Unhealthy | Container unhealthy | restart loop detected |
| Image Pulled | New image downloaded | nginx:latest pulled |
| OOM Killed | Out of memory killed | container terminated |
| Volume Full | Storage threshold | 90% capacity |

### Configuration

```go
type DockerContainerMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    WatchContainers      []string          `json:"watch_containers"` // "web", "db", "*"
    HealthWarningPct     int               `json:"health_warning_pct"` // 80 default
    SoundOnStart         bool              `json:"sound_on_start"`
    SoundOnStop          bool              `json:"sound_on_stop"`
    SoundOnHealthFail    bool              `json:"sound_on_health_fail"`
    SoundOnOOM           bool              `json:"sound_on_oom"`
    SoundOnImagePull     bool              `json:"sound_on_image_pull"`
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 10 default
}

type DockerContainerEvent struct {
    Container  string
    Image      string
    Status     string // "running", "stopped", "restarting", "unhealthy"
    ExitCode   int
    Health     string // "healthy", "unhealthy", "starting"
    OOMKilled  bool
    EventType  string // "start", "stop", "restart", "health_fail", "oom", "image_pull"
}
```

### Commands

```bash
/ccbell:docker status                 # Show Docker status
/ccbell:docker add web                # Add container to watch
/ccbell:docker remove web
/ccbell:docker health 80              # Set health warning threshold
/ccbell:docker sound start <sound>
/ccbell:docker sound stop <sound>
/ccbell:docker sound health <sound>
/ccbell:docker test                   # Test Docker sounds
```

### Output

```
$ ccbell:docker status

=== Sound Event Docker Container Monitor ===

Status: Enabled
Health Warning: 80%
Start Sounds: Yes
Stop Sounds: Yes

Watched Containers: 3

[1] web (nginx:latest)
    Status: RUNNING
    Health: HEALTHY
    Restarts: 0
    Uptime: 5 days
    Sound: bundled:docker-start

[2] db (postgres:15)
    Status: RUNNING
    Health: HEALTHY
    Restarts: 2
    Uptime: 5 days
    Sound: bundled:docker-db

[3] api (myapp:latest)
    Status: RESTARTING
    Health: UNHEALTHY
    Restarts: 10
    Uptime: 2 hours
    Sound: bundled:docker-alert

Recent Events:
  [1] api: Container Restarted (5 min ago)
       Restarts: 10, Health failing
  [2] api: Health Check Failed (10 min ago)
       Unhealthy status detected
  [3] web: Container Started (1 hour ago)
       nginx:latest started

Docker Statistics:
  Total containers: 10
  Running: 8
  Stopped: 2

Sound Settings:
  Start: bundled:docker-start
  Stop: bundled:docker-stop
  Health Fail: bundled:docker-health
  OOM: bundled:docker-oom

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Docker monitoring doesn't play sounds directly:
- Monitoring feature using docker CLI
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Docker Container Monitor

```go
type DockerContainerMonitor struct {
    config            *DockerContainerMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    containerState    map[string]*ContainerInfo
    lastEventTime     map[string]time.Time
}

type ContainerInfo struct {
    Name       string
    Image      string
    Status     string
    Health     string
    Restarts   int
    ExitCode   int
    OOMKilled  bool
    StartedAt  time.Time
}

func (m *DockerContainerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]*ContainerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DockerContainerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotContainerState()

    for {
        select {
        case <-ticker.C:
            m.checkContainerState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DockerContainerMonitor) snapshotContainerState() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Health}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDockerPSOutput(string(output))
}

func (m *DockerContainerMonitor) checkContainerState() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Health}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseDockerPSOutput(string(output))
}

func (m *DockerContainerMonitor) parseDockerPSOutput(output string) {
    lines := strings.Split(output, "\n")
    currentContainers := make(map[string]*ContainerInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Split(line, "|")
        if len(parts) < 2 {
            continue
        }

        name := parts[0]
        if !m.shouldWatchContainer(name) {
            continue
        }

        status := parts[1]
        health := ""
        if len(parts) > 2 {
            health = parts[2]
        }

        // Get detailed info
        info := m.getContainerInfo(name)
        if info == nil {
            continue
        }

        currentContainers[name] = info

        lastInfo := m.containerState[name]
        if lastInfo == nil {
            // First time seeing this container
            m.containerState[name] = info
            if info.Status == "running" {
                m.onContainerStarted(name, info)
            }
            continue
        }

        // Check for state changes
        if lastInfo.Status != info.Status {
            if info.Status == "running" && lastInfo.Status != "running" {
                m.onContainerStarted(name, info)
            } else if info.Status != "running" && lastInfo.Status == "running" {
                m.onContainerStopped(name, info, lastInfo)
            }
        }

        // Check health changes
        if info.Health != "" && lastInfo.Health != info.Health {
            if info.Health == "unhealthy" {
                m.onHealthCheckFailed(name, info)
            }
        }

        // Check restart count
        if info.Restarts > lastInfo.Restarts {
            m.onContainerRestarted(name, info, lastInfo)
        }

        // Check OOM
        if info.OOMKilled && !lastInfo.OOMKilled {
            m.onOOMKilled(name, info)
        }

        m.containerState[name] = info
    }

    // Check for removed containers
    for name := range m.containerState {
        if _, exists := currentContainers[name]; !exists {
            delete(m.containerState, name)
        }
    }

    m.containerState = currentContainers
}

func (m *DockerContainerMonitor) getContainerInfo(name string) *ContainerInfo {
    cmd := exec.Command("docker", "inspect", "--format", "{{.State.Status}}|{{.State.Health.Status}}|{{.State.RestartCount}}|{{.State.ExitCode}}|{{.State.OOMKilled}}", name)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    parts := strings.Split(strings.TrimSpace(string(output)), "|")
    if len(parts) < 5 {
        return nil
    }

    status := parts[0]
    health := parts[1]
    restarts, _ := strconv.Atoi(parts[2])
    exitCode, _ := strconv.Atoi(parts[3])
    oomKilled := parts[4] == "true"

    // Get image name
    imgCmd := exec.Command("docker", "inspect", "--format", "{{.Config.Image}}", name)
    imgOutput, _ := imgCmd.Output()
    image := strings.TrimSpace(string(imgOutput))

    return &ContainerInfo{
        Name:      name,
        Image:     image,
        Status:    status,
        Health:    health,
        Restarts:  restarts,
        ExitCode:  exitCode,
        OOMKilled: oomKilled,
    }
}

func (m *DockerContainerMonitor) shouldWatchContainer(name string) bool {
    if len(m.config.WatchContainers) == 0 {
        return true
    }

    for _, c := range m.config.WatchContainers {
        if c == "*" || c == name {
            return true
        }
    }

    return false
}

func (m *DockerContainerMonitor) onContainerStarted(name string, info *ContainerInfo) {
    if !m.config.SoundOnStart {
        return
    }

    key := fmt.Sprintf("start:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DockerContainerMonitor) onContainerStopped(name string, info *ContainerInfo, last *ContainerInfo) {
    if !m.config.SoundOnStop {
        return
    }

    key := fmt.Sprintf("stop:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DockerContainerMonitor) onContainerRestarted(name string, info *ContainerInfo, last *ContainerInfo) {
    // Sound on restart is handled by stop + start events
}

func (m *DockerContainerMonitor) onHealthCheckFailed(name string, info *ContainerInfo) {
    if !m.config.SoundOnHealthFail {
        return
    }

    key := fmt.Sprintf("health_fail:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["health_fail"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DockerContainerMonitor) onOOMKilled(name string, info *ContainerInfo) {
    if !m.config.SoundOnOOM {
        return
    }

    key := fmt.Sprintf("oom:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["oom"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *DockerContainerMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| docker | System Tool | Free | Container management |
| docker ps | Command | Free | Container listing |
| docker inspect | Command | Free | Container details |

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
| macOS | Supported | Uses docker CLI |
| Linux | Supported | Uses docker CLI |
