# Feature: Sound Event Service Restart Monitor

Play sounds for systemd service status changes, restarts, and failure events.

## Summary

Monitor systemd services for status changes, automatic restarts, and failure detection, playing sounds for service events.

## Motivation

- Service awareness
- Failure detection
- Restart tracking
- Dependency management
- System reliability

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
| Service Started | Service activated | started |
| Service Stopped | Service deactivated | stopped |
| Service Restarted | Service restarted | restarted |
| Service Failed | Service failed | failed |
| Service Reloaded | Config reloaded | reloaded |
| Auto Restart | Auto-restart triggered | auto-restart |

### Configuration

```go
type ServiceRestartMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchServices    []string          `json:"watch_services"` // "nginx", "*"
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnRestart   bool              `json:"sound_on_restart"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 15 default
}
```

### Commands

```bash
/ccbell:service status              # Show service status
/ccbell:service add nginx           # Add service to watch
/ccbell:service sound fail <sound>
/ccbell:service test                # Test service sounds
```

### Output

```
$ ccbell:service status

=== Sound Event Service Restart Monitor ===

Status: Enabled
Watch Services: all

Service Status:

[1] nginx (active) *** ACTIVE ***
    Status: active (running)
    Since: 2 hours ago
    Main PID: 1234 (nginx)
    Restarts: 0
    Sound: bundled:service-nginx *** ACTIVE ***

[2] postgresql (active)
    Status: active (running)
    Since: 2 hours ago
    Main PID: 5678 (postgres)
    Restarts: 0
    Sound: bundled:service-postgres

[3] redis (inactive) *** STOPPED ***
    Status: inactive (dead)
    Since: 5 min ago
    Main PID: N/A
    Restarts: 1
    Sound: bundled:service-redis *** STOPPED ***

[4] app-api (failed) *** FAILED ***
    Status: failed (Result: exit-code)
    Since: 10 min ago
    Main PID: 9999 (crashed)
    Restarts: 5
    Last Failure: Signal: SIGSEGV
    Sound: bundled:service-app *** FAILED ***

Recent Events:

[1] redis: Service Stopped (5 min ago)
       Unit stopped successfully
       Sound: bundled:service-stop
  [2] app-api: Service Restarted (10 min ago)
       Automatic restart triggered (attempt 5)
       Sound: bundled:service-restart
  [3] app-api: Service Failed (10 min ago)
       Process crashed with exit code 139
       Sound: bundled:service-fail
  [4] nginx: Service Started (2 hours ago)
       Unit started successfully
       Sound: bundled:service-start

Service Statistics:
  Total Services: 4
  Active: 2
  Inactive: 1
  Failed: 1
  Total Restarts: 6

Sound Settings:
  Start: bundled:service-start
  Stop: bundled:service-stop
  Restart: bundled:service-restart
  Fail: bundled:service-fail

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Service monitoring doesn't play sounds directly:
- Monitoring feature using systemctl, journalctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Service Restart Monitor

```go
type ServiceRestartMonitor struct {
    config        *ServiceRestartMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    serviceState  map[string]*ServiceInfo
    lastEventTime map[string]time.Time
}

type ServiceInfo struct {
    Name          string
    Status        string // "active", "inactive", "failed", "activating"
    ActiveState   string
    SubState      string
    MainPID       int
    Restarts      int
    LastStartedAt time.Time
    LastFailMsg   string
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| systemctl | System Tool | Free | systemd service management |
| journalctl | System Tool | Free | systemd journal |
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
| Linux | Supported | Uses systemctl, journalctl |
