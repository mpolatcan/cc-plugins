# Feature: Sound Event Firewall Status Monitor

Play sounds for firewall rule changes, blocked connections, and security alerts.

## Summary

Monitor firewall status, rule changes, and blocked connection attempts, playing sounds for firewall events.

## Motivation

- Firewall awareness
- Security alerts
- Rule change tracking
- Blocked connection detection
- Network security feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Firewall Events

| Event | Description | Example |
|-------|-------------|---------|
| Firewall Active | Firewall enabled | Active |
| Firewall Inactive | Firewall disabled | Inactive |
| Rule Added | New rule | Allow port 8080 |
| Rule Deleted | Rule removed | Block port 22 |
| Blocked Connection | Connection denied | 10.0.0.1:12345 |
| Port Scanned | Port scan detected | Multiple ports |

### Configuration

```go
type FirewallMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchFirewall     bool              `json:"watch_firewall"` // true default
    WatchRules        bool              `json:"watch_rules"` // true default
    WatchBlocked      bool              `json:"watch_blocked"` // false default
    SoundOnActive     bool              `json:"sound_on_active"`
    SoundOnInactive   bool              `json:"sound_on_inactive"`
    SoundOnRuleAdd    bool              `json:"sound_on_rule_add"`
    SoundOnRuleDelete bool              `json:"sound_on_rule_delete"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:firewall status             # Show firewall status
/ccbell:firewall sound active <sound>
/ccbell:firewall sound inactive <sound>
/ccbell:firewall test               # Test firewall sounds
```

### Output

```
$ ccbell:firewall status

=== Sound Event Firewall Status Monitor ===

Status: Enabled
Watch Rules: Yes

Firewall Status:

[1] pf (Packet Filter) - macOS
    Status: ENABLED
    Config: /etc/pf.conf
    Rules: 45
    Last Change: Jan 14, 2026 02:00
    Sound: bundled:firewall-pf

[2] ufw (Uncomplicated Firewall) - Linux
    Status: ENABLED
    Rules: 25
    Inactive: 2
    Last Change: Jan 13, 2026 14:30
    Sound: bundled:firewall-ufw

Firewall Rules:

  [1] ALLOW TCP 22 -> Anywhere
      Status: Active
      Added: Jan 1, 2026
      Sound: bundled:firewall-allow

  [2] ALLOW TCP 80 -> Anywhere
      Status: Active
      Added: Dec 15, 2025
      Sound: bundled:firewall-allow

  [3] DENY TCP 23 -> Anywhere
      Status: Active
      Added: Jan 10, 2026
      Sound: bundled:firewall-deny

Recent Events:
  [1] Firewall: Active (1 week ago)
       ufw enabled
       Sound: bundled:firewall-active
  [2] Rule Added (2 weeks ago)
       ALLOW TCP 443 -> Anywhere
       Sound: bundled:firewall-rule-add
  [3] Rule Deleted (3 weeks ago)
       DENY TCP 23 -> Anywhere
       Sound: bundled:firewall-rule-del

Firewall Statistics:
  Active Rules: 25
  Rules Today: 0
  Blocked Today: 0

Sound Settings:
  Active: bundled:firewall-active
  Inactive: bundled:firewall-inactive
  Rule Add: bundled:firewall-rule-add
  Rule Delete: bundled:firewall-rule-del

[Configure] [Test All]
```

---

## Audio Player Compatibility

Firewall monitoring doesn't play sounds directly:
- Monitoring feature using pfctl/ufw/iptables
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Firewall Status Monitor

```go
type FirewallMonitor struct {
    config          *FirewallMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    firewallState   *FirewallInfo
    ruleHashes      map[string]string
    lastEventTime   map[string]time.Time
}

type FirewallInfo struct {
    Name           string
    Status         string // "active", "inactive", "unknown"
    RuleCount      int
    LastRuleChange time.Time
}

func (m *FirewallMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.firewallState = &FirewallInfo{}
    m.ruleHashes = make(map[string]string)
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
    m.checkFirewallState()
}

func (m *FirewallMonitor) checkFirewallState() {
    info := m.getFirewallInfo()
    if info == nil {
        return
    }

    m.processFirewallStatus(info)
}

func (m *FirewallMonitor) getFirewallInfo() *FirewallInfo {
    info := &FirewallInfo{}

    // Detect firewall type and check status
    if runtime.GOOS == "darwin" {
        m.checkDarwinFirewall(info)
    } else {
        m.checkLinuxFirewall(info)
    }

    if info.Name == "" {
        return nil
    }

    return info
}

func (m *FirewallMonitor) checkDarwinFirewall(info *FirewallInfo) {
    // Check pf (Packet Filter) status
    cmd := exec.Command("pfctl", "-s", "status")
    output, err := cmd.Output()
    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "Enabled") {
            info.Status = "active"
            info.Name = "pf"
        } else {
            info.Status = "inactive"
            info.Name = "pf"
        }
    }

    // Get rule count
    cmd = exec.Command("pfctl", "-sr", "-v")
    output, err = cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        info.RuleCount = 0
        for _, line := range lines {
            if strings.HasPrefix(line, "pass") || strings.HasPrefix(line, "block") {
                info.RuleCount++
            }
        }
    }

    // Check application firewall
    cmd = exec.Command("defaults", "read", "/Library/Preferences/com.apple.alf", "globalstate")
    output, err = cmd.Output()
    if err == nil {
        state := strings.TrimSpace(string(output))
        if state == "1" {
            info.Name = "ALF (Application Firewall)"
        }
    }
}

func (m *FirewallMonitor) checkLinuxFirewall(info *FirewallInfo) {
    // Check ufw status
    cmd := exec.Command("ufw", "status")
    output, err := cmd.Output()
    if err == nil {
        outputStr := string(output)
        if strings.Contains(outputStr, "Status: active") {
            info.Status = "active"
            info.Name = "ufw"

            // Count rules
            lines := strings.Split(outputStr, "\n")
            for _, line := range lines {
                if strings.HasPrefix(line, String) ||
                   strings.HasPrefix(line, "ALLOW") ||
                   strings.HasPrefix(line, "DENY") ||
                   strings.HasPrefix(line, "LIMIT") {
                    info.RuleCount++
                }
            }
            return
        } else if strings.Contains(outputStr, "Status: inactive") {
            info.Status = "inactive"
            info.Name = "ufw"
            return
        }
    }

    // Check iptables
    cmd = exec.Command("iptables", "-L", "-n", "-v")
    output, err = cmd.Output()
    if err == nil {
        info.Name = "iptables"
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.HasPrefix(line, "Chain") {
                continue
            }
            if strings.TrimSpace(line) != "" {
                info.RuleCount++
            }
        }
        if info.RuleCount > 0 {
            info.Status = "active"
        } else {
            info.Status = "inactive"
        }
    }

    // Check firewalld
    cmd = exec.Command("firewall-cmd", "--state")
    err = cmd.Run()
    if err == nil {
        info.Name = "firewalld"
        info.Status = "active"

        cmd = exec.Command("firewall-cmd", "--list-all")
        output, _ = cmd.Output()
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.HasPrefix(line, "services:") ||
               strings.HasPrefix(line, "ports:") {
                info.RuleCount++
            }
        }
    }
}

func (m *FirewallMonitor) processFirewallStatus(info *FirewallInfo) {
    if m.firewallState == nil {
        m.firewallState = info
        if info.Status == "active" && m.config.SoundOnActive {
            m.onFirewallActive(info)
        } else if info.Status == "inactive" && m.config.SoundOnInactive {
            m.onFirewallInactive(info)
        }
        return
    }

    // Check for status changes
    if info.Status != m.firewallState.Status {
        if info.Status == "active" {
            if m.config.SoundOnActive {
                m.onFirewallActive(info)
            }
        } else if info.Status == "inactive" {
            if m.config.SoundOnInactive {
                m.onFirewallInactive(info)
            }
        }
    }

    // Check for rule changes
    if info.RuleCount != m.firewallState.RuleCount {
        if info.RuleCount > m.firewallState.RuleCount {
            if m.config.SoundOnRuleAdd {
                m.onRuleAdded(info)
            }
        } else if info.RuleCount < m.firewallState.RuleCount {
            if m.config.SoundOnRuleDelete {
                m.onRuleDeleted(info)
            }
        }
    }

    m.firewallState = info
}

func (m *FirewallMonitor) onFirewallActive(info *FirewallInfo) {
    key := "firewall:active"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["active"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *FirewallMonitor) onFirewallInactive(info *FirewallInfo) {
    key := "firewall:inactive"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["inactive"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *FirewallMonitor) onRuleAdded(info *FirewallInfo) {
    key := "firewall:rule-add"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["rule_add"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *FirewallMonitor) onRuleDeleted(info *FirewallInfo) {
    key := "firewall:rule-delete"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["rule_delete"]
        if sound != "" {
            m.player.Play(sound, 0.3)
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
| pfctl | System Tool | Free | Packet filter (macOS) |
| ufw | System Tool | Free | Uncomplicated firewall (Linux) |
| iptables | System Tool | Free | IP tables (Linux) |
| firewall-cmd | System Tool | Free | firewalld (Linux) |

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
| Linux | Supported | Uses ufw, iptables, firewalld |
