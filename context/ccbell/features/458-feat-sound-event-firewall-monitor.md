# Feature: Sound Event Firewall Monitor

Play sounds for firewall rule changes, blocked connections, and security alerts.

## Summary

Monitor firewall (pf, iptables, nftables) for rule changes, blocked traffic patterns, and security events, playing sounds for firewall events.

## Motivation

- Security awareness
- Rule change alerts
- Intrusion detection
- Port scan alerts
- Traffic pattern monitoring

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
| Rule Added | New firewall rule | allow port 8080 |
| Rule Deleted | Rule removed | deleted rule |
| Block Detected | Connection blocked | 10.0.0.1:port |
| Port Scan | Scanning detected | nmap scan |
| Rate Limit | Traffic limited | rate exceeded |
| Connection Limit | Too many conn | limit hit |

### Configuration

```go
type FirewallMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchFirewall    string            `json:"watch_firewall"` // "pf", "iptables", "nftables", "all"
    SoundOnRule      bool              `json:"sound_on_rule"`
    SoundOnBlock     bool              `json:"sound_on_block"`
    SoundOnPortScan  bool              `json:"sound_on_port_scan"`
    BlockThreshold   int               `json:"block_threshold"` // 10 per minute
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:firewall status             # Show firewall status
/ccbell:firewall add iptables       # Add firewall to watch
/ccbell:firewall sound block <sound>
/ccbell:firewall test               # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Monitor ===

Status: Enabled
Watch Firewall: all
Block Threshold: 10/min

Firewall Status:

[1] pf (macOS)
    Status: ENABLED
    Rules: 45
    Last Change: 2 hours ago
    Packets Blocked: 1,234
    Sound: bundled:firewall-pf

[2] iptables (Linux)
    Status: ENABLED
    Chains: 5
    Rules: 32
    Packets Blocked: 5,678
    Sound: bundled:firewall-iptables

Recent Events:

[1] iptables: Rule Added (5 min ago)
       -A INPUT -p tcp --dport 8080 -j ACCEPT
       Sound: bundled:firewall-rule
  [2] pf: Block Detected (10 min ago)
       15 blocks from 10.0.0.1
       Sound: bundled:firewall-block
  [3] pf: Port Scan Detected (1 hour ago)
       Scan from 192.168.1.100
       Sound: bundled:firewall-scan

Firewall Statistics:
  Total Firewalls: 2
  Enabled: 2
  Blocks Today: 156

Sound Settings:
  Rule: bundled:firewall-rule
  Block: bundled:firewall-block
  Port Scan: bundled:firewall-scan

[Configure] [Add Firewall] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using pfctl, iptables, nft
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Firewall Monitor

```go
type FirewallMonitor struct {
    config        *FirewallMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    firewallState map[string]*FirewallInfo
    lastEventTime map[string]time.Time
    blockCounts   map[string]int
}

type FirewallInfo struct {
    Name      string
    Type      string // "pf", "iptables", "nftables"
    Status    string // "enabled", "disabled"
    RuleCount int
    LastChange time.Time
    Blocks     int64
}

func (m *FirewallMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.firewallState = make(map[string]*FirewallInfo)
    m.lastEventTime = make(map[string]time.Time)
    m.blockCounts = make(map[string]int)
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
    m.checkFirewallState()
}

func (m *FirewallMonitor) checkFirewallState() {
    // Check pf on macOS
    if runtime.GOOS == "darwin" {
        m.checkPF()
    }

    // Check iptables on Linux
    if runtime.GOOS == "linux" {
        m.checkIPTables()
        m.checkNftables()
    }
}

func (m *FirewallMonitor) checkPF() {
    info := &FirewallInfo{
        Name: "pf",
        Type: "pf",
    }

    // Check if pf is enabled
    cmd := exec.Command("pfctl", "-si")
    output, err := cmd.Output()
    if err != nil {
        info.Status = "disabled"
        m.processFirewallStatus(info)
        return
    }

    if strings.Contains(string(output), "Enabled") {
        info.Status = "enabled"
    } else {
        info.Status = "disabled"
    }

    // Get rule count
    cmd = exec.Command("pfctl", "-sr", "-sn")
    rulesOutput, _ := cmd.Output()
    info.RuleCount = strings.Count(string(rulesOutput), "\n")

    // Get statistics
    cmd = exec.Command("pfctl", "-si")
    statsOutput, _ := cmd.Output()

    // Parse block count
    blockRe := regexp.MustEach(`(\d+)\s+packets\s+blocked`)
    matches := blockRe.FindStringSubmatch(string(statsOutput))
    if len(matches) >= 2 {
        info.Blocks, _ = strconv.ParseInt(matches[1], 10, 64)
    }

    m.processFirewallStatus(info)
}

func (m *FirewallMonitor) checkIPTables() {
    info := &FirewallInfo{
        Name: "iptables",
        Type: "iptables",
    }

    // Check if iptables exists
    cmd := exec.Command("iptables", "-L", "-n", "-c")
    _, err := cmd.Output()
    if err != nil {
        // iptables might not be available, try iptables-legacy or iptables-nft
        cmd = exec.Command("iptables-legacy", "-L", "-n", "-c")
        _, err = cmd.Output()
    }

    if err != nil {
        info.Status = "disabled"
        m.processFirewallStatus(info)
        return
    }

    info.Status = "enabled"

    // Count rules
    cmd = exec.Command("iptables", "-L", "-n")
    rulesOutput, _ := cmd.Output()
    info.RuleCount = strings.Count(string(rulesOutput), "Chain")

    // Get block counts from LOG rules or counters
    m.processFirewallStatus(info)
}

func (m *FirewallMonitor) checkNftables() {
    info := &FirewallInfo{
        Name: "nftables",
        Type: "nftables",
    }

    // Check if nftables is available
    cmd := exec.Command("nft", "list", "tables")
    _, err := cmd.Output()
    if err != nil {
        return // nftables not available
    }

    info.Status = "enabled"

    // Get rule count
    cmd = exec.Command("nft", "list", "ruleset")
    rulesOutput, _ := cmd.Output()
    info.RuleCount = strings.Count(string(rulesOutput), "type")

    m.processFirewallStatus(info)
}

func (m *FirewallMonitor) processFirewallStatus(info *FirewallInfo) {
    lastInfo := m.firewallState[info.Name]

    if lastInfo == nil {
        m.firewallState[info.Name] = info
        return
    }

    // Check for rule changes
    if info.RuleCount != lastInfo.RuleCount {
        if m.config.SoundOnRule {
            m.onRuleChanged(info, info.RuleCount-lastInfo.RuleCount)
        }
    }

    // Check for block count changes (potential attack)
    blockIncrease := info.Blocks - lastInfo.Blocks
    if blockIncrease >= int64(m.config.BlockThreshold) {
        if m.config.SoundOnBlock && m.shouldAlert(info.Name+"block", 5*time.Minute) {
            m.onBlockDetected(info, int(blockIncrease))
        }
    }

    m.firewallState[info.Name] = info
}

func (m *FirewallMonitor) onRuleChanged(info *FirewallInfo, change int) {
    key := fmt.Sprintf("rule:%s", info.Name)
    if m.shouldAlert(key, 2*time.Minute) {
        sound := m.config.Sounds["rule"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FirewallMonitor) onBlockDetected(info *FirewallInfo, count int) {
    key := fmt.Sprintf("block:%s", info.Name)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["block"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FirewallMonitor) onPortScanDetected(info *FirewallInfo) {
    key := fmt.Sprintf("scan:%s", info.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["port_scan"]
        if sound != "" {
            m.player.Play(sound, 0.6)
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
| pfctl | System Tool | Free | Packet filter control (macOS) |
| iptables | System Tool | Free | Firewall (Linux) |
| nft | System Tool | Free | nftables (Linux) |

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
