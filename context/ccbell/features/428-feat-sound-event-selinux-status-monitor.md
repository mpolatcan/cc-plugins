# Feature: Sound Event SELinux Status Monitor

Play sounds for SELinux mode changes, policy reloads, and security context alerts.

## Summary

Monitor SELinux status, mode changes, and policy events, playing sounds for SELinux status changes.

## Motivation

- Security awareness
- SELinux mode tracking
- Policy change alerts
- Security context monitoring
- Compliance feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### SELinux Status Events

| Event | Description | Example |
|-------|-------------|---------|
| Mode Enforcing | SELinux enforcing | Enforcing |
| Mode Permissive | SELinux permissive | Permissive |
| Mode Disabled | SELinux disabled | Disabled |
| Policy Reloaded | Policy updated | Reload |
| AVC Denied | Access denied | 5 denials |
| Context Changed | Label changed | new context |

### Configuration

```go
type SELinuxMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchMode         bool              `json:"watch_mode"` // true default
    WatchPolicy       bool              `json:"watch_policy"` // true default
    WatchAVC          bool              `json:"watch_avc"` // false default
    SoundOnEnforce    bool              `json:"sound_on_enforce"`
    SoundOnPermissive bool              `json:"sound_on_permissive"`
    SoundOnDisabled   bool              `json:"sound_on_disabled"`
    SoundOnAVC        bool              `json:"sound_on_avc"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:selinux status              # Show SELinux status
/ccbell:selinux sound enforce <sound>
/ccbell:selinux sound permissive <sound>
/ccbell:selinux test                # Test SELinux sounds
```

### Output

```
$ ccbell:selinux status

=== Sound Event SELinux Status Monitor ===

Status: Enabled
Watch Mode: Yes
Watch Policy: Yes

SELinux Status:

[1] System Mode
    Current: ENFORCING
    Config: Enforcing
    Ready: Yes
    Sound: bundled:selinux-enforce

[2] Policy
    Version: 33.1
    Loaded: Yes
    Last Reload: Jan 14, 2026 02:00
    Sound: bundled:selinux-policy

[3] AVC Statistics
    Today: 5 denials
    This Week: 23 denials
    Most Common: httpd_t (web content)

Recent Events:
  [1] SELinux Mode: Enforcing (1 week ago)
       System started in enforcing mode
       Sound: bundled:selinux-enforce
  [2] Policy Reloaded (2 weeks ago)
       Policy version 33.0 -> 33.1
       Sound: bundled:selinux-policy
  [3] AVC Denial (1 day ago)
       httpd_t denied read on var_log_t
       Sound: bundled:selinux-avc

SELinux Statistics:
  Days in Enforcing: 30
  Policy Reloads: 2
  Total AVC Denials: 45

Sound Settings:
  Enforce: bundled:selinux-enforce
  Permissive: bundled:selinux-permissive
  Disabled: bundled:selinux-disabled
  AVC: bundled:selinux-avc

[Configure] [Test All]
```

---

## Audio Player Compatibility

SELinux monitoring doesn't play sounds directly:
- Monitoring feature using getenforce/sestatus/ausearch
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### SELinux Status Monitor

```go
type SELinuxMonitor struct {
    config          *SELinuxMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    selinuxState    *SELinuxInfo
    lastEventTime   map[string]time.Time
}

type SELinuxInfo struct {
    CurrentMode     string // "Enforcing", "Permissive", "Disabled"
    ConfigMode      string
    PolicyLoaded    bool
    PolicyVersion   string
    LastReload      time.Time
    AVCCount        int
    AVCChange       int
}

func (m *SELinuxMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.selinuxState = &SELinuxInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SELinuxMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSELinuxState()

    for {
        select {
        case <-ticker.C:
            m.checkSELinuxState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SELinuxMonitor) snapshotSELinuxState() {
    m.checkSELinuxState()
}

func (m *SELinuxMonitor) checkSELinuxState() {
    info := m.getSELinuxInfo()
    if info == nil {
        return
    }

    m.processSELinuxStatus(info)
}

func (m *SELinuxMonitor) getSELinuxInfo() *SELinuxInfo {
    info := &SELinuxInfo{}

    // Check if SELinux is available
    if !m.isSELinuxAvailable() {
        return nil
    }

    // Get current mode
    cmd := exec.Command("getenforce")
    output, err := cmd.Output()
    if err == nil {
        info.CurrentMode = strings.TrimSpace(string(output))
    }

    // Get configured mode
    cmd = exec.Command("sestatus")
    output, err = cmd.Output()
    if err == nil {
        outputStr := string(output)

        // Parse configured mode
        configRe := regexp.MustEach(`Loaded policy name:\s+(.+)`)
        matches := configRe.FindStringSubmatch(outputStr)
        if len(matches) >= 2 {
            info.ConfigMode = matches[1]
        }

        // Check if policy is loaded
        if strings.Contains(outputStr, "Policy from config file:") {
            info.PolicyLoaded = true
        }
    }

    // Get policy version
    cmd = exec.Command("semodule", "-ls")
    output, err = cmd.Output()
    if err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.HasPrefix(line, "base") {
                parts := strings.Fields(line)
                if len(parts) >= 2 {
                    info.PolicyVersion = parts[1]
                }
                break
            }
        }
    }

    // Get AVC count
    if m.config.WatchAVC {
        cmd = exec.Command("ausearch", "-m", "AVC", "-ts", "recent")
        output, err = cmd.Output()
        if err == nil {
            lines := strings.Split(string(output), "\n")
            info.AVCChange = len(lines)
        }
    }

    return info
}

func (m *SELinuxMonitor) isSELinuxAvailable() bool {
    // Check if SELinux is installed and available
    cmd := exec.Command("getenforce")
    err := cmd.Run()
    return err == nil
}

func (m *SELinuxMonitor) processSELinuxStatus(info *SELinuxInfo) {
    if m.selinuxState == nil {
        m.selinuxState = info
        m.onModeChanged(info.CurrentMode)
        return
    }

    // Check for mode changes
    if info.CurrentMode != m.selinuxState.CurrentMode {
        m.onModeChanged(info.CurrentMode)
    }

    // Check for policy reload
    if info.PolicyVersion != m.selinuxState.PolicyVersion && info.PolicyVersion != "" {
        m.onPolicyReloaded(info)
    }

    // Check for AVC changes
    if info.AVCChange > m.selinuxState.AVCCount && m.config.WatchAVC {
        m.onAVCDenied(info)
    }

    m.selinuxState = info
}

func (m *SELinuxMonitor) onModeChanged(mode string) {
    switch strings.ToLower(mode) {
    case "enforcing":
        if m.config.SoundOnEnforce {
            m.onEnforcingMode()
        }
    case "permissive":
        if m.config.SoundOnPermissive {
            m.onPermissiveMode()
        }
    case "disabled":
        if m.config.SoundOnDisabled {
            m.onDisabledMode()
        }
    }
}

func (m *SELinuxMonitor) onPolicyReloaded(info *SELinuxInfo) {
    key := "selinux:policy"
    if m.shouldAlert(key, 1*time.Hour) {
        sound := m.config.Sounds["policy"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SELinuxMonitor) onAVCDenied(info *SELinuxInfo) {
    key := "selinux:avc"
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["avc"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SELinuxMonitor) onEnforcingMode() {
    key := "selinux:enforcing"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["enforce"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SELinuxMonitor) onPermissiveMode() {
    key := "selinux:permissive"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["permissive"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SELinuxMonitor) onDisabledMode() {
    key := "selinux:disabled"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["disabled"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SELinuxMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| getenforce | System Tool | Free | SELinux tools |
| sestatus | System Tool | Free | SELinux status |
| semodule | System Tool | Free | SELinux module management |
| ausearch | System Tool | Free | Audit log search |

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
| macOS | Not Supported | No SELinux |
| Linux | Supported | Uses SELinux tools |
