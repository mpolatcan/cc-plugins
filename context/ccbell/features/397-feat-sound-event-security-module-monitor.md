# Feature: Sound Event Security Module Monitor

Play sounds for SELinux/AppArmor policy events, denials, and mode changes.

## Summary

Monitor SELinux and AppArmor security modules for policy changes, access denials, and mode switches, playing sounds for security events.

## Motivation

- Security policy awareness
- Intrusion detection
- Access denial alerts
- Policy change tracking
- Compliance monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Security Module Events

| Event | Description | Example |
|-------|-------------|---------|
| Access Denied | SELinux/AppArmor denied | avc denied |
| Policy Loaded | New policy applied | policy reload |
| Mode Changed | Enforce/disabled/permissive | setenforce |
| Context Changed | Label changed | chcon |
| Booleans Changed | Boolean toggle | httpd_can_network |

### Configuration

```go
type SecurityModuleMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    ModuleType        string            `json:"module_type"` // "selinux", "apparmor", "auto"
    WatchProcesses    []string          `json:"watch_processes"` // "httpd", "mysqld", "*"
    SoundOnDenial     bool              `json:"sound_on_denial"`
    SoundOnModeChange bool              `json:"sound_on_mode_change"`
    SoundOnPolicyLoad bool              `json:"sound_on_policy_load"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:selinux status                 # Show security module status
/ccbell:selinux mode enforce           # Set SELinux mode
/ccbell:selinux sound denial <sound>
/ccbell:selinux sound mode <sound>
/ccbell:selinux test                   # Test security sounds
```

### Output

```
$ ccbell:selinux status

=== Sound Event Security Module Monitor ===

Status: Enabled
Module: SELinux
Mode: Enforcing
Denial Sounds: Yes
Mode Change Sounds: Yes

Current State:
  SELinux Status: Enabled
  Current Mode: Enforcing
  Policy Version: 34.1
  Load Time: 2 days ago

Watched Processes: 3

Recent Denials:

[1] httpd (5 min ago)
    Type: AVC
    Denial: denied { getattr } for pid=1234
    Path: /var/www/html/config.php
    Context: system_u:object_r:httpd_sys_content_t
    Sound: bundled:selinux-httpd

[2] mysqld (1 hour ago)
    Type: AVC
    Denial: denied { write } for pid=5678
    Path: /var/log/mysql/error.log
    Context: system_u:object_r:mysqld_log_t
    Sound: bundled:selinux-mysql

[3] dockerd (2 hours ago)
    Type: AVC
    Denial: denied { link } for pid=9012
    Path: /var/lib/docker
    Context: container_var_lib_t
    Sound: bundled:selinux-docker

AppArmor Profiles:
  /usr/sbin/nginx (enforce)
  /usr/sbin/mysql (enforce)
  /usr/bin/docker (enforce)

Recent Events:
  [1] httpd: Access Denied (5 min ago)
       config.php access
  [2] SELinux: Mode Changed (1 day ago)
       Permissive -> Enforcing
  [3] Policy: Loaded (3 days ago)
       Version 34.1

Statistics:
  Denials Today: 12
  Denials This Week: 45
  Mode Changes: 2

Sound Settings:
  Denial: bundled:selinux-denial
  Mode Change: bundled:selinux-mode
  Policy Load: bundled:selinux-policy

[Configure] [Test All]
```

---

## Audio Player Compatibility

Security module monitoring doesn't play sounds directly:
- Monitoring feature using ausearch/aureport/aa-status
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Security Module Monitor

```go
type SecurityModuleMonitor struct {
    config          *SecurityModuleMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    moduleState     *SecurityModuleInfo
    denialState     map[string]int
    lastEventTime   map[string]time.Time
    lastCheckTime   time.Time
}

type SecurityModuleInfo struct {
    Type     string // "selinux", "apparmor"
    Mode     string // "enforcing", "permissive", "disabled", "enforce", "complaint"
    Enabled  bool
    Version  string
    LastLoad time.Time
}

func (m *SecurityModuleMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.moduleState = &SecurityModuleInfo{}
    m.denialState = make(map[string]int)
    m.lastEventTime = make(map[string]time.Time)
    m.lastCheckTime = time.Now()
    go m.monitor()
}

func (m *SecurityModuleMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Detect module type
    m.detectModuleType()

    // Initial snapshot
    m.checkModuleState()

    for {
        select {
        case <-ticker.C:
            m.checkModuleState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SecurityModuleMonitor) detectModuleType() {
    // Check for SELinux
    cmd := exec.Command("getenforce")
    if err := cmd.Run(); err == nil {
        m.moduleState.Type = "selinux"
        return
    }

    // Check for AppArmor
    cmd = exec.Command("which", "aa-status")
    if err := cmd.Run(); err == nil {
        m.moduleState.Type = "apparmor"
        return
    }
}

func (m *SecurityModuleMonitor) checkModuleState() {
    if m.moduleState.Type == "selinux" {
        m.checkSELinuxState()
    } else if m.moduleState.Type == "apparmor" {
        m.checkAppArmorState()
    }

    // Check for new denials
    m.checkDenials()

    m.lastCheckTime = time.Now()
}

func (m *SecurityModuleMonitor) checkSELinuxState() {
    cmd := exec.Command("getenforce")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    mode := strings.TrimSpace(string(output))
    newMode := strings.ToLower(mode)

    lastMode := m.moduleState.Mode
    if lastMode != "" && lastMode != newMode {
        m.onModeChanged(newMode)
    }

    m.moduleState.Mode = newMode
    m.moduleState.Enabled = newMode != "disabled"

    // Get policy version
    cmd = exec.Command("sestatus", "-v")
    output, _ = cmd.Output()

    re := regexp.MustEach(`Loaded policy version: (\d+)`)
    matches := re.FindAllStringSubmatch(string(output), -1)
    if len(matches) > 0 {
        m.moduleState.Version = matches[0][1]
    }
}

func (m *SecurityModuleMonitor) checkAppArmorState() {
    cmd := exec.Command("aa-status", "--enabled")
    err := cmd.Run()
    m.moduleState.Enabled = err == nil

    // Get mode
    cmd = exec.Command("aa-status")
    output, err := cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.Contains(line, "enforce") {
                m.moduleState.Mode = "enforce"
                break
            } else if strings.Contains(line, "complaint") {
                m.moduleState.Mode = "complaint"
                break
            }
        }
    }
}

func (m *SecurityModuleMonitor) checkDenials() {
    since := m.lastCheckTime.Format("2006-01-02 15:04:05")

    var denials []string

    if m.moduleState.Type == "selinux" {
        denials = m.getSELinuxDenials(since)
    } else if m.moduleState.Type == "apparmor" {
        denials = m.getAppArmorDenials(since)
    }

    for _, denial := range denials {
        if _, exists := m.denialState[denial]; !exists {
            m.denialState[denial] = 1
            m.onAccessDenied(denial)
        }
    }
}

func (m *SecurityModuleMonitor) getSELinuxDenials(since string) []string {
    var denials []string

    cmd := exec.Command("ausearch", "-m", "AVC", "--since", since, "-i")
    output, err := cmd.Output()
    if err != nil {
        return denials
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "avc: denied") {
            // Extract process name
            re := regexp.MustEach(`scontext=([^ ]+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                scontext := matches[0][1]
                parts := strings.Split(scontext, ":")
                if len(parts) >= 3 {
                    process := strings.Split(parts[2], "_t")[0]
                    denials = append(denials, process)
                }
            }
        }
    }

    return denials
}

func (m *SecurityModuleMonitor) getAppArmorDenials(since string) []string {
    var denials []string

    // Check audit log
    cmd := exec.Command("journalctl", "-k", "--since", since, "--no-pager")
    output, _ := cmd.Output()

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "apparmor=") && strings.Contains(line, "DENIED") {
            re := regexp.MustEach(`profile=([^ ]+)`)
            matches := re.FindAllStringSubmatch(line, -1)
            if len(matches) > 0 {
                profile := matches[0][1]
                denials = append(denials, profile)
            }
        }
    }

    return denials
}

func (m *SecurityModuleMonitor) onAccessDenied(process string) {
    if !m.config.SoundOnDenial {
        return
    }

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

func (m *SecurityModuleMonitor) onModeChanged(newMode string) {
    if !m.config.SoundOnModeChange {
        return
    }

    key := fmt.Sprintf("mode:%s", newMode)
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["mode_change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SecurityModuleMonitor) shouldWatchProcess(process string) bool {
    if len(m.config.WatchProcesses) == 0 {
        return true
    }

    for _, p := range m.config.WatchProcesses {
        if p == "*" || strings.Contains(process, p) {
            return true
        }
    }

    return false
}

func (m *SecurityModuleMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| getenforce | System Tool | Free | SELinux mode |
| sestatus | System Tool | Free | SELinux status |
| ausearch | System Tool | Free | Audit search |
| aa-status | System Tool | Free | AppArmor status |

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
| macOS | Not Supported | No SELinux/AppArmor |
| Linux | Supported | Uses getenforce, aa-status |
