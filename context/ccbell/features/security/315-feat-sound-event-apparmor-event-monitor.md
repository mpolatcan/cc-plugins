# Feature: Sound Event Apparmor Event Monitor

Play sounds for AppArmor policy violations and profile changes.

## Summary

Monitor AppArmor events including denials, profile loads, and confinement changes, playing sounds for security events.

## Motivation

- Security monitoring
- Confinement violation alerts
- Profile change awareness
- Access control feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### AppArmor Events

| Event | Description | Example |
|-------|-------------|---------|
| Access Denied | AppArmor blocked | profile://usr/sbin/nginx |
| Profile Loaded | New profile | apparmor_parser |
| Profile Unloaded | Profile removed | aa-disable |
| Mode Change | Enforcement changed | complain mode |

### Configuration

```go
type AppArmorMonitorConfig struct {
    Enabled         bool              `json:"enabled"`
    WatchProfiles   []string          `json:"watch_profiles"] // "nginx", "mysql"
    SoundOnDeny     bool              `json:"sound_on_deny"]
    SoundOnLoad     bool              `json:"sound_on_load"]
    SoundOnUnload   bool              `json:"sound_on_unload"]
    Sounds          map[string]string `json:"sounds"`
    PollInterval    int               `json:"poll_interval_sec"` // 10 default
}

type AppArmorEvent struct {
    Profile   string
    Operation string
    Access    string
    Result    string // "denied", "allowed"
    EventType string
}
```

### Commands

```bash
/ccbell:apparmor status               # Show AppArmor status
/ccbell:apparmor add nginx            # Add profile to watch
/ccbell:apparmor remove nginx
/ccbell:apparmor sound deny <sound>
/ccbell:apparmor sound load <sound>
/ccbell:apparmor test                 # Test AppArmor sounds
```

### Output

```
$ ccbell:apparmor status

=== Sound Event AppArmor Monitor ===

Status: Enabled
Mode: Enforce
Deny Sounds: Yes
Load Sounds: Yes

Watched Profiles: 2

[1] /usr/sbin/nginx
    Mode: Enforce
    Denials: 3
    Last Denial: 5 min ago
    Sound: bundled:apparmor-deny

[2] /usr/bin/mysql
    Mode: Complain
    Denials: 10
    Last Denial: 1 hour ago
    Sound: bundled:stop

Recent Events:
  [1] nginx: Access Denied (5 min ago)
       /var/log/nginx/error.log write
  [2] mysql: Access Denied (1 hour ago)
       /etc/mysql/my.cnf read
  [3] Profile Loaded (2 hours ago)
       /usr/sbin/postgresql

AppArmor Statistics (24h):
  Total denials: 13
  Profiles loaded: 2
  Profiles unloaded: 0

Sound Settings:
  Deny: bundled:apparmor-deny
  Load: bundled:stop
  Unload: bundled:stop

[Configure] [Add Profile] [Test All]
```

---

## Audio Player Compatibility

AppArmor monitoring doesn't play sounds directly:
- Monitoring feature using AppArmor tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### AppArmor Event Monitor

```go
type AppArmorMonitor struct {
    config           *AppArmorMonitorConfig
    player           *audio.Player
    running          bool
    stopCh           chan struct{}
    apparmorState    *AppArmorState
    lastEventTime    map[string]time.Time
}

type AppArmorState struct {
    Profiles   map[string]string // profile -> mode
    DenyCount  int
}

func (m *AppArmorMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.apparmorState = &AppArmorState{
        Profiles: make(map[string]string),
    }
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *AppArmorMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotAppArmorState()

    for {
        select {
        case <-ticker.C:
            m.checkAppArmorEvents()
        case <-m.stopCh:
            return
        }
    }
}

func (m *AppArmorMonitor) snapshotAppArmorState() {
    if runtime.GOOS != "linux" {
        return
    }

    // List loaded profiles
    m.listLoadedProfiles()

    // Check for denials
    m.checkApparmorDenials()
}

func (m *AppArmorMonitor) listLoadedProfiles() {
    cmd := exec.Command("aa-status", "--json")
    output, err := cmd.Output()
    if err != nil {
        // Fallback to plain output
        cmd = exec.Command("aa-status")
        output, err = cmd.Output()
        if err != nil {
            return
        }

        m.parseAAStatusOutput(string(output))
        return
    }

    m.parseAAStatusJSON(string(output))
}

func (m *AppArmorMonitor) checkAppArmorEvents() {
    if runtime.GOOS != "linux" {
        return
    }

    // Check profile changes
    m.listLoadedProfiles()

    // Check for new denials
    m.checkApparmorDenials()
}

func (m *AppArmorMonitor) parseAAStatusOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "profiles are loaded") {
            // Count profiles
            parts := strings.Fields(line)
            if len(parts) >= 1 {
                // Update state
            }
        }
    }
}

func (m *AppArmorMonitor) parseAAStatusJSON(output string) {
    var status struct {
        Profiles []struct {
            Name string `json:"name"`
            Mode string `json:"mode"`
        } `json:"profiles"`
    }

    if err := json.Unmarshal([]byte(output), &status); err != nil {
        return
    }

    for _, p := range status.Profiles {
        oldMode := m.apparmorState.Profiles[p.Name]
        if oldMode == "" {
            // New profile loaded
            m.onProfileLoaded(p.Name)
        } else if oldMode != p.Mode {
            // Mode changed
            m.onProfileModeChanged(p.Name, oldMode, p.Mode)
        }
        m.apparmorState.Profiles[p.Name] = p.Mode
    }
}

func (m *AppArmorMonitor) checkApparmorDenials() {
    // Check audit logs for AppArmor denials
    logFile := "/var/log/audit/audit.log"
    data, err := os.ReadFile(logFile)
    if err != nil {
        data, err = os.ReadFile("/var/log/syslog")
        if err != nil {
            return
        }
    }

    m.parseAppArmorDenials(string(data))
}

func (m *AppArmorMonitor) parseAppArmorDenials(log string) {
    lines := strings.Split(log, "\n")
    recentTime := time.Now().Add(-time.Duration(m.config.PollInterval) * time.Second)

    for _, line := range lines {
        if !strings.Contains(line, "apparmor") && !strings.Contains(line, "APPARMOR") {
            continue
        }

        // Check if line is recent
        if !m.isRecentLogLine(line, recentTime) {
            continue
        }

        event := m.parseAppArmorLine(line)
        if event == nil {
            continue
        }

        if event.Result == "denied" && m.shouldWatchProfile(event.Profile) {
            m.onAccessDenied(event)
        }
    }
}

func (m *AppArmorMonitor) parseAppArmorLine(line string) *AppArmorEvent {
    event := &AppArmorEvent{}

    // Parse AppArmor denial line
    // Example: apparmor="DENIED" operation="open" profile="/usr/sbin/nginx" name="/var/log/nginx/error.log"

    if strings.Contains(line, "apparmor=\"DENIED\"") || strings.Contains(line, "apparmor='DENIED'") {
        event.Result = "denied"
        event.EventType = "deny"
    } else if strings.Contains(line, "apparmor=\"ALLOWED\"") || strings.Contains(line, "apparmor='ALLOWED'") {
        event.Result = "allowed"
        event.EventType = "allow"
    }

    // Extract profile name
    profileRe := regexp.MustCompile(`profile="([^"]+)"`)
    if match := profileRe.FindStringSubmatch(line); match != nil {
        event.Profile = match[1]
    }

    // Extract operation
    opRe := regexp.MustCompile(`operation="([^"]+)"`)
    if match := opRe.FindStringSubmatch(line); match != nil {
        event.Operation = match[1]
    }

    return event
}

func (m *AppArmorMonitor) isRecentLogLine(line string, since time.Time) bool {
    // Simple check - if line contains recent timestamp
    // For audit.log, format is: type=AVC msg=audit(1234567890.123:456)
    re := regexp.MustCompile(`audit\(([0-9]+)\.`)
    if match := re.FindStringSubmatch(line); match != nil {
        timestampSec, err := strconv.ParseInt(match[1], 10, 64)
        if err == nil {
            lineTime := time.Unix(timestampSec, 0)
            return lineTime.After(since)
        }
    }
    return true
}

func (m *AppArmorMonitor) shouldWatchProfile(profile string) bool {
    if len(m.config.WatchProfiles) == 0 {
        return true
    }

    for _, p := range m.config.WatchProfiles {
        if strings.Contains(profile, p) {
            return true
        }
    }

    return false
}

func (m *AppArmorMonitor) onAccessDenied(event *AppArmorEvent) {
    if !m.config.SoundOnDeny {
        return
    }

    key := fmt.Sprintf("deny:%s", event.Profile)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["deny"]
        if sound != "" {
            m.player.Play(sound, 0.6)
        }
    }

    m.apparmorState.DenyCount++
}

func (m *AppArmorMonitor) onProfileLoaded(profile string) {
    if !m.config.SoundOnLoad {
        return
    }

    if !m.shouldWatchProfile(profile) {
        return
    }

    key := fmt.Sprintf("load:%s", profile)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["load"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AppArmorMonitor) onProfileUnloaded(profile string) {
    if !m.config.SoundOnUnload {
        return
    }

    key := fmt.Sprintf("unload:%s", profile)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["unload"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AppArmorMonitor) onProfileModeChanged(profile string, oldMode string, newMode string) {
    key := fmt.Sprintf("mode:%s:%s->%s", profile, oldMode, newMode)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["mode_change"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *AppArmorMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| aa-status | System Tool | Free | AppArmor status |
| /var/log/audit/audit.log | File | Free | Audit logs |

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
| macOS | Not Supported | No AppArmor on macOS |
| Linux | Supported | Uses aa-status, audit.log |
| Windows | Not Supported | ccbell only supports macOS/Linux |
