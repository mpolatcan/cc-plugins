# Feature: Sound Event Systemd Service Monitor

Play sounds for systemd service state changes and unit events.

## Summary

Monitor systemd service status, unit failures, and service restarts, playing sounds for systemd service events.

## Motivation

- Service awareness
- Failure detection
- Restart alerts
- Dependency tracking
- Service health feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Systemd Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Service started | nginx started |
| Service Stopped | Service stopped | mysql stopped |
| Service Restarted | Service restarted | sshd restarted |
| Service Failed | Service failed | httpd failed |
| Service Enabled | Service enabled | docker enabled |
| Service Disabled | Service disabled | firewalld disabled |
| Job Queued | Job queued | restart job queued |
| Job Failed | Job failed | start job failed |

### Configuration

```go
type SystemdMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchServices    []string          `json:"watch_services"` // "nginx", "mysql", "*"
    SoundOnStart     bool              `json:"sound_on_start"`
    SoundOnStop      bool              `json:"sound_on_stop"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    SoundOnEnable    bool              `json:"sound_on_enable"`
    SoundOnDisable   bool              `json:"sound_on_disable"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}

type SystemdEvent struct {
    Unit      string
    ActiveState string // "active", "inactive", "failed", "activating", "deactivating"
    SubState  string // "running", "dead", "failed", "start", "stop"
    UnitType  string // "service", "socket", "timer"
    EventType string // "start", "stop", "restart", "fail", "enable", "disable"
}
```

### Commands

```bash
/ccbell:systemd status                # Show systemd status
/ccbell:systemd add nginx             # Add service to watch
/ccbell:systemd remove nginx
/ccbell:systemd sound start <sound>
/ccbell:systemd sound fail <sound>
/ccbell:systemd test                  # Test systemd sounds
```

### Output

```
$ ccbell:systemd status

=== Sound Event Systemd Service Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Fail Sounds: Yes

Watched Services: 3

[1] nginx.service
    Active: ACTIVE
    SubState: RUNNING
    Description: A high performance web server
    Sound: bundled:systemd-start

[2] mysql.service
    Active: ACTIVE
    SubState: RUNNING
    Description: MySQL Database Server
    Sound: bundled:systemd-db

[3] docker.service
    Active: FAILED
    SubState: FAILED
    Description: Docker Application Container Engine
    Sound: bundled:systemd-fail

Recent Events:
  [1] docker.service: Service Failed (5 min ago)
       Exit code: 137
  [2] nginx.service: Service Restarted (10 min ago)
       Configuration reloaded
  [3] mysql.service: Service Started (1 hour ago)
       Boot completed

Systemd Statistics:
  Total watched: 3
  Active: 2
  Failed: 1

Sound Settings:
  Start: bundled:systemd-start
  Stop: bundled:systemd-stop
  Fail: bundled:systemd-fail

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Systemd monitoring doesn't play sounds directly:
- Monitoring feature using systemctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Systemd Service Monitor

```go
type SystemdMonitor struct {
    config         *SystemdMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    unitState      map[string]*UnitInfo
    lastEventTime  map[string]time.Time
}

type UnitInfo struct {
    Name        string
    Description string
    ActiveState string
    SubState    string
    UnitType    string
    LoadState   string
    ActiveEnter time.Time
}

func (m *SystemdMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.unitState = make(map[string]*UnitInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemdMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotUnitState()

    for {
        select {
        case <-ticker.C:
            m.checkUnitState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemdMonitor) snapshotUnitState() {
    m.checkUnitState()
}

func (m *SystemdMonitor) checkUnitState() {
    var services []string

    if len(m.config.WatchServices) > 0 && m.config.WatchServices[0] != "*" {
        services = m.config.WatchServices
    } else {
        // Get all services
        services = m.getAllServices()
    }

    for _, service := range services {
        info := m.getUnitInfo(service)
        if info == nil {
            continue
        }

        lastInfo := m.unitState[service]
        if lastInfo == nil {
            m.unitState[service] = info
            // Only alert on first load if already active
            if info.ActiveState == "active" {
                m.onUnitStarted(service, info)
            }
            continue
        }

        // Check for state changes
        if lastInfo.ActiveState != info.ActiveState {
            if info.ActiveState == "active" && lastInfo.ActiveState != "active" {
                m.onUnitStarted(service, info)
            } else if info.ActiveState == "inactive" && lastInfo.ActiveState == "active" {
                m.onUnitStopped(service, info, lastInfo)
            } else if info.ActiveState == "failed" {
                m.onUnitFailed(service, info)
            }
        }

        m.unitState[service] = info
    }
}

func (m *SystemdMonitor) getAllServices() []string {
    cmd := exec.Command("systemctl", "list-units", "--type=service", "--no-pager", "-o", "name")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    lines := strings.Split(string(output), "\n")
    var services []string

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line != "" && strings.HasSuffix(line, ".service") {
            services = append(services, strings.TrimSuffix(line, ".service"))
        }
    }

    return services
}

func (m *SystemdMonitor) getUnitInfo(name string) *UnitInfo {
    fullName := name
    if !strings.HasSuffix(name, ".service") {
        fullName = name + ".service"
    }

    cmd := exec.Command("systemctl", "show", fullName, "--no-pager",
        "--property=Id,Description,ActiveState,SubState,LoadState,Type,ActiveEnterTimestamp")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &UnitInfo{Name: name}

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, "=", 2)
        if len(parts) != 2 {
            continue
        }

        switch parts[0] {
        case "Description":
            info.Description = parts[1]
        case "ActiveState":
            info.ActiveState = parts[1]
        case "SubState":
            info.SubState = parts[1]
        case "LoadState":
            info.LoadState = parts[1]
        case "Type":
            info.UnitType = parts[1]
        case "ActiveEnterTimestamp":
            if parts[1] != "" {
                t, _ := time.Parse("Mon 2006-01-02 15:04:05 MST", parts[1])
                info.ActiveEnter = t
            }
        }
    }

    if info.LoadState != "loaded" {
        return nil
    }

    return info
}

func (m *SystemdMonitor) onUnitStarted(name string, info *UnitInfo) {
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

func (m *SystemdMonitor) onUnitStopped(name string, info *UnitInfo, last *UnitInfo) {
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

func (m *SystemdMonitor) onUnitFailed(name string, info *UnitInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemdMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| systemctl | System Tool | Free | Systemd management |
| systemd | System Service | Free | Service management |

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
| macOS | Not Supported | No native systemd |
| Linux | Supported | Uses systemctl |
