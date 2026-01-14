# Feature: Sound Event Package Update Monitor

Play sounds for available system package updates and upgrade completions.

## Summary

Monitor available package updates, security patches, and installation completions, playing sounds for update events.

## Motivation

- Update awareness
- Security patch alerts
- Package upgrade feedback
- System maintenance
- Repository sync notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Package Update Events

| Event | Description | Example |
|-------|-------------|---------|
| Updates Available | Updates pending | 15 updates |
| Security Updates | Security patches available | 3 security updates |
| Update Installed | Package updated | apt-get upgrade |
| Repository Sync | Repo sync completed | Index updated |
| Auto Update | System updated | unattended upgrade |

### Configuration

```go
type PackageUpdateMonitorConfig struct {
    Enabled             bool              `json:"enabled"`
    PackageManager      string            `json:"package_manager"` // "apt", "yum", "brew"
    SecurityAlerts      bool              `json:"security_alerts"`
    UpdateThreshold     int               `json:"update_threshold"` // 5 default
    SoundOnUpdates      bool              `json:"sound_on_updates"`
    SoundOnSecurity     bool              `json:"sound_on_security"`
    SoundOnInstall      bool              `json:"sound_on_install"`
    Sounds              map[string]string `json:"sounds"`
    PollInterval        int               `json:"poll_interval_sec"` // 3600 default
}

type PackageUpdateEvent struct {
    PackageManager  string
    UpdatesCount    int
    SecurityCount   int
    Packages        []string
    Version         string
    EventType       string // "available", "security", "installed", "sync"
}
```

### Commands

```bash
/ccbell:packages status               # Show package update status
/ccbell:packages type apt             # Set package manager
/ccbell:packages threshold 5          # Set update threshold
/ccbell:packages sound updates <sound>
/ccbell:packages sound security <sound>
/ccbell:packages test                 # Test package sounds
```

### Output

```
$ ccbell:packages status

=== Sound Event Package Update Monitor ===

Status: Enabled
Package Manager: apt
Security Alerts: Yes
Update Threshold: 5
Update Sounds: Yes
Security Sounds: Yes

Available Updates:
  Total: 15 packages
  Security: 3 packages
  Regular: 12 packages

Security Updates:
  [1] openssl (CVE-2024-1234)
  [2] libssl3 (CVE-2024-1234)
  [3] nginx (CVE-2024-5678)

Regular Updates:
  [1] curl 7.88 -> 7.88.1
  [2] vim 9.0 -> 9.0.2
  [3] ...

Recent Events:
  [1] Updates Available (5 min ago)
       15 updates available (3 security)
  [2] Security Updates (10 min ago)
       3 critical security updates
  [3] Repository Synced (1 hour ago)
       Index updated successfully

Package Statistics:
  Last Check: 5 min ago
  Updates Today: 28
  Installed Today: 12

Sound Settings:
  Updates: bundled:pkg-updates
  Security: bundled:pkg-security
  Install: bundled:pkg-install

[Configure] [Set Type] [Test All]
```

---

## Audio Player Compatibility

Package update monitoring doesn't play sounds directly:
- Monitoring feature using apt/yum/brew
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Package Update Monitor

```go
type PackageUpdateMonitor struct {
    config          *PackageUpdateMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    updateState     *UpdateInfo
    lastEventTime   map[string]time.Time
}

type UpdateInfo struct {
    PackageManager  string
    UpdatesCount    int
    SecurityCount   int
    Packages        []string
    LastCheck       time.Time
}

func (m *PackageUpdateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.updateState = &UpdateInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *PackageMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotUpdateState()

    for {
        select {
        case <-ticker.C:
            m.checkUpdateState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *PackageUpdateMonitor) snapshotUpdateState() {
    m.detectPackageManager()
    m.checkUpdateState()
}

func (m *PackageUpdateMonitor) detectPackageManager() {
    // Detect available package managers
    if _, err := exec.LookPath("apt-get"); err == nil {
        m.config.PackageManager = "apt"
    } else if _, err := exec.LookPath("dnf"); err == nil {
        m.config.PackageManager = "dnf"
    } else if _, err := exec.LookPath("brew"); err == nil {
        m.config.PackageManager = "brew"
    }
}

func (m *PackageUpdateMonitor) checkUpdateState() {
    var newState UpdateInfo
    newState.PackageManager = m.config.PackageManager
    newState.LastCheck = time.Now()

    switch m.config.PackageManager {
    case "apt":
        m.checkAPTUpdates(&newState)
    case "dnf":
        m.checkDNFUpdates(&newState)
    case "brew":
        m.checkBrewUpdates(&newState)
    }

    if m.updateState.UpdatesCount > 0 {
        m.evaluateUpdateEvents(&newState, m.updateState)
    }

    m.updateState = &newState
}

func (m *PackageUpdateMonitor) checkAPTUpdates(state *UpdateInfo) {
    // Update package lists
    cmd := exec.Command("apt-get", "update", "-qq")
    cmd.Run()

    // Get upgradeable packages
    cmd = exec.Command("apt-get", "upgrade", "-s", "-qq")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    count := 0
    securityCount := 0

    for _, line := range lines {
        if strings.HasPrefix(line, "Inst") {
            count++
            if strings.Contains(line, "[Security]") || strings.Contains(line, "security") {
                securityCount++
            }

            // Extract package name
            parts := strings.Fields(line)
            if len(parts) >= 2 {
                state.Packages = append(state.Packages, parts[1])
            }
        }
    }

    state.UpdatesCount = count
    state.SecurityCount = securityCount
}

func (m *PackageUpdateMonitor) checkDNFUpdates(state *UpdateInfo) {
    cmd := exec.Command("dnf", "check-update", "-q")
    output, err := cmd.Output()
    exitCode := 0
    if err != nil {
        if exitErr, ok := err.(*exec.ExitError); ok {
            exitCode = exitErr.ExitCode()
        }
    }

    if exitCode == 100 {
        // Updates available
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if line == "" || strings.HasPrefix(line, "Last metadata") {
                continue
            }
            state.UpdatesCount++
            state.Packages = append(state.Packages, line)
        }

        // Check for security updates
        cmd = exec.Command("dnf", "updateinfo", "list", "security", "-q")
        secOutput, _ := cmd.Output()
        secLines := strings.Split(string(secOutput), "\n")
        state.SecurityCount = len(secLines) - 1
    }
}

func (m *PackageUpdateMonitor) checkBrewUpdates(state *UpdateInfo) {
    cmd := exec.Command("brew", "outdated", "--json=v1")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse JSON output
    // This is simplified - would need full JSON parsing
    state.UpdatesCount = len(strings.Split(string(output), "\n"))
}

func (m *PackageUpdateMonitor) evaluateUpdateEvents(newState *UpdateInfo, lastState *UpdateInfo) {
    // Check if updates became available
    if newState.UpdatesCount > 0 && lastState.UpdatesCount == 0 {
        if newState.SecurityCount > 0 && m.config.SecurityAlerts {
            m.onSecurityUpdates(newState)
        } else if newState.UpdatesCount >= m.config.UpdateThreshold {
            m.onUpdatesAvailable(newState)
        }
    }

    // Check for new security updates
    if newState.SecurityCount > lastState.SecurityCount && m.config.SecurityAlerts {
        m.onSecurityUpdates(newState)
    }

    // Check for increased regular updates
    if newState.UpdatesCount >= m.config.UpdateThreshold &&
        lastState.UpdatesCount < m.config.UpdateThreshold {
        m.onUpdatesAvailable(newState)
    }
}

func (m *PackageUpdateMonitor) onUpdatesAvailable(state *UpdateInfo) {
    if !m.config.SoundOnUpdates {
        return
    }

    key := fmt.Sprintf("updates:%d", state.UpdatesCount)
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["updates"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *PackageUpdateMonitor) onSecurityUpdates(state *UpdateInfo) {
    if !m.config.SoundOnSecurity {
        return
    }

    key := fmt.Sprintf("security:%d", state.SecurityCount)
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["security"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }
}

func (m *PackageUpdateMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| apt-get | System Tool | Free | Debian/Ubuntu packages |
| dnf/yum | System Tool | Free | RedHat/Fedora packages |
| brew | System Tool | Free | macOS packages |

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
| macOS | Supported | Uses brew |
| Linux | Supported | Uses apt, dnf, yum |
