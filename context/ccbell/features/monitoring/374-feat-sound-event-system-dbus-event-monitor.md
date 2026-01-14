# Feature: Sound Event System D-Bus Event Monitor

Play sounds for D-Bus system events and service notifications.

## Summary

Monitor D-Bus system bus events, service activations, and method calls, playing sounds for D-Bus events.

## Motivation

- D-Bus awareness
- Service activation alerts
- System event feedback
- Hardware events via D-Bus
- Session integration

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### D-Bus Events

| Event | Description | Example |
|-------|-------------|---------|
| Service Activated | Service started via D-Bus | NetworkManager |
| Service Lost | Service disappeared | Connection lost |
| Name Owner Changed | Bus name owner changed | New owner |
| Property Changed | Service property changed | Network up |
| Method Called | D-Bus method called | Request made |

### Configuration

```go
type DbusEventMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchServices     []string          `json:"watch_services"` // "org.freedesktop.NetworkManager", "*"
    WatchNames        []string          `json:"watch_names"` // "org.freedesktop.NetworkManager1"
    SoundOnActivate   bool              `json:"sound_on_activate"`
    SoundOnLost       bool              `json:"sound_on_lost"]
    SoundOnProperty   bool              `json:"sound_on_property"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type DbusEventEvent struct {
    Service    string
    Interface  string
    Member     string
    Sender     string
    Destination string
    Path       string
    EventType  string // "activate", "lost", "property", "method"
}
```

### Commands

```bash
/ccbell:dbus status                   # Show D-Bus status
/ccbell:dbus add org.freedesktop.NetworkManager  # Add service
/ccbell:dbus remove org.freedesktop.NetworkManager
/ccbell:dbus sound activate <sound>
/ccbell:dbus sound lost <sound>
/ccbell:dbus test                     # Test D-Bus sounds
```

### Output

```
$ ccbell:dbus status

=== Sound Event System D-Bus Event Monitor ===

Status: Enabled
Activate Sounds: Yes
Lost Sounds: Yes
Property Sounds: Yes

Watched Services: 2
Watched Names: 3

Active Services:
  [1] org.freedesktop.NetworkManager (owned by :1.45)
      Status: ACTIVE
      Properties: 12
      Sound: bundled:dbus-network

  [2] org.freedesktop.systemd1 (owned by root)
      Status: ACTIVE
      Properties: 45
      Sound: bundled:dbus-systemd

Recent D-Bus Events:
  [1] org.freedesktop.NetworkManager (5 min ago)
       Property Changed: WirelessEnabled -> true
  [2] org.freedesktop.NetworkManager (10 min ago)
       Service Activated
  [3] org.freedesktop.upower (1 hour ago)
       Service Lost

D-Bus Statistics:
  Active Services: 25
  Events Today: 45
  Service Activations: 12

Sound Settings:
  Activate: bundled:dbus-activate
  Lost: bundled:dbus-lost
  Property: bundled:dbus-property

[Configure] [Add Service] [Test All]
```

---

## Audio Player Compatibility

D-Bus monitoring doesn't play sounds directly:
- Monitoring feature using dbus-monitor
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System D-Bus Event Monitor

```go
type DbusEventMonitor struct {
    config          *DbusEventMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    serviceState    map[string]*ServiceInfo
    lastEventTime   map[string]time.Time
}

type ServiceInfo struct {
    Name       string
    Owner      string
    Status     string // "active", "waiting", "unknown"
    Properties int
    LastSeen   time.Time
}

func (m *DbusEventMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.serviceState = make(map[string]*ServiceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *DbusEventMonitor) monitor() {
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

func (m *DbusEventMonitor) snapshotServiceState() {
    // List available services on system bus
    m.listSystemBusServices()
}

func (m *DbusEventMonitor) checkServiceState() {
    // Check for service state changes
    m.listSystemBusServices()
}

func (m *DbusEventMonitor) listSystemBusServices() {
    cmd := exec.Command("dbus-send", "--system",
        "--dest=org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus.ListNames")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentServices := m.parseListNamesOutput(string(output))

    for name, info := range currentServices {
        lastInfo := m.serviceState[name]
        if lastInfo == nil {
            m.serviceState[name] = info
            if m.shouldWatchService(name) {
                m.onServiceActivated(name, info)
            }
            continue
        }

        // Check for ownership changes
        if lastInfo.Owner != info.Owner {
            if info.Owner == "" {
                m.onServiceLost(name, lastInfo)
            }
        }

        m.serviceState[name] = info
    }

    // Check for removed services
    for name, lastInfo := range m.serviceState {
        if _, exists := currentServices[name]; !exists {
            delete(m.serviceState, name)
            if m.shouldWatchService(name) {
                m.onServiceLost(name, lastInfo)
            }
        }
    }
}

func (m *DbusEventMonitor) parseListNamesOutput(output string) map[string]*ServiceInfo {
    services := make(map[string]*ServiceInfo)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "string") {
            // Parse: "string "org.freedesktop.DBus""
            re := regexp.MustCompile(`string "([^"]+)"`)
            match := re.FindStringSubmatch(line)
            if match != nil {
                name := match[1]

                if !m.shouldWatchService(name) {
                    continue
                }

                // Get owner
                ownerCmd := exec.Command("dbus-send", "--system",
                    "--dest=org.freedesktop.DBus",
                    fmt.Sprintf("/org/freedesktop/DBus/org/freedesktop/DBus"),
                    "org.freedesktop.DBus.GetNameOwner",
                    fmt.Sprintf("string:%s", name))
                ownerOutput, err := ownerCmd.Output()
                owner := ""
                if err == nil {
                    ownerRe := regexp.MustCompile(`string "([^"]+)"`)
                    ownerMatch := ownerRe.FindStringSubmatch(string(ownerOutput))
                    if ownerMatch != nil {
                        owner = ownerMatch[1]
                    }
                }

                services[name] = &ServiceInfo{
                    Name:     name,
                    Owner:    owner,
                    Status:   "active",
                    LastSeen: time.Now(),
                }
            }
        }
    }

    return services
}

func (m *DbusEventMonitor) shouldWatchService(name string) bool {
    if len(m.config.WatchServices) == 0 && len(m.config.WatchNames) == 0 {
        return true
    }

    for _, s := range m.config.WatchServices {
        if s == "*" || name == s || strings.HasPrefix(name, s) {
            return true
        }
    }

    for _, n := range m.config.WatchNames {
        if name == n {
            return true
        }
    }

    return false
}

func (m *DbusEventMonitor) onServiceActivated(name string, info *ServiceInfo) {
    if !m.config.SoundOnActivate {
        return
    }

    key := fmt.Sprintf("activate:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["activate"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *DbusEventMonitor) onServiceLost(name string, info *ServiceInfo) {
    if !m.config.SoundOnLost {
        return
    }

    key := fmt.Sprintf("lost:%s", name)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["lost"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *DbusEventMonitor) onPropertyChanged(name string, property string) {
    if !m.config.SoundOnProperty {
        return
    }

    key := fmt.Sprintf("property:%s:%s", name, property)
    if m.shouldAlert(key, 10*time.Second) {
        sound := m.config.Sounds["property"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *DbusEventMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| dbus-send | System Tool | Free | D-Bus messaging |
| dbus-monitor | System Tool | Free | D-Bus monitoring |

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
| macOS | Not Supported | No native D-Bus |
| Linux | Supported | Uses dbus-send, dbus-monitor |
