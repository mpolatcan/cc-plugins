# Feature: Sound Event Firewall Event Monitor

Play sounds for firewall rule matches and connection blocking events.

## Summary

Monitor firewall events including blocked connections, allowed traffic, and rule triggers, playing sounds for firewall events.

## Motivation

- Security awareness
- Intrusion detection
- Port scan alerts
- Connection monitoring
- Firewall feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Firewall Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Blocked | Packet blocked | Port 22 from unknown IP |
| Connection Allowed | Packet allowed | HTTP traffic |
| Port Scan Detected | Port scan pattern | Multiple ports |
| Rate Limit Hit | Connection rate limit | DDoS protection |
| New Rule Match | Custom rule triggered | Block list hit |

### Configuration

```go
type FirewallMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    FirewallType       string            `json:"firewall_type"` // "iptables", "pf", "nft"
    SoundOnBlock       bool              `json:"sound_on_block"`
    SoundOnPortScan    bool              `json:"sound_on_port_scan"`
    SoundOnRateLimit   bool              `json:"sound_on_rate_limit"`
    BlockedPorts       []int             `json:"blocked_ports"` // [22, 3389]
    RateLimitThreshold int               `json:"rate_limit_per_minute"` // 100
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 30 default
}

type FirewallEvent struct {
    Action      string // "block", "allow", "rate_limit"
    Protocol    string // "tcp", "udp", "icmp"
    SourceIP    string
    DestIP      string
    SourcePort  int
    DestPort    int
    Rule        string
    Count       int
    EventType   string // "block", "scan", "rate", "rule"
}
```

### Commands

```bash
/ccbell:firewall status               # Show firewall status
/ccbell:firewall type iptables        # Set firewall type
/ccbell:firewall sound block <sound>
/ccbell:firewall sound scan <sound>
/ccbell:firewall test                 # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Event Monitor ===

Status: Enabled
Firewall: iptables
Block Sounds: Yes
Port Scan Sounds: Yes

Firewall Rules:
  [1] INPUT - DROP (estab. connection)
  [2] INPUT - ACCEPT (22/tcp)
  [3] FORWARD - DROP (all)

Recent Events:
  [1] Blocked: 192.168.1.50:54321 -> 22/tcp (5 min ago)
       Failed SSH attempt
  [2] Port Scan: 10.0.0.100 (10 ports, 5 sec) (10 min ago)
       Detected port scan
  [3] Rate Limit: 192.168.1.75 (150 req/min) (1 hour ago)
       DDoS protection triggered

Firewall Statistics:
  Blocked Today: 125
  Port Scans: 3
  Rate Limited: 15

Sound Settings:
  Block: bundled:firewall-block
  Scan: bundled:firewall-scan
  Rate Limit: bundled:firewall-rate

[Configure] [Set Type] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using iptables/netfilter
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Firewall Event Monitor

```go
type FirewallMonitor struct {
    config          *FirewallMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    blockCount      map[string]int
    portScanState   map[string]*ScanInfo
    lastEventTime   map[string]time.Time
}

type ScanInfo struct {
    SourceIP    string
    Ports       []int
    FirstSeen   time.Time
    PortCount   int
}

func (m *FirewallMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.blockCount = make(map[string]int)
    m.portScanState = make(map[string]*ScanInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *FirewallMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFirewallState()

    for {
        select {
        case <-ticker.C:
            m.checkFirewallState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FirewallMonitor) snapshotFirewallState() {
    // Get current firewall statistics
    if runtime.GOOS == "linux" {
        m.readIPTablesStats()
    } else {
        m.readPFStats()
    }
}

func (m *FirewallMonitor) checkFirewallState() {
    if runtime.GOOS == "linux" {
        m.readIPTablesStats()
    } else {
        m.readPFStats()
    }
}

func (m *FirewallMonitor) readIPTablesStats() {
    // Read iptables counters
    cmd := exec.Command("iptables", "-L", "-v", "-n", "-x")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPTablesOutput(string(output))
}

func (m *FirewallMonitor) parseIPTablesOutput(output string) {
    lines := strings.Split(string(output), "\n")

    for _, line := range lines {
        if strings.Contains(line, "DROP") || strings.Contains(line, "REJECT") {
            parts := strings.Fields(line)
            if len(parts) >= 8 {
                // Parse blocked packet count
                // This is simplified - actual parsing depends on iptables output
                m.evaluateBlockEvent(line)
            }
        }
    }
}

func (m *FirewallMonitor) readPFStats() {
    cmd := exec.Command("pfctl", "-s", "info")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePFStats(string(output))
}

func (m *FirewallMonitor) parsePFStats(output string) {
    // Parse pfctl output for blocked packets
}

func (m *FirewallMonitor) evaluateBlockEvent(line string) {
    // This is a simplified approach
    // Real implementation would parse actual firewall logs
}

func (m *FirewallMonitor) checkPortScans() {
    // Check for port scan patterns in logs
    // Could read /var/log/syslog or use auditd
}

func (m *FirewallMonitor) onConnectionBlocked(event *FirewallEvent) {
    if !m.config.SoundOnBlock {
        return
    }

    // Check if this port is being watched
    for _, port := range m.config.BlockedPorts {
        if event.DestPort == port {
            key := fmt.Sprintf("block:%s:%d", event.SourceIP, port)
            if m.shouldAlert(key, 5*time.Minute) {
                sound := m.config.Sounds["block"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
            return
        }
    }
}

func (m *FirewallMonitor) onPortScanDetected(event *FirewallEvent) {
    if !m.config.SoundOnPortScan {
        return
    }

    key := fmt.Sprintf("scan:%s", event.SourceIP)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["scan"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *FirewallMonitor) onRateLimitHit(event *FirewallEvent) {
    if !m.config.SoundOnRateLimit {
        return
    }

    key := fmt.Sprintf("rate:%s", event.SourceIP)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["rate_limit"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *FirewallMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| iptables | System Tool | Free | Linux firewall |
| pfctl | System Tool | Free | macOS firewall |
| /var/log/syslog | File | Free | Log source |

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
| macOS | Supported | Uses pfctl |
| Linux | Supported | Uses iptables, nft |
