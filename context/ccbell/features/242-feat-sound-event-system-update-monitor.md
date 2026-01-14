# Feature: Sound Event System Update Monitor

Play sounds for system update and package upgrade events.

## Summary

Monitor system updates, package manager activities, and upgrade notifications, playing sounds for update events.

## Motivation

- Update completion alerts
- Upgrade feedback
- Reboot required warnings
- Security patch awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### System Update Events

| Event | Description | Example |
|-------|-------------|---------|
| Update Available | Updates found | 5 updates |
| Update Started | Update began | apt upgrade |
| Update Complete | All updates done | System updated |
| Package Installed | New package | nginx installed |
| Reboot Required | Reboot needed | Kernel updated |
| Security Update | Security patch | CVE fix |

### Configuration

```go
type SystemUpdateMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    SoundOnUpdate      bool              `json:"sound_on_update"`
    SoundOnComplete    bool              `json:"sound_on_complete"`
    SoundOnReboot      bool              `json:"sound_on_reboot"`
    CheckSecurity      bool              `json:"check_security"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_hours"` // 6 default
}

type SystemUpdateEvent struct {
    EventType   string // "available", "started", "complete", "reboot_required", "security"
    PackageCount int
    Packages    []string
    Severity    string // "normal", "security", "critical"
}
```

### Commands

```bash
/ccbell:system-update status      # Show update status
/ccbell:system-update check       # Force check now
/ccbell:system-update sound available <sound>
/ccbell:system-update sound complete <sound>
/ccbell:system-update sound reboot <sound>
/ccbell:system-update test        # Test update sounds
```

### Output

```
$ ccbell:system-update status

=== Sound Event System Update Monitor ===

Status: Enabled
Check Interval: 6 hours
Last Check: 2 hours ago

Available Updates: 12
  Regular: 8
  Security: 4

Updates:
  [1] python3 (3.10.0 -> 3.10.1) - Regular
  [2] nginx (1.20.0 -> 1.20.1) - Regular
  [3] openssl (1.1.1k -> 1.1.1l) - SECURITY
  [4] libssl3 (3.0.0 -> 3.0.1) - SECURITY
  ...

Recent Events:
  [1] 12 Updates Available (2 hours ago)
  [2] Security Updates Available (2 hours ago)
  [3] System Updated (1 day ago)
  [4] Reboot Required (1 day ago)

Sound Settings:
  Updates Available: bundled:stop
  Update Complete: bundled:stop
  Reboot Required: bundled:stop

[Configure] [Check Now] [Test All]
```

---

## Audio Player Compatibility

System update monitoring doesn't play sounds directly:
- Monitoring feature using package manager tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Update Monitor

```go
type SystemUpdateMonitor struct {
    config         *SystemUpdateMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    lastCheck      time.Time
    lastUpdateCount int
}

func (m *SystemUpdateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastUpdateCount = -1
    go m.monitor()
}

func (m *SystemUpdateMonitor) monitor() {
    interval := time.Duration(m.config.PollInterval) * time.Hour
    ticker := time.NewTicker(interval)
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
    m.lastCheck = time.Now()

    if runtime.GOOS == "darwin" {
        m.checkMacOSUpdates()
    } else if runtime.GOOS == "linux" {
        m.checkLinuxUpdates()
    }
}

func (m *SystemUpdateMonitor) checkMacOSUpdates() {
    cmd := exec.Command("softwareupdate", "-l")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    result := string(output)

    if strings.Contains(result, "No new software available") {
        return
    }

    // Count updates
    updateCount := m.countMacOSUpdates(result)

    if updateCount != m.lastUpdateCount {
        m.onUpdatesAvailable(updateCount, result)
    }

    m.lastUpdateCount = updateCount
}

func (m *SystemUpdateMonitor) countMacOSUpdates(output string) int {
    count := 0
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "   * ") || strings.Contains(line, "Label:") {
            count++
        }
    }
    return count
}

func (m *SystemUpdateMonitor) checkLinuxUpdates() {
    var updateCount int
    var securityCount int

    // Try apt-get (Debian/Ubuntu)
    cmd := exec.Command("apt-get", "-s", "upgrade")
    output, err := cmd.Output()
    if err == nil {
        updateCount = m.countAptUpdates(string(output))
    }

    // Check for security updates
    if m.config.CheckSecurity {
        cmd = exec.Command("apt-get", "-s", "dist-upgrade")
        output, err = cmd.Output()
        if err == nil {
            securityCount = m.countSecurityUpdates(string(output))
        }
    }

    if updateCount > 0 && updateCount != m.lastUpdateCount {
        m.onUpdatesAvailable(updateCount, string(output))
    }

    m.lastUpdateCount = updateCount
}

func (m *SystemUpdateMonitor) countAptUpdates(output string) int {
    count := 0
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Inst") || strings.HasPrefix(line, "Conf") {
            count++
        }
    }
    return count
}

func (m *SystemUpdateMonitor) countSecurityUpdates(output string) int {
    count := 0
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "security") ||
           strings.Contains(line, "Ubuntu-security") {
            count++
        }
    }
    return count
}

func (m *SystemUpdateMonitor) onUpdatesAvailable(count int, details string) {
    if !m.config.SoundOnUpdate {
        return
    }

    event := SystemUpdateEvent{
        EventType:   "available",
        PackageCount: count,
    }

    if m.config.CheckSecurity {
        event.Severity = "security"
    }

    sound := m.config.Sounds["available"]
    if event.Severity == "security" {
        altSound := m.config.Sounds["security"]
        if altSound != "" {
            sound = altSound
        }
    }

    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemUpdateMonitor) onUpdateComplete() {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemUpdateMonitor) onRebootRequired() {
    if !m.config.SoundOnReboot {
        return
    }

    sound := m.config.Sounds["reboot_required"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| softwareupdate | System Tool | Free | macOS updates |
| apt-get | APT | Free | Debian/Ubuntu updates |
| yum/dnf | RPM | Free | RedHat/Fedora updates |

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
| macOS | Supported | Uses softwareupdate |
| Linux | Supported | Uses apt/yum/dnf |
| Windows | Not Supported | ccbell only supports macOS/Linux |
