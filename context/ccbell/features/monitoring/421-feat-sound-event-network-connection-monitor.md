# Feature: Sound Event Network Connection Monitor

Play sounds for network connection changes, interface up/down events, and connection status.

## Summary

Monitor network interfaces and connections for status changes, playing sounds for network events.

## Motivation

- Network awareness
- Interface status alerts
- Connection quality tracking
- Offline/online detection
- Network change feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Network Connection Events

| Event | Description | Example |
|-------|-------------|---------|
| Interface Up | Network up | en0 online |
| Interface Down | Network down | en0 offline |
| New Connection | New TCP connection | ESTABLISHED |
| Connection Lost | Connection dropped | TIME_WAIT |
| DNS Resolved | Host resolved | example.com |
| High Latency | Latency > threshold | > 100ms |

### Configuration

```go
type NetworkConnectionMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchInterfaces   []string          `json:"watch_interfaces"` // "en0", "eth0", "*"
    WatchHosts        []string          `json:"watch_hosts"` // "8.8.8.8", "example.com"
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 100 default
    SoundOnUp         bool              `json:"sound_on_up"`
    SoundOnDown       bool              `json:"sound_on_down"`
    SoundOnConnection bool              `json:"sound_on_connection"`
    SoundOnLatency    bool              `json:"sound_on_latency"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:network status               # Show network status
/ccbell:network add en0              # Add interface to watch
/ccbell:network latency 100          # Set latency threshold
/ccbell:network sound up <sound>
/ccbell:network sound down <sound>
/ccbell:network test                 # Test network sounds
```

### Output

```
$ ccbell:network status

=== Sound Event Network Connection Monitor ===

Status: Enabled
Up Sounds: Yes
Down Sounds: Yes
Latency Threshold: 100ms

Network Interfaces:

[1] en0 (Wi-Fi)
    Status: UP
    IP: 192.168.1.100
    Speed: 450 Mbps
    Signal: 85%
    Sound: bundled:network-wifi

[2] en1 (USB Ethernet)
    Status: DOWN
    IP: -
    Speed: -
    Sound: bundled:network-eth *** OFFLINE ***

[3] lo0 (Loopback)
    Status: UP
    IP: 127.0.0.1
    Speed: Local
    Sound: bundled:network-loopback

Connection Status:

  8.8.8.8: REACHABLE (12ms)
  example.com: REACHABLE (45ms)
  api.example.com: REACHABLE (32ms)

Recent Network Events:
  [1] en1: Interface Down (2 hours ago)
       USB Ethernet disconnected
  [2] en0: Interface Up (3 hours ago)
       Wi-Fi reconnected
  [3] 8.8.8.8: High Latency (1 day ago)
       150ms > 100ms threshold

Network Statistics:
  Interface Changes Today: 3
  Avg Latency: 25ms
  Packet Loss: 0%

Sound Settings:
  Up: bundled:network-up
  Down: bundled:network-down
  Latency: bundled:network-latency
  Connection: bundled:network-connected

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Network monitoring doesn't play sounds directly:
- Monitoring feature using ifconfig/ip/netstat
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Connection Monitor

```go
type NetworkConnectionMonitor struct {
    config          *NetworkConnectionMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    interfaceState  map[string]*InterfaceInfo
    lastEventTime   map[string]time.Time
}

type InterfaceInfo struct {
    Name       string
    Status     string // "up", "down", "unknown"
    IPAddress  string
    MACAddress string
    Speed      string
    MTU        int
}

func (m *NetworkConnectionMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]*InterfaceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkConnectionMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotInterfaceState()

    for {
        select {
        case <-ticker.C:
            m.checkInterfaceState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkConnectionMonitor) snapshotInterfaceState() {
    m.checkInterfaceState()
}

func (m *NetworkConnectionMonitor) checkInterfaceState() {
    interfaces := m.listInterfaces()

    for _, iface := range interfaces {
        if !m.shouldWatchInterface(iface.Name) {
            continue
        }
        m.processInterfaceStatus(iface)
    }
}

func (m *NetworkConnectionMonitor) listInterfaces() []*InterfaceInfo {
    if runtime.GOOS == "darwin" {
        return m.listDarwinInterfaces()
    }
    return m.listLinuxInterfaces()
}

func (m *NetworkConnectionMonitor) listLinuxInterfaces() []*InterfaceInfo {
    var interfaces []*InterfaceInfo

    cmd := exec.Command("ip", "-o", "link", "show")
    output, err := cmd.Output()
    if err != nil {
        return interfaces
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        name := strings.TrimSpace(parts[0])
        details := strings.TrimSpace(parts[1])

        iface := &InterfaceInfo{
            Name: name,
        }

        // Check if up or down
        if strings.Contains(details, "UP") {
            iface.Status = "up"
        } else if strings.Contains(details, "LOWER_UP") {
            iface.Status = "up"
        } else {
            iface.Status = "down"
        }

        // Extract MAC address
        macRe := regexp.MustEach(`link/ether ([0-9a-f:]+)`)
        matches := macRe.FindStringSubmatch(details)
        if len(matches) >= 2 {
            iface.MACAddress = matches[1]
        }

        // Get IP address
        cmd := exec.Command("ip", "-o", "addr", "show", name)
        ipOutput, _ := cmd.Output()
        ipLines := strings.Split(string(ipOutput), "\n")
        for _, ipLine := range ipLines {
            ipRe := regexp.MustEach(`inet ([\d.]+)`)
            ipMatches := ipRe.FindStringSubmatch(ipLine)
            if len(ipMatches) >= 2 {
                iface.IPAddress = ipMatches[1]
                break
            }
        }

        interfaces = append(interfaces, iface)
    }

    return interfaces
}

func (m *NetworkConnectionMonitor) listDarwinInterfaces() []*InterfaceInfo {
    var interfaces []*InterfaceInfo

    cmd := exec.Command("ifconfig", "-a")
    output, err := cmd.Output()
    if err != nil {
        return interfaces
    }

    lines := strings.Split(string(output), "\n")
    currentName := ""

    for _, line := range lines {
        line = strings.TrimSpace(line)

        if strings.HasSuffix(line, ":") {
            currentName = strings.TrimSuffix(line, ":")
            continue
        }

        if currentName == "" {
            continue
        }

        iface := &InterfaceInfo{
            Name: currentName,
        }

        if strings.Contains(line, "status: active") {
            iface.Status = "up"
        } else if strings.Contains(line, "status: inactive") {
            iface.Status = "down"
        }

        // Extract IP
        ipRe := regexp.MustEach(`inet ([\d.]+)`)
        matches := ipRe.FindStringSubmatch(line)
        if len(matches) >= 2 {
            iface.IPAddress = matches[1]
        }

        // Extract MAC
        etherRe := regexp.MustEach(`ether ([0-9a-f:]+)`)
        etherMatches := etherRe.FindStringSubmatch(line)
        if len(etherMatches) >= 2 {
            iface.MACAddress = etherMatches[1]
        }

        interfaces = append(interfaces, iface)
    }

    return interfaces
}

func (m *NetworkConnectionMonitor) shouldWatchInterface(name string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, iface := range m.config.WatchInterfaces {
        if iface == "*" || name == iface {
            return true
        }
    }

    return false
}

func (m *NetworkConnectionMonitor) processInterfaceStatus(iface *InterfaceInfo) {
    lastInfo := m.interfaceState[iface.Name]

    if lastInfo == nil {
        m.interfaceState[iface.Name] = iface
        if iface.Status == "up" && m.config.SoundOnUp {
            m.onInterfaceUp(iface)
        }
        return
    }

    // Check for status changes
    if iface.Status != lastInfo.Status {
        if iface.Status == "up" {
            if m.config.SoundOnUp {
                m.onInterfaceUp(iface)
            }
        } else if iface.Status == "down" {
            if m.config.SoundOnDown {
                m.onInterfaceDown(iface)
            }
        }
    }

    m.interfaceState[iface.Name] = iface
}

func (m *NetworkConnectionMonitor) checkHostReachability() {
    for _, host := range m.config.WatchHosts {
        latency := m.pingHost(host)
        if latency > 0 && latency > int64(m.config.LatencyThreshold) {
            if m.config.SoundOnLatency {
                m.onHighLatency(host, latency)
            }
        }
    }
}

func (m *NetworkConnectionMonitor) pingHost(host string) int64 {
    var countFlag string
    var timeoutFlag string

    if runtime.GOOS == "darwin" {
        countFlag = "-c"
        timeoutFlag = "-t"
    } else {
        countFlag = "-c"
        timeoutFlag = "-w"
    }

    cmd := exec.Command("ping", countFlag, "1", timeoutFlag, "2", host)
    start := time.Now()
    err := cmd.Run()
    latency := time.Since(start).Milliseconds()

    if err != nil {
        return -1
    }

    return latency
}

func (m *NetworkConnectionMonitor) onInterfaceUp(iface *InterfaceInfo) {
    key := fmt.Sprintf("up:%s", iface.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["up"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkConnectionMonitor) onInterfaceDown(iface *InterfaceInfo) {
    key := fmt.Sprintf("down:%s", iface.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkConnectionMonitor) onHighLatency(host string, latency int64) {
    key := fmt.Sprintf("latency:%s", host)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["latency"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkConnectionMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ip | System Tool | Free | Network configuration (Linux) |
| ifconfig | System Tool | Free | Network configuration (macOS) |
| ping | System Tool | Free | Host reachability |

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
| macOS | Supported | Uses ifconfig, ping |
| Linux | Supported | Uses ip, ping |
