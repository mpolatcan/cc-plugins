# Feature: Sound Event SELinux Monitor

Play sounds for SELinux policy violations, enforcement changes, and audit events.

## Summary

Monitor SELinux (Security-Enhanced Linux) for policy violations, mode changes, and audit events, playing sounds for SELinux events.

## Motivation

- Security monitoring
- Policy violation alerts
- Enforcement awareness
- Audit trail
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

### SELinux Events

| Event | Description | Example |
|-------|-------------|---------|
| Violation Detected | AVC denial | denied access |
| Mode Changed | Enforce <-> Permissive | mode changed |
| Policy Loaded | New policy | policy reloaded |
| Context Changed | Label changed | context modified |
| Audit Alert | Audit message | audit message |
| Deny Count | Rising denials | spike detected |

### Configuration

```go
type SELinuxMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    SoundOnViolation  bool              `json:"sound_on_violation"`
    SoundOnModeChange bool              `json:"sound_on_mode_change"`
    SoundOnPolicyLoad bool              `json:"sound_on_policy_load"`
    DenyThreshold     int               `json:"deny_threshold"` // per minute
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:selinux status              # Show SELinux status
/ccbell:selinux sound violation <sound>
/ccbell:selinux test                # Test SELinux sounds
```

### Output

```
$ ccbell:selinux status

=== Sound Event SELinux Monitor ===

Status: Enabled
Mode: Enforcing
Deny Threshold: 10/min

SELinux Status:

[1] System
    Mode: ENFORCING
    Policy: targeted
    Version: 33
    Denies Today: 45
    Sound: bundled:selinux-enforce

Recent Events:

[1] httpd: AVC Violation (5 min ago)
       denied { read } for pid=1234
       comm="httpd" path="/var/www/html"
       Sound: bundled:selinux-violation
  [2] sshd: Context Changed (1 hour ago)
       unconfined_u:system_r:sshd_t:s0-s0:c0.c1023
       Sound: bundled:selinux-context
  [3] System: Policy Loaded (2 hours ago)
       Policy version 33 loaded
       Sound: bundled:selinux-policy

SELinux Statistics:
  Total Denies: 45
  Denies/min: 0.5
  Top AVC: httpd (12), sshd (5)

Sound Settings:
  Violation: bundled:selinux-violation
  Mode Change: bundled:selinux-mode
  Policy Load: bundled:selinux-policy
  Context: bundled:selinux-context

[Configure] [Test All]
```

---

## Audio Player Compatibility

SELinux monitoring doesn't play sounds directly:
- Monitoring feature using ausearch, sestatus, semodule
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS - N/A) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### SELinux Monitor

```go
type SELinuxMonitor struct {
    config        *SELinuxMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    selinuxState  *SELinuxInfo
    lastEventTime map[string]time.Time
    denyCounts    map[string]int
}

type SELinuxInfo struct {
    Mode       string // "enforcing", "permissive", "disabled"
    Policy     string
    PolicyVer  string
    TotalDenies int
    DeniesPerMin float64
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ausearch | System Tool | Free | Audit search |
| sestatus | System Tool | Free | SELinux status |
| semodule | System Tool | Free | SELinux modules |

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
| macOS | Not Supported | SELinux not available |
| Linux | Supported | Uses ausearch, sestatus |
