# Feature: Sound Event System Update Monitor

Play sounds for system updates, kernel updates, and security patch availability.

## Summary

Monitor system package updates (apt, yum, brew, softwareupdate) for available updates, security patches, and reboot requirements, playing sounds for update events.

## Motivation

- Update awareness
- Security patch alerts
- Kernel update detection
- Maintenance reminders
- Update completion

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### System Update Events

| Event | Description | Example |
|-------|-------------|---------|
| Updates Available | Updates pending | 10 updates |
| Security Updates | Security patches | 5 security |
| Kernel Update | New kernel | linux-image-5.15 |
| Reboot Required | Reboot needed | reboot |
| Update Installed | Update completed | updated |
| Repository Error | Repo unreachable | 404 |

### Configuration

```go
type SystemUpdateMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    PackageManager     string            `json:"package_manager"` // "apt", "yum", "brew", "all"
    SecurityOnly       bool              `json:"security_only"` // only alert on security
    RebootRequired     bool              `json:"alert_reboot"`
    UpdateThreshold    int               `json:"update_threshold"` // 5 updates
    SoundOnUpdates     bool              `json:"sound_on_updates"`
    SoundOnSecurity    bool              `json:"sound_on_security"`
    SoundOnReboot      bool              `json:"sound_on_reboot"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_hours"` // 6 default
}
```

### Commands

```bash
/ccbell:update status               # Show update status
/ccbell:update add apt              # Add package manager
/ccbell:update security             # Check security only
/ccbell:update sound updates <sound>
/ccbell:update test                 # Test update sounds
```

### Output

```
$ ccbell:update status

=== Sound Event System Update Monitor ===

Status: Enabled
Package Manager: apt
Update Threshold: 5

Update Status:

[1] apt (Debian)
    Status: UPDATES AVAILABLE *** 12 ***
    Regular: 7
    Security: 5
    Last Check: 5 min ago
    Reboot Required: Yes *** REBOOT ***
    Sound: bundled:update-apt *** WARNING ***

[2] brew (Homebrew)
    Status: HEALTHY
    Updates: 0
    Last Check: 1 hour ago
    Sound: bundled:update-brew

Recent Events:

[1] apt: Security Updates (5 min ago)
       5 security updates available
       Sound: bundled:update-security
  [2] apt: Reboot Required (1 hour ago)
       Kernel updated, reboot needed
       Sound: bundled:update-reboot
  [3] apt: Updates Installed (8 hours ago)
       10 packages updated
       Sound: bundled:update-complete

Update Statistics:
  Total Updates: 12
  Security: 5
  Regular: 7

Sound Settings:
  Updates: bundled:update-updates
  Security: bundled:update-security
  Reboot: bundled:update-reboot
  Complete: bundled:update-complete

[Configure] [Add Manager] [Test All]
```

---

## Audio Player Compatibility

Update monitoring doesn't play sounds directly:
- Monitoring feature using apt, yum, brew, softwareupdate
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### System Update Monitor

```go
type SystemUpdateMonitor struct {
    config        *SystemUpdateMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    updateState   map[string]*UpdateInfo
    lastEventTime map[string]time.Time
}

type UpdateInfo struct {
    Manager      string // "apt", "yum", "brew", "softwareupdate"
    Status       string // "healthy", "updates", "security", "reboot"
    TotalUpdates int
    SecurityUpdates int
    RebootRequired bool
    LastCheck    time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| apt | System Tool | Free | Debian package manager |
| yum/dnf | System Tool | Free | RedHat package manager |
| brew | System Tool | Free | Homebrew package manager |
| softwareupdate | System Tool | Free | macOS update tool |

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
| Linux | Supported | Uses apt, yum, dnf |
