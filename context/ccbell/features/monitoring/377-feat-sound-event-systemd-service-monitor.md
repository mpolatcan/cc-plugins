# Feature: Sound Event Systemd Service Monitor

Play sounds for systemd service state changes, unit failures, and restart events.

## Summary

Monitor systemd services for active/inactive states, failures, and restarts, playing sounds for service events.

## Motivation

- Service health awareness
- Failure detection
- Restart notifications
- Service dependency alerts
- System reliability

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Systemd Service Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Started | Unit activated | httpd start |
| Service Stopped | Unit deactivated | httpd stop |
| Service Failed | Unit failed | crash |
| Service Restarted | Unit restarted | reload |
| Service Reloaded | Config reloaded | reload |
| Service Timeout | Start timeout | hung |

### Configuration

```go
type SystemdServiceMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchUnits        []string          `json:"watch_units"` // "nginx.service", "*"
    WatchTypes        []string          `json:"watch_types"` // "active", "failed", "reloading"
    SoundOnActive     bool              `json:"sound_on_active"`
    SoundOnInactive   bool              `json:"sound_on_inactive"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnRestart    bool              `json:"sound_on_restart"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:systemd status                # Show systemd status
/ccbell:systemd add nginx.service     # Add unit to watch
/ccbell:systemd remove nginx.service
/ccbell:systemd sound active <sound>
/ccbell:systemd sound fail <sound>
/ccbell:systemd test                  # Test systemd sounds
```

### Output

```
$ ccbell:systemd status

=== Sound Event Systemd Service Monitor ===

Status: Enabled
Active Sounds: Yes
Fail Sounds: Yes
Restart Sounds: Yes

Watched Units: 3

[1] nginx.service (Nginx HTTP Server)
    Status: active (running)
    Since: 2 days ago
    Restarts: 0
    Sound: bundled:systemd-nginx

[2] postgresql.service (PostgreSQL Database)
    Status: active (running)
    Since: 1 week ago
    Restarts: 1
    Sound: bundled:systemd-postgres

[3] docker.service (Docker Application Container Engine)
    Status: inactive
    Since: 1 hour ago
    Restarts: 5
    Sound: bundled:systemd-docker

Recent Events:
  [1] docker.service: Service Stopped (5 min ago)
       Manual stop
  [2] postgresql.service: Service Restarted (1 hour ago)
       Reload configuration
  [3] nginx.service: Service Started (2 days ago)
       Boot start

Failed Units:
  [1] backup.service (2 hours ago)
       Exit code: exit_code

Systemd Statistics:
  Active Units: 45
  Failed Units: 1
  Total Restarts: 12

Sound Settings:
  Active: bundled:systemd-active
  Inactive: bundled:systemd-inactive
  Fail: bundled:systemd-fail
  Restart: bundled:systemd-restart

[Configure] [Add Unit] [Test All]
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
type SystemdServiceMonitor struct {
    config          *SystemdServiceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    unitState       map[string]*UnitInfo
    lastEventTime   map[string]time.Time
    lastCheckTime   time.Time
}

type UnitInfo struct {
    Name       string
    Status     string // "active", "inactive", "failed", "reloading"
    ActiveSince time.Time
    SubState   string // "running", "dead", "failed"
    Restarts   int
    LastEvent  time.Time
}

func (m *SystemdServiceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.unitState = make(map[string]*UnitInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *SystemdServiceMonitor) monitor() {
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

func (m *SystemdServiceMonitor) snapshotUnitState() {
    for _, unit := range m.config.WatchUnits {
        m.checkUnit(unit)
    }
}

func (m *SystemdServiceMonitor) checkUnitState() {
    for _, unit := range m.config.WatchUnits {
        m.checkUnit(unit)
    }

    // Check for failed units if enabled
    if m.config.SoundOnFail {
        m.checkFailedUnits()
    }
}

func (m *SystemdServiceMonitor) checkUnit(unitName string) {
    cmd := exec.Command("systemctl", "show", unitName,
        "--property=Id,Description,ActiveState,SubState,ActiveEnterTimestamp,RestartsCount,MainExitCode")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    info := m.parseUnitOutput(unitName, string(output))
    if info == nil {
        return
    }

    lastInfo := m.unitState[unitName]
    if lastInfo == nil {
        m.unitState[unitName] = info
        if info.Status == "active" {
            m.onUnitActive(info)
        }
        return
    }

    // Check for state changes
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "active":
            m.onUnitActive(info)
        case "inactive":
            m.onUnitInactive(info)
        case "failed":
            m.onUnitFailed(info)
        case "reloading":
            m.onUnitReloaded(info)
        }
    }

    // Check for restarts
    if info.Restarts > lastInfo.Restarts {
        m.onUnitRestarted(info, info.Restarts-lastInfo.Restarts)
    }

    m.unitState[unitName] = info
}

func (m *SystemdServiceMonitor) checkFailedUnits() {
    cmd := exec.Command("systemctl", "--failed", "--no-pager")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "● ") || strings.HasPrefix(line, "* ") {
            unitName := strings.TrimPrefix(strings.TrimPrefix(line, "● "), "* ")
            unitName = strings.TrimSpace(unitName)

            if m.shouldWatchUnit(unitName) {
                key := fmt.Sprintf("failed:%s", unitName)
                if m.shouldAlert(key, 1*time.Hour) {
                    sound := m.config.Sounds["fail"]
                    if sound != "" {
                        m.player.Play(sound, 0.6)
                    }
                }
            }
        }
    }
}

func (m *SystemdServiceMonitor) parseUnitOutput(unitName string, output string) *UnitInfo {
    info := &UnitInfo{Name: unitName}

    re := regexp.MustCompile(`ActiveState=(\w+)`)
    match := re.FindStringSubmatch(output)
    if match != nil {
        info.Status = match[1]
    }

    re = regexp.MustCompile(`SubState=(\w+)`)
    match = re.FindStringSubmatch(output)
    if match != nil {
        info.SubState = match[1]
    }

    re = regexp.MustCompile(`RestartsCount=(\d+)`)
    match = re.FindStringSubmatch(output)
    if match != nil {
        info.Restarts, _ = strconv.Atoi(match[1])
    }

    re = regexp.MustCompile(`ActiveEnterTimestamp=(.+)`)
    match = re.FindStringSubmatch(output)
    if match != nil {
        ts := match[1]
        // Parse timestamp
        t, err := time.Parse("Mon 2006-01-02 15:04:05 MST", ts)
        if err == nil {
            info.ActiveSince = t
        }
    }

    info.LastEvent = time.Now()

    return info
}

func (m *SystemdServiceMonitor) onUnitActive(info *UnitInfo) {
    if !m.config.SoundOnActive {
        return
    }

    key := fmt.Sprintf("active:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["active"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemdServiceMonitor) onUnitInactive(info *UnitInfo) {
    if !m.config.SoundOnInactive {
        return
    }

    key := fmt.Sprintf("inactive:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["inactive"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SystemdServiceMonitor) onUnitFailed(info *UnitInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("failed:%s", info.Name)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *SystemdServiceMonitor) onUnitRestarted(info *UnitInfo, count int) {
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

func (m *SystemdServiceMonitor) onUnitReloaded(info *UnitInfo) {
    // Optional: sound when unit reloads
}

func (m *SystemdServiceMonitor) shouldWatchUnit(unitName string) bool {
    if len(m.config.WatchUnits) == 0 {
        return true
    }

    for _, u := range m.config.WatchUnits {
        if u == "*" || u == unitName {
            return true
        }
    }

    return false
}

func (m *SystemdServiceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| systemd | System Service | Free | Service manager |

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
