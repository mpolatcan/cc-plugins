# Feature: Sound Event Firewall Event Monitor

Play sounds for firewall block events, port scans, and security alerts.

## Summary

Monitor firewall logs for blocked connections, port scans, and security events, playing sounds for firewall events.

## Motivation

- Security awareness
- Intrusion detection
- Port scan alerts
- Connection blocking feedback
- Network security monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Firewall Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Blocked | Rule matched | DROP |
| Port Scan Detected | Sequential ports | SYN flood |
| New Connection | First-time source | new IP |
| Rate Limit Hit | Too many requests | throttled |
| Invalid Packet | Malformed packet | malformed |
| Rule Matched | Specific rule fired | SSH block |

### Configuration

```go
type FirewallEventMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchChains       []string          `json:"watch_chains"` // "INPUT", "OUTPUT"
    WatchActions      []string          `json:"watch_actions"` // "DROP", "REJECT"
    WatchPorts        []int             `json:"watch_ports"` // 22, 80, 443
    RateLimitEvents   int               `json:"rate_limit_events"` // 10 per minute
    SoundOnBlock      bool              `json:"sound_on_block"`
    SoundOnScan       bool              `json:"sound_on_scan"`
    SoundOnNewSource  bool              `json:"sound_on_new_source"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:firewall status                # Show firewall status
/ccbell:firewall add port 22           # Add port to watch
/ccbell:firewall add chain INPUT       # Add chain to watch
/ccbell:firewall sound block <sound>
/ccbell:firewall sound scan <sound>
/ccbell:firewall test                  # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Event Monitor ===

Status: Enabled
Block Sounds: Yes
Scan Sounds: Yes
New Source Sounds: Yes

Watched Chains: 2
Watched Ports: 3

Recent Blocked Events:

[1] 192.168.1.100:55532 -> 192.168.1.1:22 (SSH)
    Action: DROP
    Chain: INPUT
    Time: 5 min ago
    Sound: bundled:fw-ssh

[2] 10.0.0.50:62123 -> 192.168.1.1:3389 (RDP)
    Action: DROP
    Chain: INPUT
    Time: 15 min ago
    Sound: bundled:fw-rdp

[3] 45.33.32.156:port scan detected
    Action: DROP
    Ports: 22, 80, 443, 3306
    Time: 1 hour ago
    Sound: bundled:fw-scan

Blocked Sources Today: 45
Port Scans Detected: 3
New Sources: 12

Firewall Statistics:
  Total Blocks: 156
  Dropped Packets: 2.5 MB
  Top Port: 22 (SSH)
  Top Source: 45.33.32.156

Sound Settings:
  Block: bundled:fw-block
  Scan: bundled:fw-scan
  New Source: bundled:fw-new

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using iptables/pfctl
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Firewall Event Monitor

```go
type FirewallEventMonitor struct {
    config          *FirewallEventMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    eventState      map[string]*FirewallEventInfo
    lastEventTime   map[string]time.Time
    sourceSet       map[string]time.Time
    lastCheckTime   time.Time
}

type FirewallEventInfo struct {
    SourceIP   string
    DestIP     string
    DestPort   int
    Protocol   string
    Action     string
    Chain      string
    Count      int
    Timestamp  time.Time
}

func (m *FirewallEventMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.eventState = make(map[string]*FirewallEventInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.sourceSet = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *FirewallEventMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkFirewallEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FirewallEventMonitor) checkFirewallEvents() {
    // Parse iptables logs
    m.parseIPTablesLogs()

    // Parse pf logs on macOS
    m.parsePFLogs()
}

func (m *FirewallEventMonitor) parseIPTablesLogs() {
    since := m.lastCheckTime.Format("2006-01-02 15:04:05")

    // Check kernel log for iptables messages
    cmd := exec.Command("journalctl", "-k", "--since", since, "--no-pager", "-n", "100")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "IPTables") || strings.Contains(line, "kernel:") {
            m.parseIPTablesLine(line)
        }
    }

    m.lastCheckTime = time.Now()
}

func (m *FirewallEventMonitor) parseIPTablesLine(line string) {
    // Parse: "IPTables: IN=eth0 OUT= SRC=192.168.1.100 DST=192.168.1.1 DPT=22"
    re := regexp.MustCompile(`SRC=([0-9.]+) DST=([0-9.]+) DPT=(\d+)`)
    match := re.FindStringSubmatch(line)
    if match == nil {
        return
    }

    srcIP := match[1]
    dstIP := match[2]
    port, _ := strconv.Atoi(match[3])

    if !m.shouldWatchPort(port) {
        return
    }

    id := fmt.Sprintf("%s->%s:%d", srcIP, dstIP, port)
    event := &FirewallEventInfo{
        SourceIP:  srcIP,
        DestIP:    dstIP,
        DestPort:  port,
        Action:    "DROP",
        Chain:     "INPUT",
        Timestamp: time.Now(),
    }

    m.processFirewallEvent(id, event, srcIP)
}

func (m *FirewallEventMonitor) parsePFLogs() {
    since := m.lastCheckTime.Format("2006-01-02 15:04:05")

    // Check pf logs on macOS
    cmd := exec.Command("log", "show", "--predicate", "eventMessage CONTAINS 'pf'",
        "--since", since, "--last", "5m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "PASS") || strings.Contains(line, "BLOCK") {
            m.parsePFLine(line)
        }
    }
}

func (m *FirewallEventMonitor) parsePFLine(line string) {
    // Parse pfctl log format
    re := regexp.MustCompile(`([0-9.]+):(\d+) -> ([0-9.]+):(\d+)`)
    match := re.FindStringSubmatch(line)
    if match == nil {
        return
    }

    srcIP := match[1]
    srcPort := match[2]
    dstIP := match[3]
    dstPort, _ := strconv.Atoi(match[4])

    if !m.shouldWatchPort(dstPort) {
        return
    }

    action := "BLOCK"
    if strings.Contains(line, "PASS") {
        action = "PASS"
    }

    id := fmt.Sprintf("%s:%s->%s:%d", action, srcIP, dstIP, dstPort)
    event := &FirewallEventInfo{
        SourceIP:  srcIP,
        DestIP:    dstIP,
        DestPort:  dstPort,
        Action:    action,
        Chain:     "INPUT",
        Timestamp: time.Now(),
    }

    m.processFirewallEvent(id, event, srcIP)
}

func (m *FirewallEventMonitor) processFirewallEvent(id string, event *FirewallEventInfo, sourceIP string) {
    // Check if this is a new source
    if _, exists := m.sourceSet[sourceIP]; !exists {
        m.sourceSet[sourceIP] = time.Now()
        if m.config.SoundOnNewSource {
            key := fmt.Sprintf("new_source:%s", sourceIP)
            if m.shouldAlert(key, 1*time.Hour) {
                sound := m.config.Sounds["new_source"]
                if sound != "" {
                    m.player.Play(sound, 0.4)
                }
            }
        }
    }

    // Process block event
    if event.Action == "DROP" || event.Action == "REJECT" || event.Action == "BLOCK" {
        if m.config.SoundOnBlock {
            key := fmt.Sprintf("block:%s:%d", sourceIP, event.DestPort)
            if m.shouldAlert(key, 1*time.Minute) {
                sound := m.config.Sounds["block"]
                if sound != "" {
                    m.player.Play(sound, 0.5)
                }
            }
        }
    }

    // Check for port scan pattern
    m.checkPortScan(sourceIP)
}

func (m *FirewallEventMonitor) checkPortScan(sourceIP string) {
    // Count recent connections from this source
    count := 0
    cutoff := time.Now().Add(-5 * time.Minute)

    for ip, t := range m.sourceSet {
        if ip == sourceIP && t.After(cutoff) {
            count++
        }
    }

    if count >= 5 {
        if m.config.SoundOnScan {
            key := fmt.Sprintf("scan:%s", sourceIP)
            if m.shouldAlert(key, 30*time.Minute) {
                sound := m.config.Sounds["scan"]
                if sound != "" {
                    m.player.Play(sound, 0.6)
                }
            }
        }
    }
}

func (m *FirewallEventMonitor) shouldWatchPort(port int) bool {
    if len(m.config.WatchPorts) == 0 {
        return true
    }

    for _, p := range m.config.WatchPorts {
        if p == port {
            return true
        }
    }

    return false
}

func (m *FirewallEventMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| iptables | System Tool | Free | Firewall management |
| pfctl | System Tool | Free | Packet filter (macOS) |
| journalctl | System Tool | Free | Kernel logs |
| log | System Tool | Free | macOS logging |

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
| macOS | Supported | Uses pfctl, log |
| Linux | Supported | Uses iptables, journalctl |
