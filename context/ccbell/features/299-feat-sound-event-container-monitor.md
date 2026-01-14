# Feature: Sound Event Container Monitor

Play sounds for container lifecycle events.

## Summary

Monitor container status, starts, stops, and crashes, playing sounds for container events.

## Motivation

- Container awareness
- Deployment feedback
- Crash detection
- Resource usage alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Container Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Started | Container launched | docker run nginx |
| Container Stopped | Container stopped | docker stop nginx |
| Container Crashed | Container exited with error | Exit code 1 |
| Image Pulled | New image downloaded | nginx:1.25 |

### Configuration

```go
type ContainerMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    ContainerRuntime string            `json:"container_runtime"` // "docker", "podman"
    WatchContainers  []string          `json:"watch_containers"`
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnCrash     bool              `json:"sound_on_crash"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}

type ContainerEvent struct {
    ContainerName string
    Image         string
    State         string // "running", "stopped", "crashed"
    ExitCode      int
    EventType     string
}
```

### Commands

```bash
/ccbell:container status              # Show container status
/ccbell:container add web             # Add container to watch
/ccbell:container remove web
/ccbell:container runtime docker      # Set container runtime
/ccbell:container sound start <sound>
/ccbell:container sound crash <sound>
/ccbell:container test                # Test container sounds
```

### Output

```
$ ccbell:container status

=== Sound Event Container Monitor ===

Status: Enabled
Runtime: docker
Start Sounds: Yes
Crash Sounds: Yes

Watched Containers: 3

[1] web (nginx:1.25)
    State: Running
    Ports: 80->80, 443->443
    Uptime: 5 days
    Sound: bundled:stop

[2] db (postgres:15)
    State: Running
    Ports: 5432->5432
    Uptime: 5 days
    Sound: bundled:stop

[3] worker (myapp:latest)
    State: CRASHED
    Exit Code: 1
    Restarts: 5
    Last Crash: 5 min ago
    Sound: bundled:container-crash

Recent Events:
  [1] worker: Container Crashed (5 min ago)
       Exit code: 1
  [2] web: Container Started (5 days ago)
       nginx:1.25
  [3] db: Container Started (5 days ago)
       postgres:15

Sound Settings:
  Start: bundled:stop
  Stop: bundled:stop
  Crash: bundled:container-crash

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Container monitoring doesn't play sounds directly:
- Monitoring feature using container runtime
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Container Monitor

```go
type ContainerMonitor struct {
    config           *ContainerMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    containerState   map[string]string
    containerExit    map[string]int
    containerRestarts map[string]int
}

func (m *ContainerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]string)
    m.containerExit = make(map[string]int)
    m.containerRestarts = make(map[string]int)
    go m.monitor()
}

func (m *ContainerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Snapshot initial state
    m.snapshotContainerStates()

    for {
        select {
        case <-ticker.C:
            m.checkContainerStates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ContainerMonitor) snapshotContainerStates() {
    switch m.config.ContainerRuntime {
    case "docker":
        m.snapshotDockerContainers()
    case "podman":
        m.snapshotPodmanContainers()
    default:
        m.snapshotDockerContainers()
    }
}

func (m *ContainerMonitor) snapshotDockerContainers() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Ports}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseContainerOutput(string(output))
}

func (m *ContainerMonitor) snapshotPodmanContainers() {
    cmd := exec.Command("podman", "ps", "-a", "--format", "{{.Names}}|{{.Status}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseContainerOutput(string(output))
}

func (m *ContainerMonitor) checkContainerStates() {
    switch m.config.ContainerRuntime {
    case "docker":
        m.checkDockerContainers()
    case "podman":
        m.checkPodmanContainers()
    default:
        m.checkDockerContainers()
    }
}

func (m *ContainerMonitor) checkDockerContainers() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Ports}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseContainerOutput(string(output))
}

func (m *ContainerMonitor) checkPodmanContainers() {
    cmd := exec.Command("podman", "ps", "-a", "--format", "{{.Names}}|{{.Status}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseContainerOutput(string(output))
}

func (m *ContainerMonitor) parseContainerOutput(output string) {
    lines := strings.Split(output, "\n")
    currentStates := make(map[string]string)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Split(line, "|")
        if len(parts) < 2 {
            continue
        }

        name := parts[0]
        status := parts[1]

        if !m.shouldWatchContainer(name) {
            continue
        }

        // Determine state
        state := "unknown"
        if strings.Contains(status, "Up") {
            state = "running"
        } else if strings.Contains(status, "Exited") {
            state = "stopped"
            // Extract exit code
            re := regexp.MustCompile(`Exited \((\d+)\)`)
            if match := re.FindStringSubmatch(status); match != nil {
                exitCode, _ := strconv.Atoi(match[1])
                m.containerExit[name] = exitCode
                if exitCode != 0 {
                    state = "crashed"
                }
            }
        }

        currentStates[name] = state
        m.onContainerStateChange(name, state)
    }
}

func (m *ContainerMonitor) shouldWatchContainer(name string) bool {
    if len(m.config.WatchContainers) == 0 {
        return true
    }

    for _, container := range m.config.WatchContainers {
        if name == container {
            return true
        }
    }

    return false
}

func (m *ContainerMonitor) onContainerStateChange(name string, newState string) {
    lastState := m.containerState[name]

    if lastState == "" {
        // Initial state
        m.containerState[name] = newState
        return
    }

    if lastState == newState {
        return
    }

    // State transition handling
    switch newState {
    case "running":
        if lastState == "stopped" || lastState == "crashed" {
            m.containerRestarts[name]++
        }
        m.onContainerStarted(name)
    case "stopped":
        m.onContainerStopped(name)
    case "crashed":
        m.onContainerCrashed(name)
    }

    m.containerState[name] = newState
}

func (m *ContainerMonitor) onContainerStarted(name string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ContainerMonitor) onContainerStopped(name string) {
    if !m.config.SoundOnStop {
        return
    }

    sound := m.config.Sounds["stop"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ContainerMonitor) onContainerCrashed(name string) {
    if !m.config.SoundOnCrash {
        return
    }

    // Debounce rapid crashes
    key := fmt.Sprintf("crash:%s", name)
    if lastCrash := m.lastCrashTime[key]; time.Since(lastCrash) < 1*time.Minute {
        return
    }
    m.lastCrashTime[key] = time.Now()

    sound := m.config.Sounds["crash"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| docker | Container Runtime | Free | Container management |
| podman | Container Runtime | Free | Container management |

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
| Windows | Not Supported | ccbell only supports macOS/Linux |
