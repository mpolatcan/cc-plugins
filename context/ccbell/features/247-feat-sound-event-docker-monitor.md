# Feature: Sound Event Docker Monitor

Play sounds for Docker container and image events.

## Summary

Monitor Docker containers, images, and Docker daemon events, playing sounds for container operations.

## Motivation

- Container state awareness
- Image pull completion
- Container crash alerts
- Build completion feedback

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
| Container Started | Container running | docker run nginx |
| Container Stopped | Container exited | docker stop |
| Container Crashed | Container died | Exit code 1 |
| Image Pulled | Image downloaded | docker pull ubuntu |
| Image Built | Build completed | docker build |
| Docker Build Fail | Build errored | Dockerfile error |

### Configuration

```go
type DockerMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchContainers  []string          `json:"watch_containers"` // Container names
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnCrash     bool              `json:"sound_on_crash"`
    SoundOnImagePull bool              `json:"sound_on_image_pull"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type DockerEvent struct {
    ContainerName string
    EventType     string // "start", "stop", "crash", "image_pull", "build"
    ImageName     string
    ExitCode      int
}
```

### Commands

```bash
/ccbell:docker status            # Show docker status
/ccbell:docker add my-container  # Add container to watch
/ccbell:docker remove my-container
/ccbell:docker sound start <sound>
/ccbell:docker sound crash <sound>
/ccbell:docker test              # Test docker sounds
```

### Output

```
$ ccbell:docker status

=== Sound Event Docker Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Crash Sounds: Yes

Watched Containers: 3

[1] nginx
    Status: RUNNING (2 days)
    Image: nginx:1.21
    Sound: bundled:stop

[2] postgres
    Status: RUNNING (5 hours)
    Image: postgres:14
    Sound: bundled:stop

[3] redis
    Status: EXITED (30 min)
    Image: redis:7
    Exit Code: 137 (OOM)
    Sound: bundled:stop

Recent Events:
  [1] nginx: Container Started (2 days ago)
  [2] postgres: Container Started (5 hours ago)
  [3] redis: Container Crashed (30 min ago)
       Exit code: 137 (OOM killed)

Sound Settings:
  Start: bundled:stop
  Stop: bundled:stop
  Crash: bundled:stop
  Image Pull: bundled:stop
  Build: bundled:stop

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

### Docker Monitor

```go
type DockerMonitor struct {
    config         *DockerMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    containerState map[string]*ContainerStatus
}

type ContainerStatus struct {
    Name       string
    Running    bool
    ExitCode   int
    LastUpdate time.Time
}

func (m *DockerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]*ContainerStatus)
    go m.monitor()
}

func (m *DockerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
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
    // Get all container statuses
    containers := m.getAllContainers()

    for _, container := range containers {
        m.evaluateContainer(container)
    }
}

func (m *DockerMonitor) getAllContainers() []*ContainerInfo {
    var containers []*ContainerInfo

    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Image}}")
    output, err := cmd.Output()
    if err != nil {
        return containers
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.SplitN(line, "|", 3)
        if len(parts) < 3 {
            continue
        }

        status := m.parseStatus(parts[1])

        containers = append(containers, &ContainerInfo{
            Name:   parts[0],
            Status: status,
            Image:  parts[2],
        })
    }

    return containers
}

func (m *DockerMonitor) parseStatus(status string) ContainerState {
    if strings.Contains(status, "Up") {
        return StateRunning
    }
    if strings.Contains(status, "Exited") {
        // Extract exit code
        re := regexp.MustCompile(`Exited \((\d+)\)`)
        match := re.FindStringSubmatch(status)
        if len(match) >= 2 {
            if code, err := strconv.Atoi(match[1]); err == nil {
                if code != 0 {
                    return StateCrashed
                }
            }
        }
        return StateStopped
    }
    return StateUnknown
}

func (m *DockerMonitor) evaluateContainer(info *ContainerInfo) {
    lastState := m.containerState[info.Name]

    if lastState == nil {
        // First time seeing this container
        m.containerState[info.Name] = &ContainerStatus{
            Name:       info.Name,
            Running:    info.Status == StateRunning,
            ExitCode:   info.ExitCode,
            LastUpdate: time.Now(),
        }

        if info.Status == StateRunning {
            m.onContainerStart(info.Name)
        }
        return
    }

    // Detect state changes
    if !lastState.Running && info.Status == StateRunning {
        m.onContainerStart(info.Name)
    } else if lastState.Running && info.Status == StateStopped {
        m.onContainerStop(info.Name, 0)
    } else if lastState.Running && info.Status == StateCrashed {
        m.onContainerCrash(info.Name, info.ExitCode)
    }

    // Update state
    m.containerState[info.Name] = &ContainerStatus{
        Name:       info.Name,
        Running:    info.Status == StateRunning,
        ExitCode:   info.ExitCode,
        LastUpdate: time.Now(),
    }
}

func (m *DockerMonitor) onContainerStart(name string) {
    if !m.config.SoundOnStart {
        return
    }

    sound := m.config.Sounds["start"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *DockerMonitor) onContainerStop(name string, exitCode int) {
    if !m.config.SoundOnStop {
        return
    }

    sound := m.config.Sounds["stop"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *DockerMonitor) onContainerCrash(name string, exitCode int) {
    if !m.config.SoundOnCrash {
        return
    }

    sound := m.config.Sounds["crash"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| docker | System Tool | Free | Container runtime |
| exec | Go Stdlib | Free | Command execution |

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
| macOS | Supported | Uses docker command |
| Linux | Supported | Uses docker command |
| Windows | Not Supported | ccbell only supports macOS/Linux |
