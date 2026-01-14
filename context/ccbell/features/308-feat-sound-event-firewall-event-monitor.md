# Feature: Sound Event Firewall Event Monitor

Play sounds for firewall rule changes and blocked connection events.

## Summary

Monitor firewall activity, rule changes, and blocked connections, playing sounds for security events.

## Motivation

- Security monitoring
- Rule change awareness
- Intrusion detection feedback
- Network security alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Firewall Events

| Event | Description | Example |
|-------|-------------|---------|
| Rule Added | New firewall rule | allow port 8080 |
| Rule Removed | Firewall rule deleted | remove port 22 |
| Blocked Connection | Connection denied | DROP packet |
| Port Scan Detected | Scan attempt | Multiple ports |

### Configuration

```go
type FirewallMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchChains       []string          `json:"watch_chains"` // "INPUT", "OUTPUT"
    SoundOnBlock      bool              `json:"sound_on_block"]
    SoundOnRuleChange bool              `json:"sound_on_rule_change"]
    SoundOnScan       bool              `json:"sound_on_scan"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type FirewallEvent struct {
    Chain       string
    RuleNum     int
    Action      string // "ACCEPT", "DROP", "REJECT"
    Protocol    string
    Port        int
    SourceIP    string
    EventType   string // "block", "rule_add", "rule_remove", "scan"
}
```

### Commands

```bash
/ccbell:firewall status               # Show firewall status
/ccbell:firewall add INPUT            # Add chain to watch
/ccbell:firewall sound block <sound>
/ccbell:firewall sound scan <sound>
/ccbell:firewall test                 # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Monitor ===

Status: Enabled
Block Sounds: Yes
Scan Sounds: Yes

Current Rules: 45

[1] INPUT (Inbound)
    Rules: 30
    Last Change: 1 hour ago
    Blocked: 50/hour
    Sound: bundled:stop

[2] OUTPUT (Outbound)
    Rules: 15
    Last Change: 2 hours ago
    Blocked: 10/hour
    Sound: bundled:stop

Recent Events:
  [1] Port Scan Detected (5 min ago)
       10 connections to ports 1-100
  [2] Connection Blocked (10 min ago)
       TCP 192.168.1.100:12345 -> 22
  [3] Rule Added (1 hour ago)
       ACCEPT TCP 8080

Firewall Statistics:
  Total blocks today: 1,234
  Port scans detected: 5

Sound Settings:
  Block: bundled:firewall-block
  Rule Change: bundled:stop
  Scan: bundled:firewall-scan

[Configure] [Add Chain] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using firewall tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Firewall Event Monitor

```go
type FirewallMonitor struct {
    config           *FirewallMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    firewallRules    map[string]int
    blockedCount     map[string]int
    lastBlockTime    map[string]time.Time
    scanDetection    *ScanDetector
}

type ScanDetector struct {
    SourceIPs       map[string][]time.Time
    DetectionWindow time.Duration
}

func (m *FirewallMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.firewallRules = make(map[string]int)
    m.blockedCount = make(map[string]int)
    m.lastBlockTime = make(map[string]time.Time)
    m.scanDetection = &ScanDetector{
        SourceIPs:       make(map[string][]time.Time),
        DetectionWindow: 60 * time.Second,
    }
    go m.monitor()
}

func (m *FirewallMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotFirewallRules()

    for {
        select {
        case <-ticker.C:
            m.checkFirewallEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *FirewallMonitor) snapshotFirewallRules() {
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinFirewall()
    } else {
        m.snapshotLinuxFirewall()
    }
}

func (m *FirewallMonitor) snapshotDarwinFirewall() {
    // Use pfctl to get rules
    cmd := exec.Command("pfctl", "-sr")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePFOutput(string(output), "darwin")
}

func (m *FirewallMonitor) snapshotLinuxFirewall() {
    // Use iptables to get rules
    cmd := exec.Command("iptables", "-L", "-n", "-v", "--line-numbers")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPTablesOutput(string(output))
}

func (m *FirewallMonitor) checkFirewallEvents() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinFirewall()
    } else {
        m.checkLinuxFirewall()
    }
}

func (m *FirewallMonitor) checkDarwinFirewall() {
    // Check pfctl for rule changes
    cmd := exec.Command("pfctl", "-sr")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parsePFOutput(string(output), "darwin")
}

func (m *FirewallMonitor) checkLinuxFirewall() {
    // Check iptables for changes
    cmd := exec.Command("iptables", "-L", "-n", "-v", "--line-numbers")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseIPTablesOutput(string(output))
}

func (m *FirewallMonitor) parsePFOutput(output string, os string) {
    lines := strings.Split(output, "\n")
    ruleCount := 0

    for _, line := range lines {
        if strings.HasPrefix(line, "pass") || strings.HasPrefix(line, "block") {
            ruleCount++
        }
    }

    m.firewallRules["pf"] = ruleCount
}

func (m *FirewallMonitor) parseIPTablesOutput(output string) {
    lines := strings.Split(output, "\n")
    inputRules := 0
    outputRules := 0

    for _, line := range lines {
        if strings.HasPrefix(line, "Chain") {
            continue
        }
        if strings.HasPrefix(line, "target") || strings.HasPrefix(line, "Chain") {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        chain := parts[2]
        if chain == "INPUT" {
            inputRules++
        } else if chain == "OUTPUT" {
            outputRules++
        }
    }

    m.firewallRules["INPUT"] = inputRules
    m.firewallRules["OUTPUT"] = outputRules
}

func (m *FirewallMonitor) onBlockedConnection(event *FirewallEvent) {
    if !m.config.SoundOnBlock {
        return
    }

    // Check for port scan pattern
    if m.isPortScan(event.SourceIP) {
        m.onPortScanDetected(event.SourceIP)
        return
    }

    key := fmt.Sprintf("block:%s:%d", event.SourceIP, event.Port)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["block"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FirewallMonitor) onPortScanDetected(sourceIP string) {
    if !m.config.SoundOnScan {
        return
    }

    key := fmt.Sprintf("scan:%s", sourceIP)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["scan"]
        if sound != "" {
            m.player.Play(sound, 0.7)
        }
    }
}

func (m *FirewallMonitor) onFirewallRuleChange(chain string, change int) {
    if !m.config.SoundOnRuleChange {
        return
    }

    sound := m.config.Sounds["rule_change"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *FirewallMonitor) isPortScan(sourceIP string) bool {
    // Detect multiple connection attempts to different ports
    now := time.Now()
    windowStart := now.Add(-m.scanDetection.DetectionWindow * time.Second)

    // Add this attempt
    m.scanDetection.SourceIPs[sourceIP] = append(
        m.scanDetection.SourceIPs[sourceIP],
        now,
    )

    // Filter to detection window
    var recentAttempts []time.Time
    for _, t := range m.scanDetection.SourceIPs[sourceIP] {
        if t.After(windowStart) {
            recentAttempts = append(recentAttempts, t)
        }
    }
    m.scanDetection.SourceIPs[sourceIP] = recentAttempts

    // Port scan: more than 10 connections to different ports in window
    return len(recentAttempts) > 10
}

func (m *FirewallMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastBlockTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastBlockTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| pfctl | System Tool | Free | macOS pf firewall |
| iptables | System Tool | Free | Linux firewall |

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
| Linux | Supported | Uses iptables |
| Windows | Not Supported | ccbell only supports macOS/Linux |
