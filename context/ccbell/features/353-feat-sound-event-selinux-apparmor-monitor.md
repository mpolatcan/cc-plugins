# Feature: Sound Event SELinux/AppArmor Monitor

Play sounds for mandatory access control events and policy violations.

## Summary

Monitor SELinux or AppArmor enforcement events, policy violations, and mode changes, playing sounds for MAC events.

## Motivation

- Security policy awareness
- Violation detection
- Enforcement mode feedback
- Policy change alerts
- Access control monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### SELinux/AppArmor Events

| Event | Description | Example |
|-------|-------------|---------|
| AVC Denial | Access vector cache denial | denied read |
| Policy Loaded | New policy loaded | policy.31 |
| Mode Changed | Enforcement mode changed | enforcing -> permissive |
| Context Changed | Process context changed | new context assigned |
| Boolean Changed | Boolean value changed | httpd_can_network_connect |

### Configuration

```go
type MACMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    MACType           string            `json:"mac_type"` // "selinux", "apparmor"
    SoundOnDenial     bool              `json:"sound_on_denial"`
    SoundOnPolicy     bool              `json:"sound_on_policy"`
    SoundOnMode       bool              `json:"sound_on_mode"`
    SoundOnBoolean    bool              `json:"sound_on_boolean"`
    WatchProcesses    []string          `json:"watch_processes"` // "httpd", "mysqld", "*"
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}

type MACEvent struct {
    Process     string
    Context     string
    Operation   string
    Resource    string
    Result      string // "denied", "allowed"
    MACType     string // "SELinux", "AppArmor"
    EventType   string // "denial", "policy", "mode", "boolean"
}
```

### Commands

```bash
/ccbell:mac status                    # Show MAC status
/ccbell:mac type selinux              # Set MAC type
/ccbell:mac add httpd                 # Add process to watch
/ccbell:mac sound denial <sound>
/ccbell:mac test                      # Test MAC sounds
```

### Output

```
$ ccbell:mac status

=== Sound Event SELinux/AppArmor Monitor ===

Status: Enabled
MAC Type: SELinux
Denial Sounds: Yes
Policy Sounds: Yes

Current Mode: Enforcing
Policy Version: 33.1
Policy Date: 2024-01-15

Recent Events:
  [1] httpd: AVC Denial (5 min ago)
       Operation: read, Resource: /var/www/html/file.html
       Result: denied
  [2] mysqld: Context Changed (10 min ago)
       New context: system_u:system_r:mysqld_t:s0
  [3] system: Boolean Changed (1 hour ago)
       httpd_can_network_connect: off -> on

SELinux Statistics:
  Denials Today: 15
  Policy Reloads: 2
  Mode Changes: 0

AppArmor Profiles:
  [1] /usr/sbin/httpd (enforce)
  [2] /usr/sbin/mysqld (enforce)

Sound Settings:
  Denial: bundled:mac-denial
  Policy: bundled:mac-policy
  Mode: bundled:mac-mode

[Configure] [Set Type] [Test All]
```

---

## Audio Player Compatibility

MAC monitoring doesn't play sounds directly:
- Monitoring feature using auditd/aa-status
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SELinux/AppArmor Monitor

```go
type MACMonitor struct {
    config          *MACMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    macState        *MACState
    denialState     map[string]int
    lastEventTime   map[string]time.Time
}

type MACState struct {
    Mode         string // "enforcing", "permissive", "disabled"
    PolicyVersion string
    PolicyDate    time.Time
    LastUpdate   time.Time
}

func (m *MACMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.denialState = make(map[string]int)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *MACMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotMACState()

    for {
        select {
        case <-ticker.C:
            m.checkMACState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *MACMonitor) snapshotMACState() {
    if runtime.GOOS != "linux" {
        return
    }

    // Check for SELinux
    selinuxPath := "/sys/fs/selinux/enforce"
    if _, err := os.Stat(selinuxPath); err == nil {
        m.config.MACType = "selinux"
        m.readSELinuxState()
    }

    // Check for AppArmor
    apparmorPath := "/sys/kernel/security/codearmor"
    if _, err := os.Stat(apparmorPath); err == nil {
        m.config.MACType = "apparmor"
        m.readAppArmorState()
    }
}

func (m *MACMonitor) checkMACState() {
    if m.config.MACType == "selinux" {
        m.readSELinuxState()
        m.readAuditLogs()
    } else if m.config.MACType == "apparmor" {
        m.readAppArmorState()
    }
}

func (m *MACMonitor) readSELinuxState() {
    // Read SELinux mode
    modePath := "/sys/fs/selinux/enforce"
    data, err := os.ReadFile(modePath)
    if err == nil {
        mode := "permissive"
        if strings.TrimSpace(string(data)) == "1" {
            mode = "enforcing"
        }

        if m.macState == nil || m.macState.Mode != mode {
            m.onModeChanged(mode)
        }
    }

    // Get policy version
    cmd := exec.Command("sestatus", "-v")
    output, err := cmd.Output()
    if err == nil {
        re := regexp.MustCompile(`Loaded policy name:\s+(\S+)`)
        match := re.FindStringSubmatch(string(output))
        if match != nil {
            if m.macState == nil {
                m.macState = &MACState{}
            }
            m.macState.PolicyVersion = match[1]
        }
    }
}

func (m *MACMonitor) readAuditLogs() {
    // Read from audit logs or journalctl
    cmd := exec.Command("journalctl", "-k", "--since=5m", "--grep=AVC", "-o", "json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse audit logs for AVC denials
    m.parseAuditOutput(string(output))
}

func (m *MACMonitor) parseAuditOutput(output string) {
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "AVC") && strings.Contains(line, "denied") {
            m.onAVCDenial(line)
        }
    }
}

func (m *MACMonitor) readAppArmorState() {
    cmd := exec.Command("aa-status", "--json")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse AppArmor status
    // Check for mode changes
}

func (m *MACMonitor) onAVCDenial(line string) {
    if !m.config.SoundOnDenial {
        return
    }

    // Extract process name
    re := regexp.MustCompile(`comm=\"([^\"]+)\"`)
    match := re.FindStringSubmatch(line)
    if match == nil {
        return
    }

    process := match[1]
    if !m.shouldWatchProcess(process) {
        return
    }

    key := fmt.Sprintf("denial:%s", process)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["denial"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *MACMonitor) onModeChanged(newMode string) {
    if !m.config.SoundOnMode {
        return
    }

    key := fmt.Sprintf("mode:%s", newMode)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["mode"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }

    if m.macState == nil {
        m.macState = &MACState{}
    }
    m.macState.Mode = newMode
}

func (m *MACMonitor) onPolicyLoaded() {
    if !m.config.SoundOnPolicy {
        return
    }

    key := "policy"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["policy"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *MACMonitor) shouldWatchProcess(name string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, p := range m.config.WatchProcesses {
        if p == "*" || p == name {
            return true
        }
    }

    return false
}

func (m *MACMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| sestatus | System Tool | Free | SELinux status |
| aa-status | System Tool | Free | AppArmor status |
| auditd | System Service | Free | Audit daemon |

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
| macOS | Supported | Uses AppArmor profiles |
| Linux | Supported | Uses SELinux or AppArmor |
