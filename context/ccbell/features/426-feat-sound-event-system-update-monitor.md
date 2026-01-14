# Feature: Sound Event System Update Monitor

Play sounds for available system updates, upgrade completion, and security patch notifications.

## Summary

Monitor available system updates, security patches, and upgrade status, playing sounds for update events.

## Motivation

- Update awareness
- Security patch alerts
- Upgrade completion feedback
- Maintenance reminders
- System health

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Update Events

| Event | Description | Example |
|-------|-------------|---------|
| Updates Available | New updates found | 5 updates |
| Security Updates | Security patches | 2 critical |
| Upgrade Ready | Major upgrade | 24.04 LTS |
| Update Complete | Upgrade done | Reboot needed |
| Reboot Required | System restart | Pending |
| Update Failed | Installation error | Failed |

### Configuration

```go
type SystemUpdateMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    CheckSecurity     bool              `json:"check_security"` // true default
    CheckUpdates      bool              `json:"check_updates"` // true default
    CheckUpgrades     bool              `json:"check_upgrades"` // true default
    SoundOnUpdates    bool              `json:"sound_on_updates"`
    SoundOnSecurity   bool              `json:"sound_on_security"`
    SoundOnUpgrade    bool              `json:"sound_on_upgrade"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    Sounds            map[string]string `json:"sounds"`
    CheckInterval     int               `json:"check_interval_hours"` // 6 default
}
```

### Commands

```bash
/ccbell:update status               # Show update status
/ccbell:update check                # Force check now
/ccbell:update sound updates <sound>
/ccbell:update sound security <sound>
/ccbell:update test                 # Test update sounds
```

### Output

```
$ ccbell:update status

=== Sound Event System Update Monitor ===

Status: Enabled
Check Security: Yes
Check Updates: Yes
Check Upgrades: Yes

Update Status:

macOS Updates:

  [1] Security Update 2026-001
      Status: Available
      Severity: Critical
      Size: 45 MB
      Sound: bundled:update-security *** CRITICAL ***

  [2] macOS Sonoma 14.4
      Status: Available
      Size: 3.2 GB
      Version: 14.4
      Sound: bundled:update-major

Homebrew Updates:

  [1] python@3.12 -> 3.12.2
      Status: Available
      Size: 45 MB
      Sound: bundled:update-brew

  [2] node@20 -> 20.11.1
      Status: Available
      Size: 32 MB
      Sound: bundled:update-brew

Recent Events:
  [1] Security Update Available (2 hours ago)
       Critical security patch ready
       Sound: bundled:update-security
  [2] Homebrew Updates (5 hours ago)
       3 packages can be updated
       Sound: bundled:update-brew
  [3] System Update Complete (1 day ago)
       Reboot not required

Update Statistics:
  Security Updates: 1
  Regular Updates: 2
  Package Updates: 3

Sound Settings:
  Updates: bundled:update-available
  Security: bundled:update-security
  Upgrade: bundled:update-major
  Complete: bundled:update-complete

[Configure] [Check Now] [Test All]
```

---

## Audio Player Compatibility

Update monitoring doesn't play sounds directly:
- Monitoring feature using softwareupdate/brew
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Update Monitor

```go
type SystemUpdateMonitor struct {
    config          *SystemUpdateMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    updateState     *UpdateInfo
    lastEventTime   map[string]time.Time
    lastCheckTime   time.Time
}

type UpdateInfo struct {
    SecurityUpdates  int
    RegularUpdates   int
    MajorUpgrades    int
    PackageUpdates   int
    LastCheck        time.Time
    NeedsReboot      bool
}

func (m *SystemUpdateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.updateState = &UpdateInfo{}
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *SystemUpdateMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.CheckInterval) * time.Hour)
    defer ticker.Stop()

    // Initial check
    m.checkForUpdates()

    for {
        select {
        case <-ticker.C:
            m.checkForUpdates()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SystemUpdateMonitor) checkForUpdates() {
    var info UpdateInfo
    info.LastCheck = time.Now()

    if runtime.GOOS == "darwin" {
        m.checkDarwinUpdates(&info)
    } else {
        m.checkLinuxUpdates(&info)
    }

    // Check for package managers
    m.checkHomebrewUpdates(&info)
    m.checkSnapUpdates(&info)

    m.processUpdateStatus(&info)
}

func (m *SystemUpdateMonitor) checkDarwinUpdates(info *UpdateInfo) {
    // Check for macOS updates
    cmd := exec.Command("softwareupdate", "-l", "--list")
    output, err := cmd.Output()

    if err != nil {
        return
    }

    outputStr := string(output)

    // Parse output for updates
    // "Software Update Tool
    // Finding available software
    // No new software available." OR list of updates

    if strings.Contains(outputStr, "No new software available") {
        return
    }

    // Count security updates
    securityRe := regexp.MustEach(`(?i)security.*update`)
    securityMatches := securityRe.FindAllString(outputStr, -1)
    info.SecurityUpdates = len(securityMatches)

    // Count all updates
    updateRe := regexp.MustEach(`\* (.*)`)
    updateMatches := updateRe.FindAllString(outputStr, -1)
    info.RegularUpdates = len(updateMatches) - info.SecurityUpdates

    // Check for major OS upgrades
    majorRe := regexp.MustEach(`macOS.*(\d+\.\d+)`)
    majorMatches := majorRe.FindAllString(outputStr, -1)
    info.MajorUpgrades = len(majorMatches)

    // Check if reboot required
    if strings.Contains(outputStr, "restart") || strings.Contains(outputStr, "reboot") {
        info.NeedsReboot = true
    }
}

func (m *SystemUpdateMonitor) checkLinuxUpdates(info *UpdateInfo) {
    // Try apt-get on Debian/Ubuntu
    if m.commandExists("apt-get") {
        cmd := exec.Command("apt-get", "-s", "upgrade")
        output, err := cmd.Output()

        if err == nil {
            outputStr := string(output)
            lines := strings.Split(outputStr, "\n")
            for _, line := range lines {
                if strings.HasPrefix(line, "Inst") {
                    info.RegularUpdates++
                }
            }
        }

        // Check for security updates
        cmd = exec.Command("apt-get", "-s", "dist-upgrade")
        output, err = cmd.Output()

        if err == nil {
            outputStr := string(output)
            if strings.Contains(outputStr, "Security") {
                info.SecurityUpdates = 1
            }
        }
    }

    // Try dnf on Fedora/RHEL
    if m.commandExists("dnf") {
        cmd := exec.Command("dnf", "check-update", "--quiet")
        output, _ := cmd.Output()

        // Exit code 100 means updates available
        if len(output) > 0 {
            lines := strings.Split(string(output), "\n")
            for _, line := range lines {
                if strings.TrimSpace(line) != "" && !strings.HasPrefix(line, "Last metadata") {
                    info.RegularUpdates++
                }
            }
        }
    }
}

func (m *SystemUpdateMonitor) checkHomebrewUpdates(info *UpdateInfo) {
    if !m.commandExists("brew") {
        return
    }

    // Check for outdated packages
    cmd := exec.Command("brew", "outdated", "--quiet")
    output, err := cmd.Output()

    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) != "" {
            info.PackageUpdates++
        }
    }
}

func (m *SystemUpdateMonitor) checkSnapUpdates(info *UpdateInfo) {
    if !m.commandExists("snap") {
        return
    }

    cmd := exec.Command("snap", "refresh", "--list")
    output, err := cmd.Output()

    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Name") || strings.TrimSpace(line) == "" {
            continue
        }
        info.PackageUpdates++
    }
}

func (m *SystemUpdateMonitor) commandExists(cmd string) bool {
    cmdPath, err := exec.LookPath(cmd)
    return err == nil && cmdPath != ""
}

func (m *SystemUpdateMonitor) processUpdateStatus(info *UpdateInfo) {
    if m.updateState == nil {
        m.updateState = info
        m.onUpdatesFound(info)
        return
    }

    // Check for new security updates
    if info.SecurityUpdates > m.updateState.SecurityUpdates {
        m.onSecurityUpdates(info)
    }

    // Check for new regular updates
    if info.RegularUpdates > m.updateState.RegularUpdates {
        m.onUpdatesAvailable(info)
    }

    // Check for new package updates
    if info.PackageUpdates > m.updateState.PackageUpdates {
        m.onPackageUpdates(info)
    }

    // Check for major upgrades
    if info.MajorUpgrades > m.updateState.MajorUpgrades {
        m.onUpgradeAvailable(info)
    }

    m.updateState = info
}

func (m *SystemUpdateMonitor) onUpdatesFound(info *UpdateInfo) {
    if info.SecurityUpdates > 0 && m.config.SoundOnSecurity {
        m.onSecurityUpdates(info)
    } else if info.RegularUpdates > 0 && m.config.SoundOnUpdates {
        m.onUpdatesAvailable(info)
    }
}

func (m *SystemUpdateMonitor) onSecurityUpdates(info *UpdateInfo) {
    key := "update:security"
    if m.shouldAlert(key, 24*time.Hour) {
        sound := m.config.Sounds["security"]
        if sound != "" {
            m.player.Play(sound, 0.5)
        }
    }
}

func (m *SystemUpdateMonitor) onUpdatesAvailable(info *UpdateInfo) {
    key := "update:available"
    if m.shouldAlert(key, 12*time.Hour) {
        sound := m.config.Sounds["updates"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemUpdateMonitor) onPackageUpdates(info *UpdateInfo) {
    key := "update:packages"
    if m.shouldAlert(key, 6*time.Hour) {
        sound := m.config.Sounds["packages"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *SystemUpdateMonitor) onUpgradeAvailable(info *UpdateInfo) {
    key := "update:upgrade"
    if m.shouldAlert(key, 48*time.Hour) {
        sound := m.config.Sounds["upgrade"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *SystemUpdateMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| softwareupdate | System Tool | Free | macOS update tool |
| apt-get | System Tool | Free | Debian package manager |
| dnf | System Tool | Free | Fedora package manager |
| brew | System Tool | Free | Homebrew package manager |
| snap | System Tool | Free | Snap package manager |

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
| macOS | Supported | Uses softwareupdate, brew |
| Linux | Supported | Uses apt-get, dnf, brew, snap |
