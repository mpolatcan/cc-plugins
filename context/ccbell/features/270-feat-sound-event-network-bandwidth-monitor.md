# Feature: Sound Event Network Bandwidth Monitor

Play sounds for network bandwidth usage and thresholds.

## Summary

Monitor network bandwidth usage, data transfer rates, and connection limits, playing sounds when thresholds are exceeded.

## Motivation

- Data cap warnings
- Bandwidth awareness
- Upload/download alerts
- Speed change detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Network Bandwidth Events

| Event | Description | Example |
|-------|-------------|---------|
| High Usage | Bandwidth > threshold | > 80% of cap |
| Data Cap | Usage > 90% | 9.5 GB / 10 GB |
| Speed Change | Speed changed | 100M -> 1G |
| Connection Limit | Max connections | 1000 connections |

### Configuration

```go
type NetworkBandwidthMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Interfaces        []string          `json:"interfaces"` // "en0", "eth0"
    DataCapBytes      int64             `json:"data_cap_bytes"` // Monthly cap
    UsageWarningPercent int             `json:"usage_warning_percent"` // 80 default
    UsageCriticalPercent int           `json:"usage_critical_percent"` // 95 default
    SpeedThresholdMbps float64          `json:"speed_threshold_mbps"`
    SoundOnWarning    bool              `json:"sound_on_warning"`
    SoundOnCritical   bool              `json:"sound_on_critical"`
    SoundOnSpeedChange bool             `json:"sound_on_speed_change"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type NetworkBandwidthEvent struct {
    Interface     string
    DownloadSpeed float64 // Mbps
    UploadSpeed   float64 // Mbps
    TotalUsed     int64   // bytes
    UsagePercent  float64
    EventType     string // "warning", "critical", "speed_change"
}
```

### Commands

```bash
/ccbell:bandwidth status               # Show bandwidth status
/ccbell:bandwidth set-cap 100GB        # Set monthly data cap
/ccbell:bandwidth sound warning <sound>
/ccbell:bandwidth sound critical <sound>
/ccbell:bandwidth test                 # Test bandwidth sounds
```

### Output

```
$ ccbell:bandwidth status

=== Sound Event Network Bandwidth Monitor ===

Status: Enabled
Data Cap: 100 GB
Warning: 80%
Critical: 95%

Current Month Usage: 72.5 GB / 100 GB (73%)

Interfaces:

[1] en0 (Wi-Fi)
    Status: Connected
    Download: 45.2 Mbps
    Upload: 12.5 Mbps
    [===============.......] 73%

[2] en1 (Thunderbolt)
    Status: Disconnected

Recent Events:
  [1] Warning (2 days ago)
       80% of data cap reached
  [2] Critical (1 month ago)
       95% of data cap reached
  [3] Speed Change (1 week ago)
       100 Mbps -> 500 Mbps

Sound Settings:
  Warning: bundled:stop
  Critical: bundled:stop
  Speed Change: bundled:stop

[Configure] [Set Cap] [Test All]
```

---

## Audio Player Compatibility

Network bandwidth monitoring doesn't play sounds directly:
- Monitoring feature using network statistics tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Bandwidth Monitor

```go
type NetworkBandwidthMonitor struct {
    config             *NetworkBandwidthMonitorConfig
    player             *audio.Player
    running            bool
    stopCh             chan struct{}
    lastStats          map[string]*InterfaceStats
    lastWarningTime    time.Time
    lastCriticalTime   time.Time
    lastSpeedChange    time.Time
}

type InterfaceStats struct {
    InterfaceName  string
    RxBytes        uint64
    TxBytes        uint64
    RxSpeed        float64 // bytes/sec
    TxSpeed        float64 // bytes/sec
    SampleTime     time.Time
}
```

```go
func (m *NetworkBandwidthMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStats = make(map[string]*InterfaceStats)
    go m.monitor()
}

func (m *NetworkBandwidthMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkBandwidth()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkBandwidthMonitor) checkBandwidth() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinBandwidth()
    } else {
        m.checkLinuxBandwidth()
    }
}

func (m *NetworkBandwidthMonitor) checkDarwinBandwidth() {
    // Use nettop to get interface statistics
    cmd := exec.Command("nettop", "-L", "1", "-J", "bytes_in,bytes_out")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    var stats []InterfaceStats
    if err := json.Unmarshal(output, &stats); err != nil {
        return
    }

    for _, stat := range stats {
        // Check if we should watch this interface
        if len(m.config.Interfaces) > 0 {
            found := false
            for _, iface := range m.config.Interfaces {
                if stat.InterfaceName == iface || strings.HasPrefix(stat.InterfaceName, iface) {
                    found = true
                    break
                }
            }
            if !found {
                continue
            }
        }

        m.evaluateStats(&stat)
    }
}

func (m *NetworkBandwidthMonitor) checkLinuxBandwidth() {
    // Read from /proc/net/dev
    data, err := os.ReadFile("/proc/net/dev")
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, ":") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) < 2 {
                continue
            }

            iface := strings.TrimSpace(parts[0])

            // Check interface filter
            if len(m.config.Interfaces) > 0 {
                found := false
                for _, watchIface := range m.config.Interfaces {
                    if iface == watchIface {
                        found = true
                        break
                    }
                }
                if !found {
                    continue
                }
            }

            stats := m.parseLinuxNetDev(parts[1])
            stats.InterfaceName = iface
            m.evaluateStats(stats)
        }
    }
}

func (m *NetworkBandwidthMonitor) parseLinuxNetDev(data string) *InterfaceStats {
    stats := &InterfaceStats{}

    fields := strings.Fields(data)
    if len(fields) < 10 {
        return stats
    }

    // Format: rx_bytes rx_packets rx_errs ... tx_bytes tx_packets ...
    rxBytes, _ := strconv.ParseUint(fields[0], 10, 64)
    txBytes, _ := strconv.ParseUint(fields[8], 10, 64)

    stats.RxBytes = rxBytes
    stats.TxBytes = txBytes

    return stats
}

func (m *NetworkBandwidthMonitor) evaluateStats(stats *InterfaceStats) {
    lastStats := m.lastStats[stats.InterfaceName]

    if lastStats != nil {
        // Calculate speed
        elapsed := stats.SampleTime.Sub(lastStats.SampleTime).Seconds()
        if elapsed > 0 {
            rxSpeed := float64(stats.RxBytes-lastStats.RxBytes) / elapsed
            txSpeed := float64(stats.TxBytes-lastStats.TxBytes) / elapsed

            stats.RxSpeed = rxSpeed / 1024 / 1024 // Mbps
            stats.TxSpeed = txSpeed / 1024 / 1024 // Mbps

            // Check speed change
            if lastStats.RxSpeed > 0 && stats.RxSpeed > m.config.SpeedThresholdMbps {
                if lastStats.RxSpeed < m.config.SpeedThresholdMbps {
                    m.onSpeedChange(stats)
                }
            }
        }
    }

    // Update last stats
    stats.SampleTime = time.Now()
    m.lastStats[stats.InterfaceName] = stats

    // Calculate total usage and check thresholds
    if m.config.DataCapBytes > 0 {
        m.checkDataCap(stats)
    }
}

func (m *NetworkBandwidthMonitor) checkDataCap(stats *InterfaceStats) {
    // Calculate total bytes across all watched interfaces
    var totalUsed int64
    for _, s := range m.lastStats {
        totalUsed += int64(s.RxBytes + s.TxBytes)
    }

    usagePercent := float64(totalUsed) / float64(m.config.DataCapBytes) * 100
    stats.TotalUsed = totalUsed
    stats.UsagePercent = usagePercent

    if usagePercent >= float64(m.config.UsageCriticalPercent) {
        m.onCriticalUsage(stats)
    } else if usagePercent >= float64(m.config.UsageWarningPercent) {
        m.onWarningUsage(stats)
    }
}

func (m *NetworkBandwidthMonitor) onWarningUsage(stats *InterfaceStats) {
    if !m.config.SoundOnWarning {
        return
    }

    if time.Since(m.lastWarningTime) < 24*time.Hour {
        return
    }

    m.lastWarningTime = time.Now()

    sound := m.config.Sounds["warning"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *NetworkBandwidthMonitor) onCriticalUsage(stats *InterfaceStats) {
    if !m.config.SoundOnCritical {
        return
    }

    if time.Since(m.lastCriticalTime) < 24*time.Hour {
        return
    }

    m.lastCriticalTime = time.Now()

    sound := m.config.Sounds["critical"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *NetworkBandwidthMonitor) onSpeedChange(stats *InterfaceStats) {
    if !m.config.SoundOnSpeedChange {
        return
    }

    if time.Since(m.lastSpeedChange) < 1*time.Hour {
        return
    }

    m.lastSpeedChange = time.Now()

    sound := m.config.Sounds["speed_change"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| nettop | System Tool | Free | macOS network stats |
| /proc/net/dev | File | Free | Linux network stats |

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
| macOS | Supported | Uses nettop |
| Linux | Supported | Uses /proc/net/dev |
| Windows | Not Supported | ccbell only supports macOS/Linux |
