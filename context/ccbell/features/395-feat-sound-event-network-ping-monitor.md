# Feature: Sound Event Network Ping Monitor

Play sounds for ping failures, latency thresholds, and packet loss detection.

## Summary

Monitor network hosts for ping connectivity, response times, and packet loss, playing sounds for ping events.

## Motivation

- Connectivity awareness
- Latency monitoring
- Packet loss detection
- Host availability
- Network troubleshooting

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Ping Events

| Event | Description | Example |
|-------|-------------|---------|
| Host Unreachable | Ping failed | timeout |
| High Latency | RTT > threshold | > 100ms |
| Packet Loss | Lost packets | > 5% |
| Host Recovered | Back online | recovered |
| DNS Failed | Could not resolve | nxdomain |
| Jitter Detected | High variation | > 50ms |

### Configuration

```go
type NetworkPingMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Hosts             []PingHostConfig  `json:"hosts"`
    Count             int               `json:"count"` // 4 default
    Timeout           int               `json:"timeout_ms"` // 5000 default
    LatencyThreshold  int               `json:"latency_threshold_ms"` // 100 default
    LossThreshold     float64           `json:"loss_threshold_pct"` // 5.0 default
    SoundOnFail       bool              `json:"sound_on_fail"`
    SoundOnHighLatency bool             `json:"sound_on_high_latency"`
    SoundOnLoss       bool              `json:"sound_on_loss"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type PingHostConfig struct {
    Name       string `json:"name"` // "Gateway"
    Host       string `json:"host"` // "192.168.1.1"
    Priority   string `json:"priority"` // "high", "medium", "low"
}
```

### Commands

```bash
/ccbell:ping status                    # Show ping status
/ccbell:ping add 192.168.1.1           # Add host to ping
/ccbell:ping remove 192.168.1.1
/ccbell:ping latency 100               # Set latency threshold
/ccbell:ping sound fail <sound>
/ccbell:ping sound high-latency <sound>
/ccbell:ping test                      # Test ping sounds
```

### Output

```
$ ccbell:ping status

=== Sound Event Network Ping Monitor ===

Status: Enabled
Latency Threshold: 100ms
Loss Threshold: 5%
Count: 4

Monitored Hosts: 5

Host Status:

[1] Gateway (192.168.1.1)
    Status: Online
    Latency: 1ms
    Loss: 0%
    Priority: High
    Sound: bundled:ping-gateway

[2] DNS (8.8.8.8)
    Status: Online
    Latency: 15ms
    Loss: 0%
    Priority: Medium
    Sound: bundled:ping-dns

[3] Router (10.0.0.1)
    Status: Offline
    Latency: N/A
    Loss: 100%
    Priority: High
    Sound: bundled:ping-router *** DOWN ***

[4] VPN (vpn.example.com)
    Status: Online
    Latency: 45ms
    Loss: 0%
    Priority: Medium
    Sound: bundled:ping-vpn

[5] ISP (isp-gateway.local)
    Status: Online
    Latency: 8ms
    Loss: 0%
    Priority: Low
    Sound: bundled:ping-isp

Recent Events:
  [1] Router: Host Unreachable (5 min ago)
       4/4 packets lost
  [2] VPN: High Latency (1 hour ago)
       150ms > 100ms threshold
  [3] DNS: Packet Loss (2 hours ago)
       20% loss detected

Ping Statistics:
  Total Hosts: 5
  Online: 4
  Offline: 1
  Average Latency: 17ms

Sound Settings:
  Fail: bundled:ping-fail
  High Latency: bundled:ping-latency
  Loss: bundled:ping-loss

[Configure] [Add Host] [Test All]
```

---

## Audio Player Compatibility

Ping monitoring doesn't play sounds directly:
- Monitoring feature using ping
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Network Ping Monitor

```go
type NetworkPingMonitor struct {
    config          *NetworkPingMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    hostState       map[string]*PingHostInfo
    lastEventTime   map[string]time.Time
}

type PingHostInfo struct {
    Name         string
    Host         string
    Status       string // "online", "offline", "unknown"
    Latency      float64 // milliseconds
    PacketLoss   float64 // percentage
    Priority     string
    LastCheck    time.Time
}

func (m *NetworkPingMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.hostState = make(map[string]*PingHostInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *NetworkPingMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkHosts()
        case <-m.stopCh:
            return
        }
    }
}

func (m *NetworkPingMonitor) checkHosts() {
    for _, host := range m.config.Hosts {
        m.pingHost(&host)
    }
}

func (m *NetworkPingMonitor) pingHost(config *PingHostConfig) {
    // Build ping command
    args := []string{
        "-c", strconv.Itoa(m.config.Count),
        "-W", strconv.Itoa(m.config.Timeout / 1000),
        "-q", // Quiet output
    }

    args = append(args, config.Host)

    cmd := exec.Command("ping", args...)
    output, err := cmd.Output()

    info := &PingHostInfo{
        Name:      config.Name,
        Host:      config.Host,
        Priority:  config.Priority,
        LastCheck: time.Now(),
    }

    if err != nil {
        info.Status = "offline"
        info.Latency = 0
        info.PacketLoss = 100
    } else {
        m.parsePingOutput(string(output), info)
    }

    m.processHostStatus(config.Name, info)
}

func (m *NetworkPingMonitor) parsePingOutput(output string, info *PingHostInfo) {
    // Parse: "4 packets transmitted, 4 received, 0% packet loss, time 3000ms"
    lossRe := regexp.MustCompile(`(\d+)% packet loss`)
    match := lossRe.FindStringSubmatch(output)
    if match != nil {
        loss, _ := strconv.ParseFloat(match[1], 64)
        info.PacketLoss = loss
    }

    // Parse: "rtt min/avg/max/mdev = 1.2/1.5/2.0/0.3 ms"
    latencyRe := regexp.MustEach(`= ([\d.]+)/([\d.]+)/([\d.]+)`)
    matches := latencyRe.FindAllStringSubmatch(output, -1)
    if len(matches) > 0 {
        avgLatency, _ := strconv.ParseFloat(matches[0][2], 64)
        info.Latency = avgLatency
    }

    // Determine status
    if info.PacketLoss >= 100 {
        info.Status = "offline"
    } else if info.PacketLoss > m.config.LossThreshold {
        info.Status = "degraded"
    } else if info.Latency > float64(m.config.LatencyThreshold) {
        info.Status = "high_latency"
    } else {
        info.Status = "online"
    }
}

func (m *NetworkPingMonitor) processHostStatus(name string, info *PingHostInfo) {
    lastInfo := m.hostState[name]

    if lastInfo == nil {
        m.hostState[name] = info
        return
    }

    // Check for status changes
    if lastInfo.Status != info.Status {
        switch info.Status {
        case "offline":
            if lastInfo.Status == "online" {
                m.onHostUnreachable(name, info)
            }
        case "online":
            if lastInfo.Status == "offline" {
                m.onHostRecovered(name, info)
            }
        case "degraded":
            if lastInfo.PacketLoss < m.config.LossThreshold {
                m.onPacketLoss(name, info)
            }
        case "high_latency":
            if lastInfo.Latency <= float64(m.config.LatencyThreshold) {
                m.onHighLatency(name, info)
            }
        }
    }

    m.hostState[name] = info
}

func (m *NetworkPingMonitor) onHostUnreachable(name string, info *PingHostInfo) {
    if !m.config.SoundOnFail {
        return
    }

    key := fmt.Sprintf("fail:%s", name)
    priority := info.Priority

    interval := 5 * time.Minute
    if priority == "high" {
        interval = 1 * time.Minute
    }

    if m.shouldAlert(key, interval) {
        sound := m.config.Sounds["fail"]
        if sound != "" {
            volume := 0.5
            if priority == "high" {
                volume = 0.7
            }
            m.player.Play(sound, volume)
        }
    }
}

func (m *NetworkPingMonitor) onHostRecovered(name string, info *PingHostInfo) {
    // Optional: sound when host comes back online
}

func (m *NetworkPingMonitor) onHighLatency(name string, info *PingHostInfo) {
    if !m.config.SoundOnHighLatency {
        return
    }

    key := fmt.Sprintf("latency:%s", name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["high_latency"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *NetworkPingMonitor) onPacketLoss(name string, info *PingHostInfo) {
    if !m.config.SoundOnLoss {
        return
    }

    key := fmt.Sprintf("loss:%s", name)
    if m.shouldAlert(key, 15*time.Minute) {
        sound := m.config.Sounds["loss"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *NetworkPingMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| ping | System Tool | Free | ICMP ping |

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
| macOS | Supported | Uses ping |
| Linux | Supported | Uses ping |
