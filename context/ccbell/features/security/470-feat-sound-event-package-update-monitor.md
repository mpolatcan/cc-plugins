# Feature: Sound Event Package Update Monitor

Play sounds for application package updates and dependency changes.

## Summary

Monitor application package managers (npm, pip, cargo, gem) for outdated packages, security vulnerabilities, and update availability, playing sounds for package events.

## Motivation

- Package awareness
- Update notifications
- Security alerts
- Dependency health
- Version tracking

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
| Outdated Package | Package outdated | 5 outdated |
| Security Update | Vulnerable package | CVE-2024-1234 |
| Major Update | Breaking change | v2.0.0 |
| Update Available | New version | 1.2.3 |
| Vulnerability Found | CVE detected | critical |
| Update Installed | Package updated | updated |

### Configuration

```go
type PackageUpdateMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchManagers      []string          `json:"watch_managers"` // "npm", "pip", "cargo", "*"
    OutdatedThreshold  int               `json:"outdated_threshold"` // 5 default
    CheckSecurity      bool              `json:"check_security"` // true default
    SoundOnOutdated    bool              `json:"sound_on_outdated"`
    SoundOnSecurity    bool              `json:"sound_on_security"`
    SoundOnMajor       bool              `json:"sound_on_major"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_hours"` // 24 default
}
```

### Commands

```bash
/ccbell:package status              # Show package status
/ccbell:package add npm             # Add package manager
/ccbell:package security            # Check security only
/ccbell:package sound outdated <sound>
/ccbell:package test                # Test package sounds
```

### Output

```
$ ccbell:package status

=== Sound Event Package Update Monitor ===

Status: Enabled
Watch Managers: all
Outdated Threshold: 5
Check Security: true

Package Status:

[1] npm (/project)
    Status: UPDATES AVAILABLE *** 8 ***
    Outdated: 8
    Security: 2
    Major: 1
    Last Check: 1 hour ago
    Sound: bundled:package-npm *** WARNING ***

[2] pip (global)
    Status: HEALTHY
    Outdated: 0
    Security: 0
    Last Check: 2 hours ago
    Sound: bundled:package-pip

[3] cargo
    Status: UPDATES AVAILABLE *** 3 ***
    Outdated: 3
    Security: 0
    Major: 0
    Last Check: 30 min ago
    Sound: bundled:package-cargo

Recent Events:

[1] npm (/project): Security Vulnerabilities (5 min ago)
       2 packages with CVEs
       Sound: bundled:package-security
  [2] npm (/project): Major Update (1 hour ago)
       react v17 -> v18
       Sound: bundled:package-major
  [3] cargo: Outdated Packages (2 hours ago)
       3 packages have updates
       Sound: bundled:package-outdated

Package Statistics:
  Total Outdated: 11
  Security Issues: 2
  Major Updates: 1

Sound Settings:
  Outdated: bundled:package-outdated
  Security: bundled:package-security
  Major: bundled:package-major
  Update: bundled:package-update

[Configure] [Add Manager] [Test All]
```

---

## Audio Player Compatibility

Package monitoring doesn't play sounds directly:
- Monitoring feature using npm, pip, cargo, gem commands
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Package Update Monitor

```go
type PackageUpdateMonitor struct {
    config        *PackageUpdateMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    packageState  map[string]*PackageInfo
    lastEventTime map[string]time.Time
}

type PackageInfo struct {
    Manager     string // "npm", "pip", "cargo", "gem"
    Path        string
    Status      string // "healthy", "outdated", "security"
    Outdated    int
    Security    int
    Major       int
    LastCheck   time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| npm | System Tool | Free | Node package manager |
| pip | System Tool | Free | Python package manager |
| cargo | System Tool | Free | Rust package manager |
| gem | System Tool | Free | Ruby package manager |

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
| macOS | Supported | Uses npm, pip, cargo, gem |
| Linux | Supported | Uses npm, pip, cargo, gem |
