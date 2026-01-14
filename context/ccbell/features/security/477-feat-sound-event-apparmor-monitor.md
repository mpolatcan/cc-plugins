# Feature: Sound Event AppArmor Monitor

Play sounds for AppArmor profile changes, enforcement mode, and audit events.

## Summary

Monitor AppArmor for profile status changes, mode switches, and security events, playing sounds for AppArmor events.

## Motivation

- Security monitoring
- Profile awareness
- Mode change alerts
- Audit events
- Access control

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### AppArmor Events

| Event | Description | Example |
|-------|-------------|---------|
| Profile Loaded | New profile | /etc/apparmor.d/usr.sbin.nginx |
| Profile Unloaded | Profile removed | profile removed |
| Mode Changed | Complain <-> Enforce | mode switched |
| Audit Event | Audit message | audit DENIED |
| Permission Denied | Access denied | denied |
| Cache Updated | Cache refreshed | cache update |

### Configuration

```go
type AppArmorMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnLoad       bool              `json:"sound_on_load"`
    SoundOnUnload     bool              `json:"sound_on_unload"`
    SoundOnModeChange bool              `json:"sound_on_mode_change"`
    SoundOnAudit      bool              `json:"sound_on_audit"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:apparmor status             # Show AppArmor status
/ccbell:apparmor sound load <sound>
/ccbell:apparmor test               # Test AppArmor sounds
```

### Output

```
$ ccbell:apparmor status

=== Sound Event AppArmor Monitor ===

Status: Enabled
Mode: Enforce

AppArmor Status:

[1] /etc/apparmor.d/usr.sbin.nginx
    Status: ENFORCING
    Mode: enforce
    Profile: nginx
    Last Loaded: Jan 14 08:00
    Sound: bundled:apparmor-nginx

[2] /etc/apparmor.d/usr.bin.sshd
    Status: COMPLAINING
    Mode: complain
    Profile: sshd
    Last Loaded: Jan 13 14:00
    Sound: bundled:apparmor-sshd *** WARNING ***

Recent Events:

[1] /etc/apparmor.d/usr.bin.mysql: Profile Loaded (5 min ago)
       /etc/apparmor.d/usr.bin.mysql loaded
       Sound: bundled:apparmor-load
  [2] /usr/bin/sshd: Mode Changed (1 hour ago)
       Enforce -> Complain
       Sound: bundled:apparmor-mode
  [3] nginx: Audit Event (2 hours ago)
       /var/log/nginx/error.log audit DENIED
       Sound: bundled:apparmor-audit

AppArmor Statistics:
  Total Profiles: 12
  Enforcing: 10
  Complaining: 2
  Disabled: 0

Sound Settings:
  Load: bundled:apparmor-load
  Unload: bundled:apparmor-unload
  Mode Change: bundled:apparmor-mode
  Audit: bundled:apparmor-audit

[Configure] [Test All]
```

---

## Audio Player Compatibility

AppArmor monitoring doesn't play sounds directly:
- Monitoring feature using apparmor_status, aa-status
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS - N/A) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### AppArmor Monitor

```go
type AppArmorMonitor struct {
    config        *AppArmorMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    profileState  map[string]*AppArmorProfile
    lastEventTime map[string]time.Time
}

type AppArmorProfile struct {
    Path      string
    Name      string
    Status    string // "enforce", "complain", "disabled", "loaded", "unloaded"
    Mode      string
    LoadedAt  time.Time
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| apparmor_status | System Tool | Free | AppArmor status |
| aa-status | System Tool | Free | Profile status |

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
| macOS | Not Supported | AppArmor not available |
| Linux | Supported | Uses apparmor_status, aa-status |
