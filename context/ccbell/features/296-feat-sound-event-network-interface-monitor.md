# Feature: Sound Event Network Interface Monitor

Play sounds for network interface state changes and connectivity events.

## Summary

Monitor network interface state changes, carrier detection, and link status, playing sounds for network connectivity events.

## Motivation

- Interface state awareness
- Connectivity change alerts
- Link failure detection
- Network configuration feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Interface Events

| Event | Description | Example |
|-------|-------------|---------|
| Interface Up | Interface enabled | en0 UP |
| Interface Down | Interface disabled | en0 DOWN |
| Carrier Change | Link status change | Cable plugged/unplugged |
| IP Assigned | New IP address | DHCP lease obtained |
| IP Released | IP address released | DHCP release |

### Configuration

```go
type NetworkInterfaceMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchInterfaces  []string          `json:"watch_interfaces"` // "en0", "eth0"
    SoundOnUp        bool              `json:"sound_on_up"`
    SoundOnDown      bool              `json:"sound_on_down"`
    SoundOnCarrier   bool              `json:"sound_on_carrier"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type NetworkInterfaceEvent struct {
    InterfaceName string
    State         string // "up", "down", "carrier"
    IPAddress     string
    MACAddress    string
    EventType     string
}
```

### Commands

```bash
/ccbell:netif status                 # Show network status
/ccbell:netif add en0                # Add interface to watch
/ccbell:netif remove en0
/ccbell:netif sound up <sound>
/ccbell:netif sound down <sound>
/ccbell:netif test                   # Test network sounds
```

### Output

```
$ ccbell:netif status

=== Sound Event Network Interface Monitor ===

Status: Enabled
Up Sounds: Yes
Down Sounds: Yes

Watched Interfaces: 2

[1] en0 (Wi-Fi)
    State: UP
    IP: 192.168.1.100
    MAC: aa:bb:cc:dd:ee:ff
    Carrier: Connected
    Sound: bundled:stop

[2] en1 (Thunderbolt)
    State: DOWN
    IP: --
    MAC: 11:22:33:44:55:66
    Carrier: Disconnected
    Sound: bundled:net-down

Recent Events:
  [1] en0: Interface Up (5 min ago)
       Connected to network
  [2] en1: Carrier Change (1 hour ago)
       Cable disconnected
  [3] en0: IP Assigned (2 hours ago)
       192.168.1.100

Sound Settings:
  Up: bundled:stop
  Down: bundled:net-down
  Carrier: bundled:stop

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Network interface monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Interface Monitor

```go
type NetworkInterfaceMonitor struct {
    config           *NetworkInterfaceMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    interfaceState   map[string]string
    lastStateChange  map[string]time.Time
}

func (m *NetworkInterfaceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]string)
    m.lastStateChange = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkInterfaceMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Snapshot initial state
    m.snapshotInterfaceStates()

    for {
        select {
        case <-ticker.C:
            m.checkInterfaceStates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkInterfaceMonitor) snapshotInterfaceStates() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinInterfaces()
    } else {
        m.snapshotLinuxInterfaces()
    }
}

func (m *NetworkInterfaceMonitor) snapshotDarwinInterfaces() {
    // Use ifconfig to get interface states
    cmd := exec.Command("ifconfig", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIfconfigOutput(string(output))
}

func (m *NetworkInterfaceMonitor) snapshotLinuxInterfaces() {
    // Read from /sys/class/net/*
    path := "/sys/class/net"
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !m.shouldWatchInterface(entry.Name()) {
            continue
        }

        m.checkLinuxInterface(entry.Name())
    }
}

func (m *NetworkInterfaceMonitor) checkInterfaceStates() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinInterfaces()
    } else {
        m.checkLinuxInterfaces()
    }
}

func (m *NetworkInterfaceMonitor) checkDarwinInterfaces() {
    cmd := exec.Command("ifconfig", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIfconfigOutput(string(output))
}

func (m *NetworkInterfaceMonitor) checkLinuxInterfaces() {
    path := "/sys/class/net"
    entries, err := os.ReadDir(path)
    if err != nil {
        return
    }

    for _, entry := range entries {
        if !m.shouldWatchInterface(entry.Name()) {
            continue
        }

        m.checkLinuxInterface(entry.Name())
    }
}

func (m *NetworkInterfaceMonitor) checkLinuxInterface(name string) {
    // Check operstate
    stateFile := filepath.Join("/sys/class/net", name, "operstate")
    data, err := os.ReadFile(stateFile)
    if err != nil {
        return
    }

    state := strings.TrimSpace(string(data))
    lastState := m.interfaceState[name]

    if lastState != "" && lastState != state {
        m.onInterfaceStateChange(name, state, lastState)
    }

    m.interfaceState[name] = state
}

func (m *NetworkInterfaceMonitor) parseIfconfigOutput(output string) {
    lines := strings.Split(output, "\n")
    currentInterface := ""

    for _, line := range lines {
        if strings.HasSuffix(line, ":") {
            currentInterface = strings.TrimSuffix(line, ":")
            continue
        }

        if currentInterface == "" {
            continue
        }

        // Check for UP/DOWN status
        if strings.Contains(line, "status:") {
            state := "down"
            if strings.Contains(line, "active") {
                state = "up"
            }

            lastState := m.interfaceState[currentInterface]
            if lastState != "" && lastState != state {
                m.onInterfaceStateChange(currentInterface, state, lastState)
            }

            m.interfaceState[currentInterface] = state
        }
    }
}

func (m *NetworkInterfaceMonitor) shouldWatchInterface(name string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, iface := range m.config.WatchInterfaces {
        if name == iface {
            return true
        }
    }

    return false
}

func (m *NetworkInterfaceMonitor) onInterfaceStateChange(name string, newState string, oldState string) {
    if newState == "up" {
        m.onInterfaceUp(name)
    } else if newState == "down" {
        m.onInterfaceDown(name)
    }
}

func (m *NetworkInterfaceMonitor) onInterfaceUp(name string) {
    if !m.config.SoundOnUp {
        return
    }

    sound := m.config.Sounds["up"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *NetworkInterfaceMonitor) onInterfaceDown(name string) {
    if !m.config.SoundOnDown {
        return
    }

    key := fmt.Sprintf("down:%s", name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *NetworkInterfaceMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastStateChange[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastStateChange[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ifconfig | System Tool | Free | macOS interface status |
| /sys/class/net/* | File | Free | Linux interface status |

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
| macOS | Supported | Uses ifconfig |
| Linux | Supported | Uses /sys/class/net |
| Windows | Not Supported | ccbell only supports macOS/Linux |
