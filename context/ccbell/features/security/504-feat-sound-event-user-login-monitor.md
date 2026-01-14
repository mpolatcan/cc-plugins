# Feature: Sound Event User Login Monitor

Play sounds for user logins, SSH connections, and authentication events.

## Summary

Monitor user authentication events including SSH logins, local console access, and sudo usage, playing sounds for security-relevant login events.

## Motivation

- Security awareness
- Intrusion detection
- Access tracking
- Audit compliance
- Session monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Login Events

| Event | Description | Example |
|-------|-------------|---------|
| SSH Login | SSH connection | root from 1.2.3.4 |
| SSH Logout | SSH disconnected | session closed |
| Console Login | Local console login | tty1 login |
| Sudo Usage | sudo command run | sudo invoked |
| Failed Login | Failed attempt | authentication failure |
| New Session | New session created | new session |

### Configuration

```go
type UserLoginMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchUsers       []string          `json:"watch_users"` // "root", "*"
    WatchHosts       []string          `json:"watch_hosts"` // "1.2.3.4", "*"
    SoundOnLogin     bool              `json:"sound_on_login"`
    SoundOnLogout    bool              `json:"sound_on_logout"`
    SoundOnFail      bool              `json:"sound_on_fail"`
    SoundOnSudo      bool              `json:"sound_on_sudo"`
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:login status                # Show login activity
/ccbell:login add root              # Add user to watch
/ccbell:login sound login <sound>
/ccbell:login test                  # Test login sounds
```

### Output

```
$ ccbell:login status

=== Sound Event User Login Monitor ===

Status: Enabled
Watch Users: all
Watch Hosts: all

Recent Login Activity:

[1] alice (SSH)
    From: 192.168.1.100
    Time: Just now *** ACTIVE ***
    Session: pts/1
    Sound: bundled:login-alice *** ACTIVE ***

[2] bob (SSH)
    From: 10.0.0.50
    Time: 5 min ago
    Session: pts/2
    Sound: bundled:login-bob

[3] root (SUDO)
    Command: systemctl restart nginx
    Time: 10 min ago
    Sound: bundled:login-root-sudo

[4] unknown (FAILED)
    From: 203.0.113.25
    Time: 30 min ago *** FAILED ***
    Attempts: 3
    Sound: bundled:login-failed *** WARNING ***

Active Sessions:

[1] alice - pts/1 from 192.168.1.100 (5 min)
[2] bob - pts/2 from 10.0.0.50 (30 min)
[3] carol - tty1 (local) (2 hours)

Recent Events:

[1] alice: SSH Login (5 min ago)
       From 192.168.1.100
       Sound: bundled:login-ssh
  [2] root: Sudo Usage (10 min ago)
       systemctl restart nginx
       Sound: bundled:login-sudo
  [3] unknown: Failed Login (30 min ago)
       Failed password for user 'admin'
       Sound: bundled:login-fail
  [4] bob: SSH Login (30 min ago)
       From 10.0.0.50
       Sound: bundled:login-ssh

Login Statistics:
  Total Sessions: 3
  SSH: 2
  Local: 1
  Sudo Events: 5
  Failed Logins: 2

Sound Settings:
  Login: bundled:login-ssh
  Logout: bundled:login-logout
  Fail: bundled:login-fail
  Sudo: bundled:login-sudo

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

Login monitoring doesn't play sounds directly:
- Monitoring feature using who, last, journalctl
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### User Login Monitor

```go
type UserLoginMonitor struct {
    config        *UserLoginMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    loginState    map[string]*LoginSession
    lastEventTime time.Time
}

type LoginSession struct {
    User        string
    Type        string // "SSH", "local", "sudo"
    From        string // IP or tty
    LoginTime   time.Time
    SessionID   string
    Status      string // "active", "closed"
    FailedCount int
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | Current users |
| last | System Tool | Free | Login history |
| journalctl | System Tool | Free | Auth journal |
| lastlog | System Tool | Free | Last login times |

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
| macOS | Supported | Uses who, last, log show |
| Linux | Supported | Uses who, last, journalctl |
