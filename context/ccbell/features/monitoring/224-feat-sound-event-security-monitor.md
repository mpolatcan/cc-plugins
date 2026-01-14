# Feature: Sound Event Security Monitor

Play sounds for security events and alerts.

## Summary

Monitor security-related events including failed login attempts, firewall alerts, file permission changes, and intrusion detection.

## Motivation

- Security breach awareness
- Failed authentication alerts
- Firewall event feedback
- Permission change detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Security Events

| Event | Description | Example |
|-------|-------------|---------|
| Failed Login | Authentication failed | Wrong password |
| SSH Failed | SSH login failed | Brute force attempt |
| Firewall Alert | Firewall blocked | Suspected intrusion |
| File Permission | Permissions changed | chmod 777 |
| sudo Usage | Elevated privilege used | Root access |
| Certificate Expiry | SSL cert expiring | < 30 days |

### Configuration

```go
type SecurityMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchSSH         bool              `json:"watch_ssh"`
    WatchFirewall    bool              `json:"watch_firewall"`
    WatchSudo        bool              `json:"watch_sudo"`
    WatchPermissions bool              `json:"watch_permissions"`
    WatchPaths       []string          `json:"watch_paths"` // Paths to watch
    Threshold        int               `json:"failed_login_threshold"` // 3 default
    Sounds           map[string]string `json:"sounds"`
}

type SecurityEvent struct {
    Type      string // "login", "ssh", "firewall", "permission", "sudo", "certificate"
    Source    string
    Message   string
    Severity  string // "low", "medium", "high", "critical"
    Timestamp time.Time
}
```

### Commands

```bash
/ccbell:security status           # Show security status
/ccbell:security ssh on           # Enable SSH monitoring
/ccbell:security firewall on      # Enable firewall monitoring
/ccbell:security threshold 5      # Set failed login threshold
/ccbell:security sound failed <sound>
/ccbell:security sound alert <sound>
/ccbell:security test             # Test security sounds
```

### Output

```
$ ccbell:security status

=== Sound Event Security Monitor ===

Status: Enabled
SSH Monitoring: Yes
Firewall Monitoring: Yes
Sudo Monitoring: Yes
Failed Login Threshold: 3

Recent Security Events:
  [1] SSH: Failed login from 203.0.113.50 (2 min ago)
       Severity: Medium - 1 attempt
       [Block IP] [Whitelist]

  [2] Sudo: Elevated privilege by user (1 hour ago)
       Command: /usr/sbin/visudo
       Severity: Low
       [Review]

  [3] File: Permissions changed (3 hours ago)
       Path: /Users/shared/scripts/run.sh
       Old: 644
       New: 755
       Severity: Low
       [Review]

Sound Settings:
  Failed Login: bundled:stop
  SSH Alert: bundled:stop
  Firewall Alert: bundled:stop

[Configure] [Test All] [View Logs]
```

---

## Audio Player Compatibility

Security monitoring doesn't play sounds directly:
- Monitoring feature using system logs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Security Monitor

```go
type SecurityMonitor struct {
    config          *SecurityMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    failedLogins    map[string]int
    lastLogPosition int64
}

func (m *SecurityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.failedLogins = make(map[string]int)
    go m.monitor()
}

func (m *SecurityMonitor) monitor() {
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkSecurityEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SecurityMonitor) checkSecurityEvents() {
    if m.config.WatchSSH {
        m.checkSSHEvents()
    }

    if m.config.WatchFirewall {
        m.checkFirewallEvents()
    }

    if m.config.WatchSudo {
        m.checkSudoEvents()
    }

    if m.config.WatchPermissions {
        m.checkPermissionEvents()
    }

    m.checkLoginEvents()
}

func (m *SecurityMonitor) checkSSHEvents() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSSSHEvents()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxSSHEvents()
    }
}

func (m *SecurityMonitor) checkMacOSSSHEvents() {
    // macOS: system log for SSH
    cmd := exec.Command("log", "show", "--predicate", "eventMessage CONTAINS 'sshd'",
        "--last", "5m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Failed password") || strings.Contains(line, "Invalid user") {
            m.parseSSHFailedLogin(line)
        }
    }
}

func (m *SecurityMonitor) checkLinuxSSHEvents() {
    // Linux: /var/log/auth.log
    logPath := "/var/log/auth.log"
    if _, err := os.Stat(logPath); os.IsNotExist(err) {
        logPath = "/var/log/secure"
    }

    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Failed password") ||
           strings.Contains(line, "Invalid user") ||
           strings.Contains(line, "Failed publickey") {
            m.parseSSHFailedLogin(line)
        }
    }
}

func (m *SecurityMonitor) parseSSHFailedLogin(line string) {
    // Extract IP address
    ipMatch := regexp.MustCompile(`(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})`).FindStringSubmatch(line)
    if ipMatch == nil {
        return
    }

    ip := ipMatch[1]
    m.failedLogins[ip]++

    if m.failedLogins[ip] >= m.config.Threshold {
        m.onSecurityAlert("ssh", ip,
            fmt.Sprintf("Multiple failed SSH attempts from %s (%d attempts)",
                ip, m.failedLogins[ip]), "high")
        m.failedLogins[ip] = 0 // Reset after alert
    } else {
        m.onSecurityEvent("ssh", ip, fmt.Sprintf("Failed SSH attempt from %s", ip), "low")
    }
}

func (m *SecurityMonitor) checkFirewallEvents() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSFirewallEvents()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxFirewallEvents()
    }
}

func (m *SecurityMonitor) checkMacOSFirewallEvents() {
    // macOS: application firewall logs
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'firewall' AND eventMessage CONTAINS 'deny'",
        "--last", "10m")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        m.onSecurityEvent("firewall", "unknown", line, "medium")
    }
}

func (m *SecurityMonitor) checkLinuxFirewallEvents() {
    // Linux: iptables or nft logs
    if m.isUFWActive() {
        m.checkUFWEvents()
    }

    if m.isiptablesActive() {
        m.checkIPTablesEvents()
    }
}

func (m *SecurityMonitor) isUFWActive() bool {
    cmd := exec.Command("ufw", "status")
    err := cmd.Run()
    return err == nil
}

func (m *SecurityMonitor) isiptablesActive() bool {
    cmd := exec.Command("iptables", "-L", "-n")
    err := cmd.Run()
    return err == nil
}

func (m *SecurityMonitor) checkUFWEvents() {
    logPath := "/var/log/ufw.log"
    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, "BLOCK") {
            m.onSecurityEvent("firewall", "unknown", line, "medium")
        }
    }
}

func (m *SecurityMonitor) checkIPTablesEvents() {
    cmd := exec.Command("iptables", "-L", "-v", "-n", "--line-numbers")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse for dropped packets
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "DROP") {
            m.onSecurityEvent("firewall", "unknown", line, "medium")
        }
    }
}

func (m *SecurityMonitor) checkSudoEvents() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSSudoEvents()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxSudoEvents()
    }
}

func (m *SecurityMonitor) checkMacOSSudoEvents() {
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'sudo' AND eventMessage CONTAINS 'COMMAND'",
        "--last", "1h")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        m.onSecurityEvent("sudo", "self", line, "low")
    }
}

func (m *SecurityMonitor) checkLinuxSudoEvents() {
    logPath := "/var/log/auth.log"
    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, "COMMAND=") && strings.Contains(line, "sudo") {
            m.onSecurityEvent("sudo", "unknown", line, "low")
        }
    }
}

func (m *SecurityMonitor) checkPermissionEvents() {
    for _, path := range m.config.WatchPaths {
        m.checkPathPermissions(path)
    }
}

func (m *SecurityMonitor) checkPathPermissions(path string) {
    info, err := os.Stat(path)
    if err != nil {
        return
    }

    // This is simplified - real implementation would watch for changes
    mode := info.Mode().Perm()
    if mode&0o077 != 0 {
        m.onSecurityEvent("permission", path,
            fmt.Sprintf("Permissions changed to %o", mode), "medium")
    }
}

func (m *SecurityMonitor) checkLoginEvents() {
    if runtime.GOOS == "darwin" {
        m.checkMacOSLoginEvents()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxLoginEvents()
    }
}

func (m *SecurityMonitor) checkMacOSLoginEvents() {
    cmd := exec.Command("log", "show", "--predicate",
        "eventMessage CONTAINS 'loginwindow' AND eventMessage CONTAINS 'authentication'",
        "--last", "1h")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "failed") || strings.Contains(line, "FAILED") {
            m.onSecurityEvent("login", "unknown", line, "medium")
        }
    }
}

func (m *SecurityMonitor) checkLinuxLoginEvents() {
    logPath := "/var/log/auth.log"
    data, err := os.ReadFile(logPath)
    if err != nil {
        return
    }

    lines := strings.Split(string(data), "\n")
    for _, line := range lines {
        if strings.Contains(line, "FAILED LOGIN") {
            m.onSecurityEvent("login", "unknown", line, "medium")
        }
    }
}

func (m *SecurityMonitor) onSecurityEvent(eventType, source, message, severity string) {
    sound := m.config.Sounds[eventType]
    if sound != "" {
        if severity == "high" || severity == "critical" {
            m.player.Play(sound, 0.7)
        } else {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SecurityMonitor) onSecurityAlert(eventType, source, message, severity string) {
    sound := m.config.Sounds["alert"]
    if sound != "" {
        m.player.Play(sound, 0.8)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| log | System Tool | Free | macOS system log |
| /var/log/auth.log | File | Free | Linux auth log |
| /var/log/secure | File | Free | Linux secure log |
| iptables | System Tool | Free | Linux firewall |
| ufw | APT | Free | Linux firewall |

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
| macOS | Supported | Uses log command |
| Linux | Supported | Uses /var/log and iptables |
| Windows | Not Supported | ccbell only supports macOS/Linux |
