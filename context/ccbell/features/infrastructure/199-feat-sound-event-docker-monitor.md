# Feature: Sound Event Docker Monitor

Play sounds for Docker container events.

## Summary

Play sounds when Docker containers start, stop, or have issues.

## Motivation

- Container awareness
- Build completion
- Service monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Docker Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Started | Container running | Service up |
| Container Stopped | Container stopped | Service down |
| Build Complete | Image built | Build done |
| Build Failed | Build failed | Build error |
| Health Check | Health status | Unhealthy |

### Configuration

```go
type DockerMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchContainers []string       `json:"watch_containers"` // Container names/IDs
    WatchImages   []string          `json:"watch_images"` // Image names
    Events        []string          `json:"events"` // Events to listen for
    Sounds        map[string]string `json:"sounds"`
    IncludeBuild  bool              `json:"include_build"`
}

type DockerState struct {
    Container    string
    Image        string
    Status       string
    Health       string
    StartedAt    time.Time
}
```

### Commands

```bash
/ccbell:docker status               # Show Docker status
/ccbell:docker add myapp            # Watch container
/ccbell:docker add myapp --sound stop_sound
/ccbell:docker sound started <sound>
/ccbell:docker sound stopped <sound>
/ccbell:docker sound build_success <sound>
/ccbell:docker sound build_failed <sound>
/ccbell:docker remove myapp
/ccbell:docker test                 # Test Docker sounds
```

### Output

```
$ ccbell:docker status

=== Sound Event Docker Monitor ===

Status: Enabled

Watched Containers: 3

[1] myapp
    Image: myapp:latest
    Status: Running (healthy)
    Started: 2 hours ago
    Sound: bundled:stop
    [Edit] [Remove]

[2] database
    Image: postgres:15
    Status: Running (healthy)
    Started: 3 hours ago
    Sound: bundled:stop
    [Edit] [Remove]

[3] worker
    Image: worker:latest
    Status: Exited (137)
    Started: 1 day ago
    Exit Code: 137 (OOM)
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] myapp: Started (5 min ago)
  [2] worker: Exited (1 hour ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Docker monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Docker Monitor

```go
type DockerMonitor struct {
    config   *DockerMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStates map[string]*DockerState
}

func (m *DockerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStates = make(map[string]*DockerState)
    go m.monitor()
}

func (m *DockerMonitor) monitor() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkContainers()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DockerMonitor) checkContainers() {
    for _, container := range m.config.WatchContainers {
        state := m.getContainerState(container)
        m.evaluateState(container, state)
    }
}

func (m *DockerMonitor) getContainerState(containerID string) *DockerState {
    state := &DockerState{
        Container: containerID,
    }

    // Get container status
    cmd := exec.Command("docker", "inspect", "--format",
        "{{.State.Status}}", containerID)
    output, err := cmd.Output()
    if err != nil {
        state.Status = "unknown"
        return state
    }
    state.Status = strings.TrimSpace(string(output))

    // Get image name
    cmd = exec.Command("docker", "inspect", "--format",
        "{{.Config.Image}}", containerID)
    output, err = cmd.Output()
    if err == nil {
        state.Image = strings.TrimSpace(string(output))
    }

    // Get health status if available
    cmd = exec.Command("docker", "inspect", "--format",
        "{{.State.Health.Status}}", containerID)
    output, err = cmd.Output()
    if err == nil {
        state.Health = strings.TrimSpace(string(output))
    }

    // Get start time
    cmd = exec.Command("docker", "inspect", "--format",
        "{{.State.StartedAt}}", containerID)
    output, err = cmd.Output()
    if err == nil {
        t, _ := time.Parse(time.RFC3339Nano, strings.TrimSpace(string(output)))
        state.StartedAt = t
    }

    return state
}

func (m *DockerMonitor) evaluateState(containerID string, state *DockerState) {
    lastState := m.lastStates[containerID]
    m.lastStates[containerID] = state

    if lastState == nil {
        return
    }

    // Check for status change
    if state.Status != lastState.Status {
        switch state.Status {
        case "running":
            if lastState.Status == "created" || lastState.Status == "exited" {
                m.playDockerEvent(containerID, "started", m.config.Sounds["started"])
            }
        case "exited":
            if lastState.Status == "running" {
                m.playDockerEvent(containerID, "stopped", m.config.Sounds["stopped"])
                // Get exit code
                cmd := exec.Command("docker", "inspect", "--format",
                    "{{.State.ExitCode}}", containerID)
                if output, _ := cmd.Output(); len(output) > 0 {
                    exitCode := strings.TrimSpace(string(output))
                    if exitCode != "0" {
                        m.playDockerEvent(containerID, "failed", m.config.Sounds["failed"])
                    }
                }
            }
        }
    }

    // Check for health change
    if state.Health != "" && state.Health != lastState.Health {
        if state.Health == "unhealthy" {
            m.playDockerEvent(containerID, "unhealthy", m.config.Sounds["unhealthy"])
        } else if state.Health == "healthy" && lastState.Health == "unhealthy" {
            m.playDockerEvent(containerID, "healthy", m.config.Sounds["healthy"])
        }
    }
}

// Listen for real-time Docker events
func (m *DockerMonitor) listenEvents() {
    cmd := exec.Command("docker", "events", "--filter", "type=container")
    stdout, _ := cmd.StdoutPipe()
    cmd.Start()

    scanner := bufio.NewScanner(stdout)
    for scanner.Scan() {
        line := scanner.Text()
        // Parse event and play sound
        // event: 2024-01-15T10:30:45.123456789+00:00 container start myapp
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| docker | System Tool | Free | Docker CLI |

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
| macOS | ✅ Supported | Uses docker CLI |
| Linux | ✅ Supported | Uses docker CLI |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
