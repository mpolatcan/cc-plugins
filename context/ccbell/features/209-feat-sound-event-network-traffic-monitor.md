# Feature: Sound Event Network Traffic Monitor

Play sounds for network activity and traffic events.

## Summary

Monitor network traffic, bandwidth usage, and connection events, playing sounds when thresholds are exceeded or significant events occur.

## Motivation

- Bandwidth usage awareness
- Large download completion
- Network congestion alerts
- Connection state changes

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Network Events

| Event | Description | Example |
|-------|-------------|---------|
| High Traffic | Bandwidth above threshold | Above 100 Mbps |
| Download Complete | Large download finished | 1GB file done |
| Connection Up | Network interface up | WiFi connected |
| Connection Down | Network interface down | Ethernet unplugged |
| Slow Network | High latency detected | Ping > 500ms |

### Configuration

```go
type NetworkTrafficMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    Interfaces     []string          `json:"interfaces"` // "en0" or all
    HighThreshold  int               `json:"high_threshold_mbps"` // 100 default
    PollInterval   int               `json:"poll_interval_sec"` // 30 default
    Sounds         map[string]string `json:"sounds"`
    NotifyComplete bool              `json:"notify_download_complete"`
}

type NetworkTrafficStatus struct {
    Interface   string
    RXBytes     uint64
    TXBytes     uint64
    RXSpeed     float64 // Mbps
    TXSpeed     float64 // Mbps
    Latency     time.Duration
    Connected   bool
}
```

### Commands

```bash
/ccbell:network status            # Show network status
/ccbell:network add en0           # Add interface to watch
/ccbell:network remove en0        # Remove interface
/ccbell:network threshold <mbps>  # Set threshold
/ccbell:network sound high <sound>
/ccbell:network sound connected <sound>
/ccbell:network test              # Test network sounds
```

### Output

```
$ ccbell:network status

=== Sound Event Network Traffic Monitor ===

Status: Enabled
High Traffic Threshold: 100 Mbps
Poll Interval: 30s

Interfaces: 2

[1] en0 (WiFi)
  Status: Connected
  Download: 45.2 Mbps
  Upload: 12.8 Mbps
  Latency: 25ms
  Status: Normal

[2] en1 (Thunderbolt)
  Status: Disconnected
  Download: 0 Mbps
  Upload: 0 Mbps
  Status: Disconnected

Sound Settings:
  High Traffic: bundled:stop
  Connected: bundled:stop
  Disconnected: bundled:stop
  Download Complete: bundled:stop

[Configure] [Test All]
```

---

## Audio Player Compatibility

Network traffic monitoring doesn't play sounds directly:
- Monitoring feature using system commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Traffic Monitor

```go
type NetworkTrafficMonitor struct {
    config     *NetworkTrafficMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastStats  map[string]*NetworkTrafficStatus
}

func (m *NetworkTrafficMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStats = make(map[string]*NetworkTrafficStatus)
    go m.monitor()
}

func (m *NetworkTrafficMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkTraffic()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkTrafficMonitor) checkTraffic() {
    interfaces := m.getInterfaces()

    for _, iface := range interfaces {
        status := m.getTrafficStatus(iface)
        if status != nil {
            m.evaluateStatus(iface, status)
        }
    }
}

func (m *NetworkTrafficMonitor) getInterfaces() []string {
    if len(m.config.Interfaces) > 0 {
        return m.config.Interfaces
    }

    // Get all interfaces
    ifaces, _ := net.Interfaces()
    var names []string
    for _, iface := range ifaces {
        if iface.Flags&net.FlagUp != 0 {
            names = append(names, iface.Name)
        }
    }
    return names
}

func (m *NetworkTrafficMonitor) getTrafficStatus(iface string) *NetworkTrafficStatus {
    status := &NetworkTrafficStatus{Interface: iface}

    if runtime.GOOS == "darwin" {
        return m.getMacOSTrafficStatus(iface, status)
    }

    if runtime.GOOS == "linux" {
        return m.getLinuxTrafficStatus(iface, status)
    }

    return status
}

func (m *NetworkTrafficMonitor) getMacOSTrafficStatus(iface string, status *NetworkTrafficStatus) *NetworkTrafficStatus {
    // macOS: nettop or ifconfig
    cmd := exec.Command("nettop", "-J", "bytes,interface", "-t", "en0")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to ifconfig
        cmd = exec.Command("ifconfig", iface)
        output, err = cmd.Output()
        if err != nil {
            return nil
        }
    }

    // Parse output to get bytes
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, iface) {
            parts := strings.Fields(line)
            for i, part := range parts {
                if part == "RX" && i+1 < len(parts) {
                    rx, _ := strconv.ParseUint(parts[i+1], 10, 64)
                    status.RXBytes = rx
                }
                if part == "TX" && i+1 < len(parts) {
                    tx, _ := strconv.ParseUint(parts[i+1], 10, 64)
                    status.TXBytes = tx
                }
            }
        }
    }

    status.Connected = true

    // Calculate speed
    lastStatus := m.lastStats[iface]
    if lastStatus != nil {
        interval := float64(m.config.PollInterval)
        status.RXSpeed = float64(status.RXBytes-lastStatus.RXBytes) * 8 / interval / 1e6
        status.TXSpeed = float64(status.TXBytes-lastStatus.TXBytes) * 8 / interval / 1e6
    }

    // Check latency
    status.Latency = m.checkLatency()

    return status
}

func (m *NetworkTrafficMonitor) getLinuxTrafficStatus(iface string, status *NetworkTrafficStatus) *NetworkTrafficStatus {
    // Linux: /proc/net/dev
    data, err := os.ReadFile("/proc/net/dev")
    if err != nil {
        return nil
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, iface+":") {
            parts := strings.Fields(line)
            if len(parts) >= 16 {
                rx, _ := strconv.ParseUint(parts[1], 10, 64)
                tx, _ := strconv.ParseUint(parts[9], 10, 64)
                status.RXBytes = rx
                status.TXBytes = tx
            }
        }
    }

    // Check if interface exists
    if status.RXBytes == 0 && status.TXBytes == 0 {
        status.Connected = false
    } else {
        status.Connected = true
    }

    // Calculate speed
    lastStatus := m.lastStats[iface]
    if lastStatus != nil {
        interval := float64(m.config.PollInterval)
        status.RXSpeed = float64(status.RXBytes-lastStatus.RXBytes) * 8 / interval / 1e6
        status.TXSpeed = float64(status.TXBytes-lastStatus.TXBytes) * 8 / interval / 1e6
    }

    status.Latency = m.checkLatency()

    return status
}

func (m *NetworkTrafficMonitor) checkLatency() time.Duration {
    // Ping google.com
    cmd := exec.Command("ping", "-c", "1", "-W", "1", "8.8.8.8")
    start := time.Now()
    cmd.Run()
    return time.Since(start)
}

func (m *NetworkTrafficMonitor) evaluateStatus(iface string, status *NetworkTrafficStatus) {
    lastStatus := m.lastStats[iface]
    m.lastStats[iface] = status

    // Check connection state change
    if lastStatus != nil {
        if status.Connected && !lastStatus.Connected {
            m.playSound("connected")
        } else if !status.Connected && lastStatus.Connected {
            m.playSound("disconnected")
        }

        // Check high traffic
        totalSpeed := status.RXSpeed + status.TXSpeed
        lastSpeed := lastStatus.RXSpeed + lastStatus.TXSpeed

        if totalSpeed >= float64(m.config.HighThreshold) &&
           lastSpeed < float64(m.config.HighThreshold) {
            m.playSound("high")
        }

        // Check slow network
        if status.Latency > 500*time.Millisecond &&
           lastStatus.Latency < 500*time.Millisecond {
            m.playSound("slow")
        }
    }
}

func (m *NetworkTrafficMonitor) playSound(event string) {
    sound := m.config.Sounds[event]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| nettop | System Tool | Free | macOS network stats |
| ifconfig | System Tool | Free | macOS network info |
| /proc/net/dev | File System | Free | Linux network stats |
| ping | System Tool | Free | Latency measurement |

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
| macOS | Supported | Uses nettop/ifconfig |
| Linux | Supported | Uses /proc/net/dev |
| Windows | Not Supported | ccbell only supports macOS/Linux |
