# Feature: Sound Event Container Status Monitor

Play sounds for container state changes, health checks, and restart events.

## Summary

Monitor container status for running/stopped states, health check failures, and restart events, playing sounds for container events.

## Motivation

- Container awareness
- Service health alerts
- Crash detection
- Restart notifications
- Orchestration feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Container Status Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Running | Started successfully | up |
| Container Stopped | Exited unexpectedly | down |
| Health Check Fail | Unhealthy status | unhealthy |
| Container Restarted | Rebooted container | restart |
| Image Updated | New image pulled | new version |
|OOM Killed | Out of memory killed | OOM |

### Configuration

```go
type ContainerStatusMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchContainers   []string          `json:"watch_containers"` // "web", "db", "*"
    WatchImages       []string          `json:"watch_images"` // "nginx", "*"
    SoundOnRunning    bool              `json:"sound_on_running"`
    SoundOnStopped    bool              `json:"sound_on_stopped"`
    SoundOnUnhealthy  bool              `json:"sound_on_unhealthy"`
    SoundOnRestart    bool              `json:"sound_on_restart"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:container status               # Show container status
/ccbell:container add web              # Add container to watch
/ccbell:container remove web
/ccbell:container sound running <sound>
/ccbell:container sound stopped <sound>
/ccbell:container test                 # Test container sounds
```

### Output

```
$ ccbell:container status

=== Sound Event Container Status Monitor ===

Status: Enabled
Running Sounds: Yes
Stopped Sounds: Yes
Unhealthy Sounds: Yes

Watched Containers: 5
Watched Images: 2

Container Status:

[1] web (nginx:latest)
    Status: Running
    Health: Healthy
    Restarts: 0
    Uptime: 2 days
    Sound: bundled:container-web

[2] db (postgres:15)
    Status: Running
    Health: Healthy
    Restarts: 1
    Uptime: 1 day
    Sound: bundled:container-db

[3] api (myapp:latest)
    Status: Running
    Health: Unhealthy
    Restarts: 3
    Uptime: 6 hours
    Sound: bundled:container-api *** WARNING ***

[4] worker (myworker:latest)
    Status: Exited
    Exit Code: 137
    Uptime: 30 min
    Sound: bundled:container-worker *** FAILED ***

[5] cache (redis:alpine)
    Status: Running
    Health: Healthy
    Restarts: 0
    Uptime: 1 week
    Sound: bundled:container-cache

Recent Events:
  [1] api: Health Check Failing (5 min ago)
       Unhealthy for 3 checks
  [2] worker: Container Stopped (30 min ago)
       Exit code: 137 (OOM)
  [3] web: Container Restarted (1 hour ago)
       Manual restart

Container Statistics:
  Running: 4
  Stopped: 1
  Unhealthy: 1
  Total Restarts: 4

Sound Settings:
  Running: bundled:container-running
  Stopped: bundled:container-stopped
  Unhealthy: bundled:container-unhealthy
  Restart: bundled:container-restart

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Container monitoring doesn't play sounds directly:
- Monitoring feature using docker/podman
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Container Status Monitor

```go
type ContainerStatusMonitor struct {
    config          *ContainerStatusMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    containerState  map[string]*ContainerInfo
    lastEventTime   map[string]time.Time
}

type ContainerInfo struct {
    Name       string
    Image      string
    Status     string // "running", "exited", "created", "paused"
    Health     string // "healthy", "unhealthy", "starting", "none"
    Restarts   int
    ExitCode   int
    StartedAt  time.Time
}

func (m *ContainerStatusMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]*ContainerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ContainerStatusMonitor) monitor() {
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

func (m *ContainerStatusMonitor) snapshotContainerState() {
    containers := m.listContainers()

    for _, c := range containers {
        m.containerState[c.Name] = c
    }
}

func (m *ContainerStatusMonitor) checkContainerState() {
    currentContainers := m.listContainers()
    currentMap := make(map[string]*ContainerInfo)

    for _, c := range currentContainers {
        currentMap[c.Name] = c
    }

    // Check each watched container
    for _, name := range m.config.WatchContainers {
        current := currentMap[name]
        last := m.containerState[name]

        if current == nil {
            // Container no longer exists
            if last != nil {
                delete(m.containerState, name)
                m.onContainerRemoved(last)
            }
            continue
        }

        currentMap[name] = current // Mark as processed

        if last == nil {
            m.containerState[name] = current
            m.onContainerStarted(current)
            continue
        }

        // Check status changes
        if last.Status != current.Status {
            if current.Status == "running" {
                m.onContainerStarted(current)
            } else if current.Status == "exited" || current.Status == "created" {
                m.onContainerStopped(current, last)
            }
        }

        // Check health changes
        if last.Health != current.Health {
            if current.Health == "unhealthy" {
                m.onContainerUnhealthy(current)
            } else if current.Health == "healthy" {
                m.onContainerHealthy(current)
            }
        }

        // Check restart count
        if current.Restarts > last.Restarts {
            m.onContainerRestarted(current, current.Restarts-last.Restarts)
        }

        m.containerState[name] = current
    }

    // Check for removed containers
    for name, last := range m.containerState {
        if _, exists := currentMap[name]; !exists {
            delete(m.containerState, name)
            m.onContainerRemoved(last)
        }
    }
}

func (m *ContainerStatusMonitor) listContainers() []*ContainerInfo {
    var containers []*ContainerInfo

    // Try docker first, then podman
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Health}}")
    output, err := cmd.Output()

    if err != nil {
        // Try podman
        cmd = exec.Command("podman", "ps", "-a", "--format", "{{.Names}}|{{.Status}}")
        output, err = cmd.Output()
        if err != nil {
            return containers
        }
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }

        parts := strings.SplitN(line, "|", 3)
        if len(parts) < 2 {
            continue
        }

        name := parts[0]
        status := parts[1]

        if !m.shouldWatchContainer(name) {
            continue
        }

        info := &ContainerInfo{
            Name:   name,
            Status: m.parseStatus(status),
        }

        // Get image name
        imageCmd := exec.Command("docker", "inspect", "--format", "{{.Config.Image}}", name)
        imageOutput, _ := imageCmd.Output()
        info.Image = strings.TrimSpace(string(imageOutput))

        // Get restart count
        restartCmd := exec.Command("docker", "inspect", "--format", "{{.RestartCount}}", name)
        restartOutput, _ := restartCmd.Output()
        if restart, err := strconv.Atoi(strings.TrimSpace(string(restartOutput))); err == nil {
            info.Restarts = restart
        }

        // Get health if available
        if len(parts) >= 3 {
            info.Health = parts[2]
            if info.Health == "" {
                info.Health = "none"
            }
        } else {
            info.Health = "none"
        }

        containers = append(containers, info)
    }

    return containers
}

func (m *ContainerStatusMonitor) parseStatus(status string) string {
    status = strings.ToLower(status)
    if strings.Contains(status, "up") {
        return "running"
    } else if strings.Contains(status, "exited") {
        return "exited"
    } else if strings.Contains(status, "created") {
        return "created"
    } else if strings.Contains(status, "paused") {
        return "paused"
    }
    return "unknown"
}

func (m *ContainerStatusMonitor) onContainerStarted(info *ContainerInfo) {
    if !m.config.SoundOnRunning {
        return
    }

    key := fmt.Sprintf("running:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["running"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ContainerStatusMonitor) onContainerStopped(info *ContainerInfo, last *ContainerInfo) {
    if !m.config.SoundOnStopped {
        return
    }

    key := fmt.Sprintf("stopped:%s", info.Name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["stopped"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ContainerStatusMonitor) onContainerUnhealthy(info *ContainerInfo) {
    if !m.config.SoundOnUnhealthy {
        return
    }

    key := fmt.Sprintf("unhealthy:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["unhealthy"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ContainerStatusMonitor) onContainerHealthy(info *ContainerInfo) {
    // Optional: sound when container becomes healthy again
}

func (m *ContainerStatusMonitor) onContainerRestarted(info *ContainerInfo, count int) {
    if !m.config.SoundOnRestart {
        return
    }

    key := fmt.Sprintf("restart:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["restart"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ContainerStatusMonitor) onContainerRemoved(info *ContainerInfo) {
    // Optional: sound when container is removed
}

func (m *ContainerStatusMonitor) shouldWatchContainer(name string) bool {
    if len(m.config.WatchContainers) == 0 {
        return true
    }

    for _, c := range m.config.WatchContainers {
        if c == "*" || name == c || strings.HasPrefix(name, c) {
            return true
        }
    }

    return false
}

func (m *ContainerStatusMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| podman | System Tool | Free | Container management |

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
| macOS | Supported | Uses docker, podman |
| Linux | Supported | Uses docker, podman |
