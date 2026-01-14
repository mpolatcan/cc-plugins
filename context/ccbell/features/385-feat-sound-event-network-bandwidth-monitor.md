# Feature: Sound Event Network Bandwidth Monitor

Play sounds for bandwidth thresholds, data transfer milestones, and network congestion.

## Summary

Monitor network interface bandwidth usage, data transfer volumes, and speed thresholds, playing sounds for bandwidth events.

## Motivation

- Data cap awareness
- Network congestion alerts
- Large transfer tracking
- Bandwidth throttling detection
- Network health monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Network Bandwidth Events

| Event | Description | Example |
|-------|-------------|---------|
| High Bandwidth | Speed > threshold | > 100 Mbps |
| Data Milestone | GB transferred | 10GB |
| Low Speed | Speed < threshold | < 1 Mbps |
| Congestion Detected | Packet loss high | > 5% |
| Quota Warning | Near data cap | 90% used |
| Transfer Complete | Large transfer done | sync done |

### Configuration

```go
type NetworkBandwidthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchInterfaces   []string          `json:"watch_interfaces"` // "eth0", "en0", "*"
    HighSpeedThreshold int              `json:"high_speed_mbps"` // 100 default
    LowSpeedThreshold  int              `json:"low_speed_kbps"` // 1000 default
    MilestonesGB      []int             `json:"milestones_gb"` // [1, 5, 10, 50]
    DataQuotaGB       int               `json:"data_quota_gb"` // 1000 default
    SoundOnHighSpeed  bool              `json:"sound_on_high_speed"`
    SoundOnMilestone  bool              `json:"sound_on_milestone"`
    SoundOnLowSpeed   bool              `json:"sound_on_low_speed"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:bandwidth status               # Show bandwidth status
/ccbell:bandwidth add eth0             # Add interface to watch
/ccbell:bandwidth threshold 100        # Set high speed threshold
/ccbell:bandwidth milestones 10 50 100 # Set data milestones
/ccbell:bandwidth sound high <sound>
/ccbell:bandwidth sound milestone <sound>
/ccbell:bandwidth test                 # Test bandwidth sounds
```

### Output

```
$ ccbell:bandwidth status

=== Sound Event Network Bandwidth Monitor ===

Status: Enabled
High Speed: 100 Mbps
Low Speed: 1 Mbps
Data Quota: 1000 GB

Watched Interfaces: 2

Interface Statistics:

[1] eth0 (Ethernet)
    Upload Speed: 45 Mbps
    Download Speed: 250 Mbps
    Total Today: 5.2 GB
    Status: Normal
    Sound: bundled:bw-eth0

[2] wlan0 (WiFi)
    Upload Speed: 2 Mbps
    Download Speed: 15 Mbps
    Total Today: 1.8 GB
    Status: Normal
    Sound: bundled:bw-wlan0

Data Usage This Month:
  eth0: 245 GB / 1000 GB (24%)
  wlan0: 85 GB / 1000 GB (8%)

Recent Events:
  [1] eth0: High Bandwidth (5 min ago)
       250 Mbps > 100 Mbps threshold
  [2] wlan0: Data Milestone (1 hour ago)
       1 GB transferred
  [3] eth0: Low Speed (2 hours ago)
       0.5 Mbps < 1 Mbps threshold

Bandwidth Statistics:
  High Speed Alerts: 15
  Low Speed Alerts: 3
  Milestones: 5

Sound Settings:
  High Speed: bundled:bw-high
  Milestone: bundled:bw-milestone
  Low Speed: bundled:bw-low

[Configure] [Add Interface] [Test All]
```

---

## Audio Player Compatibility

Bandwidth monitoring doesn't play sounds directly:
- Monitoring feature using ifconfig/ip/nload
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Bandwidth Monitor

```go
type NetworkBandwidthMonitor struct {
    config          *NetworkBandwidthMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    interfaceState  map[string]*InterfaceInfo
    lastEventTime   map[string]time.Time
    lastCheckTime   time.Time
}

type InterfaceInfo struct {
    Name           string
    RXBytes        uint64
    TXBytes        uint64
    RXSpeed        float64 // Mbps
    TXSpeed        float64 // Mbps
    TotalToday     uint64
    Status         string // "normal", "high", "low"
    LastCheck      time.Time
}

func (m *NetworkBandwidthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.interfaceState = make(map[string]*InterfaceInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *NetworkBandwidthMonitor) monitor() {
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

func (m *NetworkBandwidthMonitor) snapshotInterfaceState() {
    interfaces := m.listInterfaces()
    for name := range interfaces {
        m.interfaceState[name] = &InterfaceInfo{
            Name:      name,
            LastCheck: time.Now(),
        }
    }
}

func (m *NetworkBandwidthMonitor) checkInterfaceState() {
    currentInterfaces := m.listInterfaces()
    currentTime := time.Now()
    elapsed := currentTime.Sub(m.lastCheckTime).Seconds()

    for name, _ := range currentInterfaces {
        if !m.shouldWatchInterface(name) {
            continue
        }

        info := m.getInterfaceStats(name, elapsed)
        if info == nil {
            continue
        }

        lastInfo := m.interfaceState[name]
        if lastInfo == nil {
            m.interfaceState[name] = info
            continue
        }

        // Check speed thresholds
        m.checkHighSpeed(info, lastInfo)
        m.checkLowSpeed(info, lastInfo)

        // Check data milestones
        m.checkDataMilestones(info, lastInfo)

        m.interfaceState[name] = info
    }

    m.lastCheckTime = currentTime
}

func (m *NetworkBandwidthMonitor) listInterfaces() map[string]bool {
    interfaces := make(map[string]bool)

    cmd := exec.Command("ifconfig", "-l")
    output, err := cmd.Output()
    if err != nil {
        return interfaces
    }

    // macOS format: en0 en1 lo0
    parts := strings.Fields(string(output))
    for _, part := range parts {
        // Filter out loopback
        if part != "lo0" && part != "lo" {
            interfaces[part] = true
        }
    }

    return interfaces
}

func (m *NetworkBandwidthMonitor) getInterfaceStats(name string, elapsed float64) *InterfaceInfo {
    cmd := exec.Command("ifconfig", name)
    output, err := cmd.Output()
    if err != nil {
        return nil
    }

    info := &InterfaceInfo{Name: name}

    // Parse RX bytes
    rxRe := regexp.MustCompile(`\b(\d+) packets received\b`)
    // Parse TX bytes
    txRe := regexp.MustCompile(`\b(\d+) packets sent\b`)

    // More detailed parsing for bytes
    rxBytesRe := regexp.MustCompile(`bytes (\d+)`)
    txBytesRe := regexp.MustCompile(`bytes:(\d+)`)

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "RX packets") {
            match := rxBytesRe.FindStringSubmatch(line)
            if match != nil {
                info.RXBytes, _ = strconv.ParseUint(match[1], 10, 64)
            }
        } else if strings.Contains(line, "TX packets") {
            match := txBytesRe.FindStringSubmatch(line)
            if match != nil {
                info.TXBytes, _ = strconv.ParseUint(match[1], 10, 64)
            }
        }
    }

    // Calculate speeds
    if elapsed > 0 && info.RXBytes > 0 {
        // Calculate Mbps
        rxDelta := info.RXBytes - m.interfaceState[name].RXBytes
        info.RXSpeed = float64(rxDelta*8) / elapsed / 1000000 // Convert to Mbps
    }

    if elapsed > 0 && info.TXBytes > 0 {
        txDelta := info.TXBytes - m.interfaceState[name].TXBytes
        info.TXSpeed = float64(txDelta*8) / elapsed / 1000000 // Convert to Mbps
    }

    info.TotalToday = info.RXBytes + info.TXBytes

    return info
}

func (m *NetworkBandwidthMonitor) checkHighSpeed(info *InterfaceInfo, lastInfo *InterfaceInfo) {
    totalSpeed := info.RXSpeed + info.TXSpeed
    if totalSpeed >= float64(m.config.HighSpeedThreshold) {
        key := fmt.Sprintf("high_speed:%s", info.Name)
        if m.shouldAlert(key, 5*time.Minute) {
            if m.config.SoundOnHighSpeed {
                sound := m.config.Sounds["high_speed"]
                if sound != "" {
                    m.player.Play(sound, 0.4)
                }
            }
        }
    }
}

func (m *NetworkBandwidthMonitor) checkLowSpeed(info *InterfaceInfo, lastInfo *InterfaceInfo) {
    totalSpeed := (info.RXSpeed + info.TXSpeed) * 1000 // Convert to Kbps
    if totalSpeed < float64(m.config.LowSpeedThreshold) && totalSpeed > 0 {
        key := fmt.Sprintf("low_speed:%s", info.Name)
        if m.shouldAlert(key, 10*time.Minute) {
            if m.config.SoundOnLowSpeed {
                sound := m.config.Sounds["low_speed"]
                if sound != "" {
                    m.player.Play(sound, 0.3)
                }
            }
        }
    }
}

func (m *NetworkBandwidthMonitor) checkDataMilestones(info *InterfaceInfo, lastInfo *InterfaceInfo) {
    if !m.config.SoundOnMilestone {
        return
    }

    lastGB := lastInfo.TotalToday / (1024 * 1024 * 1024)
    currentGB := info.TotalToday / (1024 * 1024 * 1024)

    for _, milestone := range m.config.MilestonesGB {
        if lastGB < uint64(milestone) && currentGB >= uint64(milestone) {
            key := fmt.Sprintf("milestone:%s:%d", info.Name, milestone)
            if m.shouldAlert(key, 1*time.Hour) {
                sound := m.config.Sounds["milestone"]
                if sound != "" {
                    m.player.Play(sound, 0.4)
                }
            }
        }
    }
}

func (m *NetworkBandwidthMonitor) shouldWatchInterface(name string) bool {
    if len(m.config.WatchInterfaces) == 0 {
        return true
    }

    for _, i := range m.config.WatchInterfaces {
        if i == "*" || i == name {
            return true
        }
    }

    return false
}

func (m *NetworkBandwidthMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ifconfig | System Tool | Free | Network interface info |
| ip | System Tool | Free | Network interface info (Linux) |
| nload | System Tool | Free | Bandwidth monitoring |

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
| Linux | Supported | Uses ip, ifconfig, nload |
