# Feature: Sound Event System Update Monitor

Play sounds for system updates and patch installation events.

## Summary

Monitor system updates, patch installations, and software version changes, playing sounds for update events.

## Motivation

- Update awareness
- Patch installation feedback
- Version change alerts
- Security update notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### System Update Events

| Event | Description | Example |
|-------|-------------|---------|
| Update Available | New updates found | 5 packages |
| Update Started | Installation began | brew update |
| Update Completed | Installation finished | All packages updated |
| Update Failed | Installation error | brew upgrade failed |

### Configuration

```go
type SystemUpdateMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    UpdateTool        string            `json:"update_tool"` // "brew", "apt", "yum", "system"
    SoundOnAvailable  bool              `json:"sound_on_available"`
    SoundOnStarted    bool              `json:"sound_on_started"`
    SoundOnComplete   bool              `json:"sound_on_complete"`
    SoundOnFail       bool              `json:"sound_on_fail"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 3600 default (1 hour)
}

type SystemUpdateEvent struct {
    UpdateTool   string
    PackageCount int
    Packages     []string
    Status       string // "available", "started", "complete", "failed"
    ExitCode     int
}
```

### Commands

```bash
/ccbell:update status                # Show update status
/ccbell:update tool brew             # Set update tool
/ccbell:update check                 # Force update check
/ccbell:update sound available <sound>
/ccbell:update sound complete <sound>
/ccbell:update test                  # Test update sounds
```

### Output

```
$ ccbell:update status

=== Sound Event System Update Monitor ===

Status: Enabled
Tool: brew (Homebrew)
Available Sounds: Yes
Complete Sounds: Yes

Last Check: 5 min ago
Updates Available: 5

[1] node@20.0.0 -> 20.1.0
[2] python@3.11.0 -> 3.11.5
[3] nginx@1.24.0 -> 1.25.0
[4] postgresql@15.0 -> 15.2
[5] kubectl@1.27.0 -> 1.28.0

Recent Events:
  [1] Update Available (5 min ago)
       5 packages can be updated
  [2] Update Complete (1 day ago)
       10 packages updated
  [3] Update Started (1 day ago)
       Installing updates...

Sound Settings:
  Available: bundled:stop
  Started: bundled:stop
  Complete: bundled:stop
  Fail: bundled:stop

[Configure] [Check Now] [Test All]
```

---

## Audio Player Compatibility

System update monitoring doesn't play sounds directly:
- Monitoring feature using package managers
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### System Update Monitor

```go
type SystemUpdateMonitor struct {
    config            *SystemUpdateMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    lastCheckTime     time.Time
    lastUpdateCount   int
    lastPackages      []string
}

func (m *SystemUpdateMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *SystemUpdateMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
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
    if runtime.GOOS == "darwin" {
        m.checkDarwinUpdates()
    } else {
        m.checkLinuxUpdates()
    }
}

func (m *SystemUpdateMonitor) checkDarwinUpdates() {
    switch m.config.UpdateTool {
    case "brew":
        m.checkHomebrewUpdates()
    case "mas":
        m.checkMacAppUpdates()
    default:
        m.checkHomebrewUpdates()
    }
}

func (m *SystemUpdateMonitor) checkLinuxUpdates() {
    switch m.config.UpdateTool {
    case "apt":
        m.checkAptUpdates()
    case "yum", "dnf":
        m.checkYumUpdates()
    default:
        m.checkAptUpdates()
    }
}

func (m *SystemUpdateMonitor) checkHomebrewUpdates() {
    // Check for outdated formulae
    cmd := exec.Command("brew", "outdated", "--json=v2")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseHomebrewOutput(string(output))
}

func (m *SystemUpdateMonitor) parseHomebrewOutput(output string) {
    var result struct {
        Formulae []struct {
            Name            string `json:"name"`
            CurrentVersion  string `json:"current_version"`
            LatestVersion   string `json:"latest_version"`
        } `json:"formulae"`
        Casks []struct {
            Name   string `json:"name"`
            Token  string `json:"token"`
        } `json:"casks"`
    }

    if err := json.Unmarshal([]byte(output), &result); err != nil {
        return
    }

    updateCount := len(result.Formulae) + len(result.Casks)

    if updateCount > 0 && m.lastUpdateCount == 0 {
        m.onUpdatesAvailable(result.Formulae, result.Casks)
    } else if updateCount == 0 && m.lastUpdateCount > 0 {
        // Updates were installed
        m.onUpdatesComplete()
    }

    m.lastUpdateCount = updateCount
}

func (m *SystemUpdateMonitor) checkAptUpdates() {
    // Check for upgrades without installing
    cmd := exec.Command("apt-get", "--dry-run", "upgrade")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseAptOutput(string(output))
}

func (m *SystemUpdateMonitor) parseAptOutput(output string) {
    // Count lines that look like package upgrades
    count := 0
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Inst ") {
            count++
        }
    }

    if count > 0 && m.lastUpdateCount == 0 {
        m.onUpdatesAvailable(nil, nil)
    }

    m.lastUpdateCount = count
}

func (m *SystemUpdateMonitor) checkYumUpdates() {
    cmd := exec.Command("yum", "check-update", "--quiet")
    output, err := cmd.Output()
    if err != nil {
        // Exit code 100 means updates available
        if exitCode, ok := err.(*exec.ExitError); ok {
            if exitCode.ExitCode() == 100 {
                m.onUpdatesAvailable(nil, nil)
            }
        }
        return
    }

    // No updates
    m.lastUpdateCount = 0
}

func (m *SystemUpdateMonitor) onUpdatesAvailable(formulae []any, casks []any) {
    if !m.config.SoundOnAvailable {
        return
    }

    // Debounce: only alert once per poll cycle
    if time.Since(m.lastCheckTime) < time.Duration(m.config.PollInterval)*time.Second {
        return
    }

    sound := m.config.Sounds["available"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *SystemUpdateMonitor) onUpdatesComplete() {
    if !m.config.SoundOnComplete {
        return
    }

    sound := m.config.Sounds["complete"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SystemUpdateMonitor) onUpdateFailed() {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["fail"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| brew | Package Manager | Free | macOS package management |
| apt-get | System Tool | Free | Debian/Ubuntu updates |
| yum/dnf | System Tool | Free | RHEL/Fedora updates |

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
| macOS | Supported | Uses brew, mas |
| Linux | Supported | Uses apt, yum, dnf |
| Windows | Not Supported | ccbell only supports macOS/Linux |
