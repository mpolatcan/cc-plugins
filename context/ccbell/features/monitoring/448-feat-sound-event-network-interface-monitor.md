# Feature: Sound Event Network Interface Monitor

Play sounds for network interface state changes, connection threshold breaches, and traffic anomalies.

## Summary

Monitor network interfaces for status changes, connection counts, bandwidth usage, and connectivity issues, playing sounds for network events.

## Motivation

- Network awareness
- Connectivity monitoring
- Bandwidth alerting
- Connection limits
- Network failure detection

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
| Interface Up | Interface activated | en0 up |
| Interface Down | Interface deactivated | en0 down |
| High Connections | Too many connections | > 1000 |
| Bandwidth Spike | Traffic surge | > 100 Mbps |
| Packet Loss | Detected packet loss | > 5% |
| DNS Failure | DNS resolution failed | no DNS |

### Configuration

```go
type NetworkInterfaceMonitorConfig struct {
    Enabled              bool              `json:"enabled"`
    WatchInterfaces      []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    ConnectionThreshold  int               `json:"connection_threshold"` // 1000 default
    BandwidthThresholdMB int               `json:"bandwidth_threshold_mb"` // 100 default
    PacketLossThreshold  int               `json:"packet_loss_threshold"` // 5 default
    SoundOnUp            bool              `json:"sound_on_up"`
    SoundOnDown          bool              `json:"sound_on_down"`
    SoundOnHighConn      bool              `json:"sound_on_high_conn"`
    SoundOnBandwidth     bool              `json:"sound_on_bandwidth"`
    Sounds               map[string]string `json:"sounds"`
    PollInterval         int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:network status              # Show network status
/ccbell:network add en0             # Add interface to watch
/ccbell:network threshold conn 1000 # Set connection threshold
/ccbell:network sound up <sound>
/ccbell:network test                # Test network sounds
```

### Output

```
$ ccbell:network status

=== Sound Event Network Interface Monitor ===

Status: Enabled
Connection Threshold: 1000
Bandwidth Threshold: 100 MB/s

Interface Status:

[1] en0 (Wi-Fi)
    Status: UP
    IP: 192.168.1.100
    Connections: 234
    Download: 15 MB/s
    Upload: 5 MB/s
    Sound: bundled:network-wifi

[2] en1 (Thunderbolt)
    Status: UP
    IP: 10.0.0.50
    Connections: 45
    Download: 2 MB/s
    Upload: 1 MB/s
    Sound: bundled:network-eth

[3] lo0 (Loopback)
    Status: UP
    IP: 127.0.0.1
    Connections: 892 *** HIGH ***
    Download: 150 MB/s *** SPIKE ***
    Upload: 150 MB/s *** SPIKE ***
    Sound: bundled:network-lo *** WARNING ***

Recent Events:

[1] lo0: High Connections (5 min ago)
       892 connections > 1000 threshold
       Sound: bundled:network-highconn
  [2] en0: Interface Up (1 hour ago)
       Connected to network
       Sound: bundled:network-up
  [3] en1: Bandwidth Spike (2 hours ago)
       120 MB/s > 100 MB/s threshold
       Sound: bundled:network-bandwidth

Network Statistics:
  Total Interfaces: 3
  Connected: 3
  High Connections: 1

Sound Settings:
  Up: bundled:network-up
  Down: bundled:network-down
  High Conn: bundled:network-highconn
  Bandwidth: bundled:network-bandwidth

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Network monitoring doesn't play sounds directly:
- Monitoring feature using ifconfig, netstat, ss
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Network Interface Monitor

```go
type NetworkInterfaceMonitor struct {
    config          *NetworkInterfaceMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    interfaceState  map[string]*InterfaceInfo
    lastEventTime   map[string]time.Time
}

type InterfaceInfo struct {
    Name         string
    Status       string // "up", "down"
    IP           string
    Connections  int
    DownloadBps  int64
    UploadBps    int64
    LastCheck    time.Time
}

func (m *NetworkInterfaceMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]*InterfaceInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkInterfaceMonitor) monitor() {
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

func (m *NetworkInterfaceMonitor) snapshotInterfaceState() {
    m.checkInterfaceState()
}

func (m *NetworkInterfaceMonitor) checkInterfaceState() {
    cmd := exec.Command("ifconfig", "-a")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    interfaces := m.parseIfconfig(string(output))
    for _, info := range interfaces {
        if m.shouldWatchInterface(info.Name) {
            m.processInterfaceStatus(info)
        }
    }
}

func (m *NetworkInterfaceMonitor) parseIfconfig(output string) []*InterfaceInfo {
    var interfaces []*InterfaceInfo
    lines := strings.Split(output, "\n")

    var currentInfo *InterfaceInfo

    for _, line := range lines {
        if strings.HasPrefix(line, " ") || strings.HasPrefix(line, "\t") {
            if currentInfo != nil {
                currentInfo.Lines = append(currentInfo.Lines, line)
            }
        } else if strings.Contains(line, ":") {
            parts := strings.SplitN(line, ":", 2)
            name := strings.TrimSpace(parts[0])

            if currentInfo != nil {
                interfaces = append(interfaces, currentInfo)
            }

            currentInfo = &InterfaceInfo{
                Name:  name,
                Lines: []string{},
            }
        }
    }

    if currentInfo != nil {
        interfaces = append(interfaces, currentInfo)
    }

    // Get connection counts and bandwidth
    for _, info := range interfaces {
        m.getConnectionCount(info)
        m.getBandwidth(info)
    }

    return interfaces
}

func (m *NetworkInterfaceMonitor) getConnectionCount(info *InterfaceInfo) {
    // Use ss or netstat for connection count
    cmd := exec.Command("ss", "-tn", "src", info.Name+":")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to netstat
        cmd = exec.Command("netstat", "-an", "-p", "tcp", "-f", "inet")
        output, _ = cmd.Output()
    }

    lines := strings.Split(string(output), "\n")
    // Count established connections
    for _, line := range lines {
        if strings.Contains(line, "ESTABLISHED") {
            info.Connections++
        }
    }
}

func (m *NetworkInterfaceMonitor) getBandwidth(info *InterfaceInfo) {
    // Read from /proc/net/dev on Linux
    data, err := os.ReadFile("/proc/net/dev")
    if err == nil {
        lines := strings.Split(string(data), "\n")
        for _, line := range lines {
            if strings.HasPrefix(info.Name+":", line) {
                fields := strings.Fields(line)
                if len(fields) >= 10 {
                    // bytes received
                    rxBytes, _ := strconv.ParseInt(fields[1], 10, 64)
                    // bytes transmitted
                    txBytes, _ := strconv.ParseInt(fields[9], 10, 64)
                    info.DownloadBps = rxBytes
                    info.UploadBps = txBytes
                }
            }
        }
    }
}

func (m *NetworkInterfaceMonitor) processInterfaceStatus(info *InterfaceInfo) {
    lastInfo := m.interfaceState[info.Name]

    if lastInfo == nil {
        m.interfaceState[info.Name] = info

        if info.Status == "up" && m.config.SoundOnUp {
            m.onInterfaceUp(info)
        } else if info.Status == "down" && m.config.SoundOnDown {
            m.onInterfaceDown(info)
        }
        return
    }

    // Check for status change
    if info.Status != lastInfo.Status {
        if info.Status == "up" && m.config.SoundOnUp {
            m.onInterfaceUp(info)
        } else if info.Status == "down" && m.config.SoundOnDown {
            m.onInterfaceDown(info)
        }
    }

    // Check for high connections
    if info.Connections >= m.config.ConnectionThreshold {
        if lastInfo == nil || info.Connections > lastInfo.Connections {
            if m.config.SoundOnHighConn && m.shouldAlert(info.Name+"conn", 5*time.Minute) {
                m.onHighConnections(info)
            }
        }
    }

    // Check for bandwidth spike (Mbps)
    downloadMbps := (info.DownloadBps * 8) / (1024 * 1024)
    uploadMbps := (info.UploadBps * 8) / (1024 * 1024)

    if downloadMbps >= int64(m.config.BandwidthThresholdMB) || uploadMbps >= int64(m.config.BandwidthThresholdMB) {
        if m.config.SoundOnBandwidth && m.shouldAlert(info.Name+"bw", 5*time.Minute) {
            m.onBandwidthSpike(info, downloadMbps, uploadMbps)
        }
    }

    m.interfaceState[info.Name] = info
}

func (m *NetworkInterfaceMonitor) shouldWatchInterface(name string) bool {
    for _, iface := range m.config.WatchInterfaces {
        if iface == "*" || iface == name {
            return true
        }
    }
    return false
}

func (m *NetworkInterfaceMonitor) onInterfaceUp(info *InterfaceInfo) {
    key := fmt.Sprintf("up:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["up"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkInterfaceMonitor) onInterfaceDown(info *InterfaceInfo) {
    key := fmt.Sprintf("down:%s", info.Name)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["down"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkInterfaceMonitor) onHighConnections(info *InterfaceInfo) {
    sound := m.config.Sounds["high_conn"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *NetworkInterfaceMonitor) onBandwidthSpike(info *InterfaceInfo, download, upload int64) {
    sound := m.config.Sounds["bandwidth"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *NetworkInterfaceMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ifconfig | System Tool | Free | Network interface config |
| ss | System Tool | Free | Socket statistics |
| netstat | System Tool | Free | Network statistics |

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
| macOS | Supported | Uses ifconfig, netstat |
| Linux | Supported | Uses ifconfig, ss, /proc/net/dev |
