# Feature: Sound Event Container Monitor

Play sounds for container events, crashes, and health status changes.

## Summary

Monitor Docker/Podman containers for crashes, restarts, health changes, and deployment events, playing sounds for container events.

## Motivation

- Container awareness
- Crash detection
- Health status alerts
- Deployment feedback
- Container orchestration awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Container Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Crashed | Container stopped unexpectedly | exit code 137 |
| Container Restarted | Container was restarted | restart count |
| Health Check Failed | Health check failed | unhealthy |
| Container Started | New container started | created/running |
| Image Updated | New image deployed | pulled |
| OOM Killed | Out of memory killed | oom killer |

### Configuration

```go
type ContainerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchContainers   []string          `json:"watch_containers"` // container names or "*" for all
    WatchImages       []string          `json:"watch_images"` // image names
    SoundOnCrash      bool              `json:"sound_on_crash"`
    SoundOnRestart    bool              `json:"sound_on_restart"`
    SoundOnHealthFail bool              `json:"sound_on_health_fail"`
    SoundOnStarted    bool              `json:"sound_on_started"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:container status            # Show container status
/ccbell:container add web           # Add container to watch
/ccbell:container sound crash <sound>
/ccbell:container test              # Test container sounds
```

### Output

```
$ ccbell:container status

=== Sound Event Container Monitor ===

Status: Enabled
Watch Containers: all

Container Status:

[1] web-app (docker)
    Status: RUNNING
    Image: nginx:latest
    Restarts: 0
    Health: HEALTHY
    Sound: bundled:container-web

[2] api-server (docker)
    Status: CRASHED *** CRASHED ***
    Image: node:18-alpine
    Restarts: 5
    Exit Code: 137 (OOM)
    Sound: bundled:container-api *** FAILED ***

[3] db-postgres (docker)
    Status: RUNNING
    Image: postgres:15
    Restarts: 0
    Health: HEALTHY
    Sound: bundled:container-db

Recent Events:

[1] api-server: Crashed (5 min ago)
       Exit code 137 (OOM killed)
       Sound: bundled:container-crash
  [2] api-server: Restarted (10 min ago)
       Restart count: 5
       Sound: bundled:container-restart
  [3] web-app: Health Check Failed (1 hour ago)
       Health check timeout
       Sound: bundled:container-health-fail

Container Statistics:
  Total Containers: 3
  Running: 2
  Crashed: 1
  Restarts Today: 5

Sound Settings:
  Crash: bundled:container-crash
  Restart: bundled:container-restart
  Health Fail: bundled:container-health-fail
  Started: bundled:container-started

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Container monitoring doesn't play sounds directly:
- Monitoring feature using docker/podman CLI
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Container Monitor

```go
type ContainerMonitor struct {
    config        *ContainerMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    containerState map[string]*ContainerInfo
    lastEventTime map[string]time.Time
}

type ContainerInfo struct {
    Name       string
    ID         string
    Runtime    string // "docker", "podman"
    Status     string // "running", "exited", "crashed"
    ExitCode   int
    Restarts   int
    Health     string // "healthy", "unhealthy", "starting"
    Image      string
    StartedAt  time.Time
}

func (m *ContainerMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.containerState = make(map[string]*ContainerInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ContainerMonitor) monitor() {
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

func (m *ContainerMonitor) snapshotContainerState() {
    m.checkContainerState()
}

func (m *ContainerMonitor) checkContainerState() {
    // Check Docker containers
    m.checkDockerContainers()

    // Check Podman containers
    m.checkPodmanContainers()
}

func (m *ContainerMonitor) checkDockerContainers() {
    cmd := exec.Command("docker", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.ID}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        info := m.parseDockerOutput(line)
        if info != nil {
            m.processContainerStatus(info)
        }
    }
}

func (m *ContainerMonitor) parseDockerOutput(line string) *ContainerInfo {
    parts := strings.Split(line, "|")
    if len(parts) < 3 {
        return nil
    }

    info := &ContainerInfo{
        Name:    parts[0],
        ID:      parts[2],
        Runtime: "docker",
    }

    status := parts[1]
    if strings.Contains(status, "Up") {
        info.Status = "running"
    } else if strings.Contains(status, "Restarting") {
        info.Status = "running"
        info.Restarts = m.extractRestartCount(status)
    } else if strings.Contains(status, "Exited") {
        info.Status = "exited"
        info.ExitCode = m.extractExitCode(status)
        info.Restarts = m.extractRestartCount(status)
    }

    // Get health status
    healthCmd := exec.Command("docker", "inspect", "--format", "{{.State.Health.Status}}", info.Name)
    healthOutput, _ := healthCmd.Output()
    info.Health = strings.TrimSpace(string(healthOutput))

    return info
}

func (m *ContainerMonitor) extractExitCode(status string) int {
    re := regexp.MustEach(`Exit (\d+)`)
    matches := re.FindStringSubmatch(status)
    if len(matches) >= 2 {
        code, _ := strconv.Atoi(matches[1])
        return code
    }
    return -1
}

func (m *ContainerMonitor) extractRestartCount(status string) int {
    re := regexp.MustEach(`\((\d+)\)`)
    matches := re.FindStringSubmatch(status)
    if len(matches) >= 2 {
        count, _ := strconv.Atoi(matches[1])
        return count
    }
    return 0
}

func (m *ContainerMonitor) checkPodmanContainers() {
    cmd := exec.Command("podman", "ps", "-a", "--format", "{{.Names}}|{{.Status}}|{{.ID}}")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        info := m.parsePodmanOutput(line)
        if info != nil {
            m.processContainerStatus(info)
        }
    }
}

func (m *ContainerMonitor) parsePodmanOutput(line string) *ContainerInfo {
    parts := strings.Split(line, "|")
    if len(parts) < 3 {
        return nil
    }

    info := &ContainerInfo{
        Name:    parts[0],
        ID:      parts[2],
        Runtime: "podman",
    }

    status := parts[1]
    if strings.Contains(status, "Running") {
        info.Status = "running"
    } else {
        info.Status = "exited"
    }

    return info
}

func (m *ContainerMonitor) processContainerStatus(info *ContainerInfo) {
    if !m.shouldWatchContainer(info.Name) {
        return
    }

    lastInfo := m.containerState[info.Name]

    if lastInfo == nil {
        m.containerState[info.Name] = info
        if info.Status == "running" && m.config.SoundOnStarted {
            m.onContainerStarted(info)
        }
        return
    }

    // Check for crash
    if info.Status == "exited" && lastInfo.Status == "running" {
        if info.ExitCode != 0 {
            if m.config.SoundOnCrash && m.shouldAlert(info.Name+"crash", 5*time.Minute) {
                m.onContainerCrashed(info)
            }
        }
    }

    // Check for restart
    if info.Restarts > lastInfo.Restarts {
        if m.config.SoundOnRestart && m.shouldAlert(info.Name+"restart", 2*time.Minute) {
            m.onContainerRestarted(info)
        }
    }

    // Check for health failure
    if info.Health == "unhealthy" && lastInfo.Health != "unhealthy" {
        if m.config.SoundOnHealthFail && m.shouldAlert(info.Name+"health", 5*time.Minute) {
            m.onHealthCheckFailed(info)
        }
    }

    m.containerState[info.Name] = info
}

func (m *ContainerMonitor) shouldWatchContainer(name string) bool {
    for _, container := range m.config.WatchContainers {
        if container == "*" || container == name {
            return true
        }
    }
    return false
}

func (m *ContainerMonitor) onContainerCrashed(info *ContainerInfo) {
    sound := m.config.Sounds["crash"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ContainerMonitor) onContainerRestarted(info *ContainerInfo) {
    sound := m.config.Sounds["restart"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *ContainerMonitor) onContainerStarted(info *ContainerInfo) {
    sound := m.config.Sounds["started"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *ContainerMonitor) onHealthCheckFailed(info *ContainerInfo) {
    sound := m.config.Sounds["health_fail"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *ContainerMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| docker | System Tool | Free | Container runtime |
| podman | System Tool | Free | Container runtime |

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
| macOS | Supported | Uses docker, podman CLI |
| Linux | Supported | Uses docker, podman CLI |
