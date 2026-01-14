# Feature: Sound Event Firewall Event Monitor

Play sounds for firewall events and security alerts.

## Summary

Monitor firewall events, connection blocks, and security alerts, playing sounds for firewall activity.

## Motivation

- Security breach alerts
- Blocked connection feedback
- Port scan detection
- Security awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Firewall Events

| Event | Description | Example |
|-------|-------------|---------|
| Connection Blocked | Packet dropped | Port 22 blocked |
| Port Scan | Multiple ports | Nmap detected |
| New Rule | Firewall rule added | Allow port 8080 |
| Security Alert | Suspicious activity | Unusual traffic |

### Configuration

```go
type FirewallEventMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchPorts        []int             `json:"watch_ports"` // Ports to monitor
    SoundOnBlock      bool              `json:"sound_on_block"]
    SoundOnPortScan   bool              `json:"sound_on_port_scan"]
    SoundOnAlert      bool              `json:"sound_on_alert"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 10 default
}

type FirewallEvent struct {
    Action      string // "block", "allow", "alert"
    SourceIP    string
    DestPort    int
    Protocol    string // "tcp", "udp", "icmp"
    RuleName    string
    Timestamp   time.Time
}
```

### Commands

```bash
/ccbell:firewall status              # Show firewall status
/ccbell:firewall add 22              # Add port to watch
/ccbell:firewall remove 22
/ccbell:firewall sound block <sound>
/ccbell:firewall sound scan <sound>
/ccbell:firewall test                # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Event Monitor ===

Status: Enabled
Block Sounds: Yes
Port Scan Sounds: Yes

Firewall: pf (macOS)
Status: Active

Recent Blocked Connections: 5

[1] 192.168.1.100:12345 -> :22 (TCP)
    5 min ago
    Rule: SSH Block
    Sound: bundled:stop

[2] 10.0.0.50:54321 -> :3389 (TCP)
    1 hour ago
    Rule: RDP Block
    Sound: bundled:stop

[3] 172.16.0.100 -> :80 (TCP)
    2 hours ago
    10 connections in 5 seconds
    Port Scan Detected
    Sound: bundled:stop

Statistics:
  Blocked Today: 45
  Allowed Today: 234
  Port Scans: 2

Sound Settings:
  Block: bundled:stop
  Port Scan: bundled:stop
  Alert: bundled:stop

[Configure] [Add Port] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using system firewall tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Firewall Event Monitor

```go
type FirewallEventMonitor struct {
    config           *FirewallEventMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    recentBlocks     map[string]int // source IP -> count
    lastAlertTime    time.Time
}
```

```go
func (m *FirewallEventMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.recentBlocks = make(map[string]int)
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
    if runtime.GOOS == "darwin" {
        m.checkDarwinFirewall()
    } else {
        m.checkLinuxFirewall()
    }
}

func (m *FirewallEventMonitor) checkDarwinFirewall() {
    // Check pfctl logs
    cmd := exec.Command("pflog", "-i", "pflog0", "-n", "-p", "-t", "block")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        event := m.parsePflogLine(line)
        if event != nil {
            m.evaluateEvent(event)
        }
    }
}

func (m *FirewallEventMonitor) checkLinuxFirewall() {
    // Check iptables or nftables logs
    if m.hasIPTables() {
        m.checkIPTables()
    } else if m.hasNftables() {
        m.checkNftables()
    }
}

func (m *FirewallEventMonitor) hasIPTables() bool {
    cmd := exec.Command("which", "iptables")
    err := cmd.Run()
    return err == nil
}

func (m *FirewallEventMonitor) hasNftables() bool {
    cmd := exec.Command("which", "nft")
    err := cmd.Run()
    return err == nil
}

func (m *FirewallEventMonitor) checkIPTables() {
    // Use iptables with log target
    cmd := exec.Command("iptables", "-L", "-v", "-n")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse iptables output for recent blocks
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "LOG") {
            event := m.parseIPTablesLine(line)
            if event != nil {
                m.evaluateEvent(event)
            }
        }
    }
}

func (m *FirewallEventMonitor) checkNftables() {
    cmd := exec.Command("nft", "list", "ruleset")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse nftables output
    m.parseNftablesOutput(string(output))
}

func (m *FirewallEventMonitor) parsePflogLine(line string) *FirewallEvent {
    event := &FirewallEvent{
        Timestamp: time.Now(),
        Action:    "block",
    }

    // pf log format: timestamp rule action direction
    parts := strings.Fields(line)
    if len(parts) < 4 {
        return nil
    }

    // Parse source IP and port
    srcRe := regexp.MustCompile(`(\d+\.\d+\.\d+\.\d+)\.(\d+)`)
    match := srcRe.FindStringSubmatch(line)
    if len(match) >= 3 {
        event.SourceIP = match[1]
    }

    // Parse destination port
    portRe := regexp.MustCompile(`:(\d+)`)
    matches := portRe.FindAllStringSubmatch(line, -1)
    for _, m := range matches {
        if port, err := strconv.Atoi(m[1]); err == nil && port > 0 {
            event.DestPort = port
            break
        }
    }

    return event
}

func (m *FirewallEventMonitor) parseIPTablesLine(line string) *FirewallEvent {
    event := &FirewallEvent{
        Timestamp: time.Now(),
        Action:    "block",
    }

    // Parse iptables LOG output
    parts := strings.Fields(line)
    for i, part := range parts {
        if strings.Contains(part, ".") {
            event.SourceIP = part
        }
        if part == "dpt:" {
            if i+1 < len(parts) {
                if port, err := strconv.Atoi(parts[i+1]); err == nil {
                    event.DestPort = port
                }
            }
        }
    }

    return event
}

func (m *FirewallEventMonitor) parseNftablesOutput(output string) {
    // Parse nftables ruleset for logging rules
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "log") {
            // Found a logging rule
            event := &FirewallEvent{
                Timestamp: time.Now(),
                Action:    "alert",
            }
            m.evaluateEvent(event)
        }
    }
}

func (m *FirewallEventMonitor) evaluateEvent(event *FirewallEvent) {
    // Check if we should watch this port
    if len(m.config.WatchPorts) > 0 {
        found := false
        for _, port := range m.config.WatchPorts {
            if event.DestPort == port {
                found = true
                break
            }
        }
        if !found {
            return
        }
    }

    // Check for port scan (multiple blocks from same IP)
    if event.Action == "block" {
        m.recentBlocks[event.SourceIP]++
        if m.recentBlocks[event.SourceIP] >= 10 {
            // Likely a port scan
            m.onPortScan(event.SourceIP)
            // Reset count after alert
            m.recentBlocks[event.SourceIP] = 0
        }
    }

    // Handle based on action
    switch event.Action {
    case "block":
        m.onConnectionBlocked(event)
    case "alert":
        m.onSecurityAlert(event)
    }
}

func (m *FirewallEventMonitor) onConnectionBlocked(event *FirewallEvent) {
    if !m.config.SoundOnBlock {
        return
    }

    // Debounce: don't alert too frequently
    if time.Since(m.lastAlertTime) < 10*time.Second {
        return
    }

    m.lastAlertTime = time.Now()

    sound := m.config.Sounds["block"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *FirewallEventMonitor) onPortScan(sourceIP string) {
    if !m.config.SoundOnPortScan {
        return
    }

    sound := m.config.Sounds["port_scan"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}

func (m *FirewallEventMonitor) onSecurityAlert(event *FirewallEvent) {
    if !m.config.SoundOnAlert {
        return
    }

    sound := m.config.Sounds["alert"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pflog | System Tool | Free | macOS pf logging |
| iptables | System Tool | Free | Linux firewall |
| nft | System Tool | Free | Linux nftables |

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
| macOS | Supported | Uses pflog, pfctl |
| Linux | Supported | Uses iptables, nft |
| Windows | Not Supported | ccbell only supports macOS/Linux |
