# Feature: Sound Event Container Monitor

Play sounds for container status changes, startup, shutdown, and health events.

## Summary

Monitor Docker containers and other container runtimes for status changes, health check failures, and lifecycle events, playing sounds for container events.

## Motivation

- Container awareness
- Deployment tracking
- Health monitoring
- Restart detection
- Resource awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Container Events

| Event | Description | Example |
|-------|-------------|---------|
| Container Started | Container started | docker run |
| Container Stopped | Container stopped | exit code 0 |
| Container Crashed | Container crashed | exit code 1+ |
| Health Check Failed | Health check failed | unhealthy |
| Image Updated | New image pulled | pulled |
| Restart Count | Container restarted | restart |

### Configuration

```go
type ContainerMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchContainers   []string          `json:"watch_containers"` // "nginx", "*"
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnStop       bool              `json:"sound_on_stop"`
    SoundOnCrash      bool              `json:"sound_on_crash"`
    SoundOnHealthFail bool              `json:"sound_on_health_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 15 default
}
```

### Commands

```bash
/ccbell:container status             # Show container status
/ccbell:container add nginx          # Add container to watch
/ccbell:container sound start <sound>
/ccbell:container test               # Test container sounds
```

### Output

```
$ ccbell:container status

=== Sound Event Container Monitor ===

Status: Enabled
Watch Containers: all

Container Status:

[1] nginx (running) *** ACTIVE ***
    Image: nginx:latest
    Status: Up 2 hours
    Health: Healthy
    Restarts: 0
    Ports: 80, 443
    Sound: bundled:container-nginx *** ACTIVE ***

[2] postgres (running)
    Image: postgres:15
    Status: Up 2 hours
    Health: Healthy
    Restarts: 0
    Ports: 5432
    Sound: bundled:container-postgres

[3] redis (exited) *** STOPPED ***
    Image: redis:alpine
    Status: Exited (0) 5 min ago
    Health: N/A
    Restarts: 1
    Sound: bundled:container-redis *** STOPPED ***

[4] app-api (running) *** UNHEALTHY ***
    Image: app:latest
    Status: Up 1 hour
    Health: Unhealthy *** FAILED ***
    Restarts: 3
    Ports: 8080
    Sound: bundled:container-app *** FAILED ***

Recent Events:

[1] redis: Container Stopped (5 min ago)
       Exited with code 0
       Sound: bundled:container-stop
  [2] app-api: Health Check Failed (10 min ago)
       3 consecutive health check failures
       Sound: bundled:container-health-fail
  [3] app-api: Container Restarted (30 min ago)
       Restart count: 3
       Sound: bundled:container-crash
  [4] nginx: Container Started (2 hours ago)
       Container started successfully
       Sound: bundled:container-start

Container Statistics:
  Total Containers: 4
  Running: 3
  Stopped: 1
  Healthy: 3
  Unhealthy: 1

Sound Settings:
  Start: bundled:container-start
  Stop: bundled:container-stop
  Crash: bundled:container-crash
  Health Fail: bundled:container-health-fail

[Configure] [Add Container] [Test All]
```

---

## Audio Player Compatibility

Container monitoring doesn't play sounds directly:
- Monitoring feature using docker, podman, crictl
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
    Name        string
    Image       string
    Status      string // "running", "exited", "paused"
    Health      string // "healthy", "unhealthy", "starting"
    StartedAt   time.Time
    RestartCount int
    Ports       []string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| docker | System Tool | Free | Docker CLI |
| podman | System Tool | Free | Podman CLI |
| crictl | System Tool | Free | Container runtime CLI |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Platform detection](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L82) - GOOS-based detection

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses docker, podman |
| Linux | Supported | Uses docker, podman, crictl |
