# Feature: Sound Event System Service Dependency Monitor

Play sounds for service dependency failures, cascade stops, and service restarts.

## Summary

Monitor systemd services and their dependencies for state changes, failures, and cascade effects, playing sounds for service dependency events.

## Motivation

- Dependency chain awareness
- Service failure detection
- Cascade stop alerts
- Service restart tracking
- System health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Service Dependency Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Service is running | nginx |
| Service Stopped | Service stopped | nginx |
| Service Failed | Error occurred | mysql |
| Dependency Met | All deps running | webapp |
| Dependency Broken | Dep failed | database |
| Cascade Stop | All stopped | due to mysql |
| Service Restarted | Reloaded | nginx |

### Configuration

```go
type ServiceDependencyMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServices     []string          `json:"watch_services"` // "nginx", "mysql", "*"
    WatchGroups       []string          `json:"watch_groups"` // "multi-user.target"
    SoundOnStart      bool              `json:"sound_on_start"`
    SoundOnStop       bool              `json:"sound_on_stop"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    SoundOnCascade    bool              `json:"sound_on_cascade"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:services status              # Show service status
/ccbell:services add nginx           # Add service to watch
/ccbell:services remove nginx
/ccbell:services sound start <sound>
/ccbell:services sound stop <sound>
/ccbell:services test                # Test service sounds
```

### Output

```
$ ccbell:services status

=== Sound Event System Service Dependency Monitor ===

Status: Enabled
Start Sounds: Yes
Stop Sounds: Yes
Failed Sounds: Yes
Cascade Sounds: Yes

Watched Services: 5
Watched Targets: 2

Service Status:

[1] nginx (webserver)
    Status: ACTIVE
    SubStatus: running
    Active Since: Jan 14, 2026 02:30:00 (6 hours)
    Dependencies: network.target (MET)
    Dependents: docker-app.service (MET)
    Sound: bundled:services-nginx

[2] mysql (database)
    Status: ACTIVE
    SubStatus: running
    Active Since: Jan 14, 2026 02:00:00 (6 hours)
    Dependencies: network.target (MET), syslog.target (MET)
    Dependents: api-app.service (MET), web-app.service (MET)
    Sound: bundled:services-mysql

[3] api-app (application)
    Status: ACTIVE
    SubStatus: running
    Active Since: Jan 14, 2026 02:31:00 (5 hours)
    Dependencies: mysql.service (MET)
    Dependents: none
    Sound: bundled:services-api

[4] redis (cache)
    Status: FAILED *** FAILED ***
    Active Since: -
    Dependencies: network.target (MET)
    Dependents: api-app.service (BROKEN)
    Exit Code: exit-code
    Error: failed
    Sound: bundled:services-redis *** FAILED ***

[5] docker-app (container)
    Status: ACTIVATING
    SubStatus: auto-restart
    Active Since: -
    Dependencies: docker.service (MET)
    Dependents: none
    Sound: bundled:services-docker

Target Status:

[1] multi-user.target
    Status: ACTIVE
    Active Since: Jan 14, 2026 02:00:00 (6 hours)
    Units: 45 active, 3 inactive

[2] graphical.target
    Status: ACTIVE
    Active Since: Jan 14, 2026 02:00:00 (6 hours)
    Units: 50 active, 2 inactive

Dependency Tree:

  network.target
    |- network-online.target
    |- nginx.service
    |   |- docker-app.service
    |- mysql.service
        |- api-app.service
            |- redis.service (FAILED)

Recent Events:
  [1] redis: Service Failed (1 hour ago)
       Exit code: failed
  [2] api-app: Dependency Broken (1 hour ago)
       redis.service dependency failed
  [3] nginx: Service Started (6 hours ago)
       Auto-started by multi-user.target
  [4] docker-app: Cascade Start (6 hours ago)
       Started due to nginx.service

Service Statistics:
  Total Services: 5
  Active: 4
  Failed: 1
  Dependency Broken: 1

Sound Settings:
  Start: bundled:services-start
  Stop: bundled:services-stop
  Failed: bundled:services-failed
  Cascade: bundled:services-cascade

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

Service monitoring doesn't play sounds directly:
- Monitoring feature using systemctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Service Dependency Monitor

```go
type ServiceDependencyMonitor struct {
    config          *ServiceDependencyMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serviceState    map[string]*ServiceInfo
    lastEventTime   map[string]time.Time
}

type ServiceInfo struct {
    Name          string
    Status        string // "active", "failed", "activating", "deactivating", "unknown"
    SubStatus     string
    ActiveSince   time.Time
    MainPID       int
    ExecMainExit  int
    Dependencies  []string
    Dependents    []string
    DependencyStatus map[string]string // "met", "broken", "unknown"
}

func (m *ServiceDependencyMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]*ServiceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *ServiceDependencyMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotServiceState()

    for {
        select {
        case <-ticker.C:
            m.checkServiceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *ServiceDependencyMonitor) snapshotServiceState() {
    m.checkServiceState()
}

func (m *ServiceDependencyMonitor) checkServiceState() {
    for _, service := range m.config.WatchServices {
        info := m.getServiceInfo(service)

        if info != nil {
            m.processServiceStatus(service, info)
        }
    }

    // Also check for newly started services
    allServices := m.listAllServices()
    for _, info := range allServices {
        if m.shouldWatchService(info.Name) {
            if _, exists := m.serviceState[info.Name]; !exists {
                m.processServiceStatus(info.Name, info)
            }
        }
    }
}

func (m *ServiceDependencyMonitor) listAllServices() []*ServiceInfo {
    var services []*ServiceInfo

    cmd := exec.Command("systemctl", "list-units", "--type=service",
        "--no-pager", "--no-legend")
    output, err := cmd.Output()
    if err != nil {
        return services
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        name := parts[0]
        load := parts[1]
        active := parts[2]
        sub := parts[3]

        info := &ServiceInfo{
            Name:      name,
            Status:    active,
            SubStatus: sub,
        }

        if load != "loaded" {
            info.Status = "unknown"
        }

        services = append(services, info)
    }

    return services
}

func (m *ServiceDependencyMonitor) getServiceInfo(name string) *ServiceInfo {
    // Ensure .service suffix
    if !strings.HasSuffix(name, ".service") {
        name = name + ".service"
    }

    cmd := exec.Command("systemctl", "show", name,
        "--no-pager", "--property=Id,ActiveState,SubState,MainPID,ExecMainCode,ActiveEnterTimestamp")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &ServiceInfo{
        Name: strings.TrimSuffix(name, ".service"),
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if strings.HasPrefix(line, "Id=") {
            info.Name = strings.TrimPrefix(line, "Id=")
        } else if strings.HasPrefix(line, "ActiveState=") {
            info.Status = strings.TrimPrefix(line, "ActiveState=")
        } else if strings.HasPrefix(line, "SubState=") {
            info.SubStatus = strings.TrimPrefix(line, "SubState=")
        } else if strings.HasPrefix(line, "MainPID=") {
            pidStr := strings.TrimPrefix(line, "MainPID=")
            info.MainPID, _ = strconv.Atoi(pidStr)
        } else if strings.HasPrefix(line, "ExecMainCode=") {
            codeStr := strings.TrimPrefix(line, "ExecMainCode=")
            info.ExecMainExit, _ = strconv.Atoi(codeStr)
        } else if strings.HasPrefix(line, "ActiveEnterTimestamp=") {
            ts := strings.TrimPrefix(line, "ActiveEnterTimestamp=")
            info.ActiveSince, _ = time.Parse("Mon 2006-01-02 15:04:05 MST", ts)
        }
    }

    // Get dependencies
    info.Dependencies = m.getServiceDependencies(name)
    info.Dependents = m.getServiceDependents(name)

    // Check dependency status
    info.DependencyStatus = make(map[string]string)
    for _, dep := range info.Dependencies {
        depInfo := m.getServiceInfo(dep)
        if depInfo != nil && depInfo.Status == "active" {
            info.DependencyStatus[dep] = "met"
        } else {
            info.DependencyStatus[dep] = "broken"
        }
    }

    return info
}

func (m *ServiceDependencyMonitor) getServiceDependencies(name string) []string {
    cmd := exec.Command("systemctl", "list-dependencies", name,
        "--no-pager", "--reverse")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    var deps []string
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if strings.HasSuffix(line, ".service") ||
           strings.HasSuffix(line, ".socket") ||
           strings.HasSuffix(line, ".target") {
            name := strings.TrimSpace(line)
            if name != "" {
                deps = append(deps, name)
            }
        }
    }

    return deps
}

func (m *ServiceDependencyMonitor) getServiceDependents(name string) []string {
    cmd := exec.Command("systemctl", "list-dependencies", name,
        "--no-pager")
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    var deps []string
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if strings.HasSuffix(line, ".service") ||
           strings.HasSuffix(line, ".socket") {
            name := strings.TrimSpace(line)
            if name != "" {
                deps = append(deps, name)
            }
        }
    }

    return deps
}

func (m *ServiceDependencyMonitor) processServiceStatus(name string, info *ServiceInfo) {
    lastInfo := m.serviceState[name]

    if lastInfo == nil {
        m.serviceState[name] = info

        if info.Status == "active" && m.config.SoundOnStart {
            m.onServiceStarted(info)
        } else if info.Status == "failed" && m.config.SoundOnFailed {
            m.onServiceFailed(info)
        }
        return
    }

    // Check for status transitions
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "active":
            if m.config.SoundOnStart {
                m.onServiceStarted(info)
            }
        case "failed":
            if m.config.SoundOnFailed {
                m.onServiceFailed(info)
            }
        case "inactive", "deactivating":
            if m.config.SoundOnStop {
                m.onServiceStopped(info, lastInfo)
            }
        }
    }

    // Check for dependency status changes
    m.checkDependencyChanges(name, lastInfo, info)

    // Check for cascade effects
    if info.Status == "failed" {
        m.checkCascadeEffects(info)
    }

    m.serviceState[name] = info
}

func (m *ServiceDependencyMonitor) checkDependencyChanges(name string, lastInfo, info *ServiceInfo) {
    for dep, status := range info.DependencyStatus {
        lastStatus, exists := lastInfo.DependencyStatus[dep]
        if !exists {
            continue
        }

        if lastStatus == "met" && status == "broken" {
            // Dependency just broke
            m.onDependencyBroken(info, dep)
        } else if lastStatus == "broken" && status == "met" {
            // Dependency recovered
        }
    }
}

func (m *ServiceDependencyMonitor) checkCascadeEffects(failedService *ServiceInfo) {
    // Check if any services depend on the failed service
    for name, info := range m.serviceState {
        if name == failedService.Name {
            continue
        }

        depStatus, exists := info.DependencyStatus[failedService.Name+".service"]
        if exists && depStatus == "broken" {
            // This service has a broken dependency
            if info.Status == "inactive" || info.Status == "failed" {
                // It stopped due to the cascade
                if m.config.SoundOnCascade {
                    m.onCascadeStop(info, failedService)
                }
            }
        }
    }
}

func (m *ServiceDependencyMonitor) shouldWatchService(name string) bool {
    if len(m.config.WatchServices) == 0 {
        return true
    }

    baseName := name
    if strings.HasSuffix(name, ".service") {
        baseName = strings.TrimSuffix(name, ".service")
    }

    for _, s := range m.config.WatchServices {
        if s == "*" || baseName == s || strings.Contains(baseName, s) {
            return true
        }
    }

    return false
}

func (m *ServiceDependencyMonitor) onServiceStarted(info *ServiceInfo) {
    key := fmt.Sprintf("start:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["start"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ServiceDependencyMonitor) onServiceStopped(info, lastInfo *ServiceInfo) {
    // Check if this is a cascade stop
    for dep := range lastInfo.DependencyStatus {
        depInfo := m.serviceState[dep]
        if depInfo != nil && depInfo.Status == "failed" {
            // This was a cascade stop
            return
        }
    }

    key := fmt.Sprintf("stop:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["stop"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *ServiceDependencyMonitor) onServiceFailed(info *ServiceInfo) {
    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            volume := 0.5
            if info.ExecMainExit != 0 {
                volume = 0.6
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *ServiceDependencyMonitor) onDependencyBroken(info *ServiceInfo, dep string) {
    depName := strings.TrimSuffix(dep, ".service")
    key := fmt.Sprintf("dep-broken:%s:%s", info.Name, depName)

    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["dependency"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ServiceDependencyMonitor) onCascadeStop(info, failedService *ServiceInfo) {
    key := fmt.Sprintf("cascade:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["cascade"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *ServiceDependencyMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| systemctl | System Tool | Free | Systemd control |
| systemd | System Tool | Free | Service management |

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
| macOS | Not Supported | No systemd |
| Linux | Supported | Uses systemctl |
