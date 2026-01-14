# Feature: Sound Event Docker Container Monitor

Play sounds for Docker container events, image updates, and registry changes.

## Summary

Monitor Docker containers for state changes, image updates, and container events, playing sounds for Docker events.

## Motivation

- Container awareness
- Image update detection
- Container event tracking
- Registry sync monitoring
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

### Docker Container Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Created | Container created | docker run |
| Container Started | Container started | up |
| Container Stopped | Container stopped | down |
| Container Restarted | Container restarted | restart |
| Image Pulled | New image downloaded | latest |
| Image Updated | Tag updated | v2.0.0 |
| Container Died | Crashed | exit 1 |
| Health Check Changed | Status changed | healthy -> unhealthy |

### Configuration

```go
type DockerContainerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchContainers   []string          `json:"watch_containers"` // "web", "db", "*"
    WatchImages       []string          `json:"watch_images"` // "nginx", "*"
    WatchRegistries   []string          `json:"watch_registries"` // "docker.io", "ghcr.io"
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnStop       bool              `json:"sound_on_stop"`
    SoundOnImage      bool              `json:"sound_on_image"`
    SoundOnHealth     bool              `json:"sound_on_health"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:docker status                  # Show Docker status
/ccbell:docker add web                 # Add container to watch
/ccbell:docker remove web
/ccbell:docker sound start <sound>
/ccbell:docker sound stop <sound>
/ccbell:docker test                    # Test Docker sounds
```

### Output

```
$ ccbell:docker status

=== Sound Event Docker Container Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Image Sounds: Yes

Watched Containers: 4
Watched Images: 3

Container Status:

[1] web (nginx:latest)
    Status: RUNNING
    Image: nginx:1.25-alpine
    Ports: 80->80, 443->443
    Health: HEALTHY
    Uptime: 2 days
    Sound: bundled:docker-web

[2] db (postgres:15)
    Status: RUNNING
    Image: postgres:15
    Ports: 5432->5432
    Health: HEALTHY
    Uptime: 1 week
    Sound: bundled:docker-db

[3] api (myapp:latest)
    Status: RUNNING
    Image: myapp:v2.0.1
    Ports: 8080->8080
    Health: UNHEALTHY
    Uptime: 6 hours
    Sound: bundled:docker-api *** WARNING ***

[4] worker (myapp-worker:latest)
    Status: EXITED
    Exit Code: 137 (OOM)
    Uptime: 30 min
    Image: myapp-worker:v2.0.0
    Sound: bundled:docker-worker *** FAILED ***

Recent Events:
  [1] api: Health Check Failed (5 min ago)
       Unhealthy for 3 checks
  [2] worker: Container Died (30 min ago)
       Exit code: 137 (OOM killed)
  [3] web: Image Updated (1 hour ago)
       nginx:1.24 -> 1.25-alpine
  [4] db: Container Restarted (2 hours ago)
       Manual restart

Docker Statistics:
  Total Containers: 4
  Running: 3
  Stopped: 1
  Unhealthy: 1

Image Updates Available:
  myapp:latest -> v2.0.1 available
  postgres:15 -> 15.2 available

Sound Settings:
  Start: bundled:docker-start
  Stop: bundled:docker-stop
  Image: bundled:docker-image
  Health: bundled:docker-health

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Docker monitoring doesn't play sounds directly:
- Monitoring feature using docker
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Docker Container Monitor

```go
type DockerContainerMonitor struct {
    config          *DockerContainerMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    containerState  map[string]*ContainerInfo
    imageState      map[string]*ImageInfo
    lastEventTime   map[string]time.Time
}

type ContainerInfo struct {
    Name       string
    Image      string
    Status     string // "running", "exited", "created", "paused"
    Health     string // "healthy", "unhealthy", "starting", "none"
    ExitCode   int
    Ports      string
    StartedAt  time.Time
}

type ImageInfo struct {
    Name       string
    Tag        string
    Size       int64
    Created    time.Time
    Digest     string
}

func (m *DockerContainerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]*ContainerInfo)
    m.imageState = make(map[string]*ImageInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DockerContainerMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotState()

    for {
        select {
        case <-ticker.C:
            m.checkState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DockerContainerMonitor) snapshotState() {
    m.checkContainers()
    m.checkImages()
}

func (m *DockerContainerMonitor) checkState() {
    m.checkContainers()
    m.checkImages()
}

func (m *DockerContainerMonitor) checkContainers() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    currentContainers := make(map[string]*ContainerInfo)

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.SplitN(line, "|", 4)
        if len(parts) < 3 {
            continue
        }

        name := parts[0]
        status := m.parseStatus(parts[1])
        image := parts[2]
        ports := ""
        if len(parts) >= 4 {
            ports = parts[3]
        }

        if !m.shouldWatchContainer(name) {
            continue
        }

        info := &ContainerInfo{
            Name:   name,
            Image:  image,
            Status: status,
            Ports:  ports,
        }

        // Get health status
        health := m.getContainerHealth(name)
        info.Health = health

        // Get started time
        startedAt := m.getContainerStartedAt(name)
        info.StartedAt = startedAt

        // Get exit code if exited
        if status == "exited" {
            info.ExitCode = m.getContainerExitCode(name)
        }

        currentContainers[name] = info

        lastInfo := m.containerState[name]
        if lastInfo == nil {
            m.containerState[name] = info
            if status == "running" {
                m.onContainerStarted(info)
            }
            continue
        }

        // Check for state changes
        if lastInfo.Status != status {
            if status == "running" {
                m.onContainerStarted(info)
            } else if status == "exited" {
                m.onContainerStopped(info, lastInfo)
            }
        }

        // Check health changes
        if lastInfo.Health != info.Health {
            if info.Health == "unhealthy" && m.config.SoundOnHealth {
                m.onContainerUnhealthy(info)
            } else if info.Health == "healthy" && lastInfo.Health == "unhealthy" {
                m.onContainerHealthy(info)
            }
        }

        m.containerState[name] = info
    }

    // Check for removed containers
    for name, lastInfo := range m.containerState {
        if _, exists := currentContainers[name]; !exists {
            delete(m.containerState, name)
            m.onContainerRemoved(lastInfo)
        }
    }
}

func (m *DockerContainerMonitor) checkImages() {
    cmd := exec.Command("docker", "images", "--format", "{{.Repository}}:{{.Tag}}|{{.Size}}|{{.CreatedSince}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    currentImages := make(map[string]*ImageInfo)

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.SplitN(line, "|", 3)
        if len(parts) < 2 {
            continue
        }

        name := parts[0]
        if !m.shouldWatchImage(name) {
            continue
        }

        size, _ := strconv.ParseInt(parts[1], 10, 64)

        info := &ImageInfo{
            Name:    name,
            Tag:     m.getTagFromName(name),
            Size:    size,
            Created: m.parseTime(parts[2]),
        }

        currentImages[name] = info

        lastInfo := m.imageState[name]
        if lastInfo == nil {
            m.imageState[name] = info
            continue
        }

        // Check for image updates
        if lastInfo.Created != info.Created {
            if m.config.SoundOnImage {
                m.onImageUpdated(info)
            }
        }

        m.imageState[name] = info
    }
}

func (m *DockerContainerMonitor) parseStatus(status string) string {
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

func (m *DockerContainerMonitor) getContainerHealth(name string) string {
    cmd := exec.Command("docker", "inspect", "--format", "{{.State.Health.Status}}", name)
    output, err := cmd.Output()
    if err != nil {
        return "none"
    }
    return strings.TrimSpace(string(output))
}

func (m *DockerContainerMonitor) getContainerStartedAt(name string) time.Time {
    cmd := exec.Command("docker", "inspect", "--format", "{{.State.StartedAt}}", name)
    output, err := cmd.Output()
    if err != nil {
        return time.Now()
    }

    ts := strings.TrimSpace(string(output))
    t, _ := time.Parse(time.RFC3339, ts)
    return t
}

func (m *DockerContainerMonitor) getContainerExitCode(name string) int {
    cmd := exec.Command("docker", "inspect", "--format", "{{.State.ExitCode}}", name)
    output, err := cmd.Output()
    if err != nil {
        return -1
    }
    code, _ := strconv.Atoi(strings.TrimSpace(string(output)))
    return code
}

func (m *DockerContainerMonitor) getTagFromName(name string) string {
    parts := strings.Split(name, ":")
    if len(parts) >= 2 {
        return parts[len(parts)-1]
    }
    return "latest"
}

func (m *DockerContainerMonitor) parseTime(timeStr string) time.Time {
    // Parse "2 weeks ago" format
    t, _ := time.ParseDuration("0s")
    if strings.Contains(timeStr, "ago") {
        numStr := strings.TrimSuffix(strings.TrimSpace(timeStr), " ago")
        num, _ := strconv.Atoi(numStr)

        if strings.Contains(timeStr, "week") {
            t = time.Duration(num) * 7 * 24 * time.Hour
        } else if strings.Contains(timeStr, "day") {
            t = time.Duration(num) * 24 * time.Hour
        } else if strings.Contains(timeStr, "hour") {
            t = time.Duration(num) * time.Hour
        } else if strings.Contains(timeStr, "minute") {
            t = time.Duration(num) * time.Minute
        }
        return time.Now().Add(-t)
    }
    return time.Now()
}

func (m *DockerContainerMonitor) shouldWatchContainer(name string) bool {
    if len(m.config.WatchContainers) == 0 {
        return true
    }
    for _, n := range m.config.WatchContainers {
        if n == "*" || name == n || strings.HasPrefix(name, n) {
            return true
        }
    }
    return false
}

func (m *DockerContainerMonitor) shouldWatchImage(name string) bool {
    if len(m.config.WatchImages) == 0 {
        return true
    }
    for _, n := range m.config.WatchImages {
        if n == "*" || strings.Contains(name, n) {
            return true
        }
    }
    return false
}

func (m *DockerContainerMonitor) onContainerStarted(info *ContainerInfo) {
    if !m.config.SoundOnStart {
        return
    }
    key := fmt.Sprintf("start:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DockerContainerMonitor) onContainerStopped(info, lastInfo *ContainerInfo) {
    if !m.config.SoundOnStop {
        return
    }
    key := fmt.Sprintf("stop:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            volume := 0.4
            if info.ExitCode != 0 {
                volume = 0.5
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *DockerContainerMonitor) onContainerUnhealthy(info *ContainerInfo) {
    if !m.config.SoundOnHealth {
        return
    }
    key := fmt.Sprintf("unhealthy:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["health"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DockerContainerMonitor) onContainerHealthy(info *ContainerInfo) {
    // Optional: sound when recovered
}

func (m *DockerContainerMonitor) onImageUpdated(info *ImageInfo) {
    if !m.config.SoundOnImage {
        return
    }
    key := fmt.Sprintf("image:%s", info.Name)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["image"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DockerContainerMonitor) onContainerRemoved(info *ContainerInfo) {
    // Optional: sound when container removed
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
| macOS | Supported | Uses docker CLI |
| Linux | Supported | Uses docker CLI |
