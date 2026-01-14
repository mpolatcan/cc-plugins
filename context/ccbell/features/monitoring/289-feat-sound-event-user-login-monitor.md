# Feature: Sound Event User Login Monitor

Play sounds for user login and logout events.

## Summary

Monitor user logins, logouts, and session creation, playing sounds for authentication events.

## Motivation

- Security awareness
- Session tracking
- Login success/failure feedback
- Account activity alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### User Login Events

| Event | Description | Example |
|-------|-------------|---------|
| Login Successful | User authenticated | SSH login |
| Login Failed | Authentication error | Wrong password |
| Logout | Session ended | User logged out |
| Sudo Used | Elevated privilege | sudo command |

### Configuration

```go
type UserLoginMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    WatchUsers       []string          `json:"watch_users"`
    WatchTTYs        []string          `json:"watch_ttys"` // "/dev/pts/0", "tty1"
    SoundOnLogin     bool              `json:"sound_on_login"]
    SoundOnLogout    bool              `json:"sound_on_logout"]
    SoundOnFail      bool              `json:"sound_on_fail"]
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 5 default
}

type UserLoginEvent struct {
    UserName   string
    TTY        string
    FromIP     string
    EventType  string // "login", "logout", "failed"
    Timestamp  time.Time
}
```

### Commands

```bash
/ccbell:login status                 # Show login status
/ccbell:login add user               # Add user to watch
/ccbell:login remove user
/ccbell:login sound login <sound>
/ccbell:login sound fail <sound>
/ccbell:login test                   # Test login sounds
```

### Output

```
$ ccbell:login status

=== Sound Event User Login Monitor ===

Status: Enabled
Login Sounds: Yes
Fail Sounds: Yes

Current Sessions: 3

[1] user (pts/0)
    From: 192.168.1.100
    Login: 5 min ago
    Duration: 5 min
    Sound: bundled:stop

[2] admin (tty1)
    From: Local
    Login: 2 hours ago
    Duration: 2 hours
    Sound: bundled:stop

[3] root (pts/1)
    From: 192.168.1.100
    Login: 1 hour ago
    Duration: 1 hour
    Sound: bundled:login-root

Recent Events:
  [1] user: Login (5 min ago)
       SSH from 192.168.1.100
  [2] root: Login (1 hour ago)
       SSH from 192.168.1.100
  [3] admin: Failed Login (3 hours ago)
       From 10.0.0.50 (3 attempts)

Statistics Today:
  Successful Logins: 12
  Failed Logins: 2
  Logouts: 8

Sound Settings:
  Login: bundled:stop
  Logout: bundled:stop
  Failed: bundled:stop

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

User login monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### User Login Monitor

```go
type UserLoginMonitor struct {
    config          *UserLoginMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    activeSessions  map[string]*SessionInfo
}

type SessionInfo struct {
    UserName   string
    TTY        string
    FromIP     string
    LoginTime  time.Time
}
```

```go
func (m *UserLoginMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeSessions = make(map[string]*SessionInfo)
    go m.monitor()
}

func (m *UserLoginMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkLogins()
        case <-m.stopCh:
            return
        }
    }
}

func (m *UserLoginMonitor) checkLogins() {
    if runtime.GOOS == "darwin" {
        m.checkDarwinLogins()
    } else {
        m.checkLinuxLogins()
    }
}

func (m *UserLoginMonitor) checkDarwinLogins() {
    // Use who to get current logins
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        session := m.parseWhoLine(line)
        if session == nil {
            continue
        }

        m.evaluateSession(session)
    }

    // Check auth logs for failed attempts
    m.checkAuthLogs()
}

func (m *UserLoginMonitor) checkLinuxLogins() {
    // Use who and last commands
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if line == "" {
            continue
        }

        session := m.parseWhoLine(line)
        if session == nil {
            continue
        }

        m.evaluateSession(session)
    }

    // Check secure logs for failed logins
    m.checkAuthLogs()
}

func (m *UserLoginMonitor) parseWhoLine(line string) *SessionInfo {
    parts := strings.Fields(line)
    if len(parts) < 7 {
        return nil
    }

    user := parts[0]
    tty := parts[1]
    ip := parts[6]

    // Check user filter
    if len(m.config.WatchUsers) > 0 {
        found := false
        for _, watchUser := range m.config.WatchUsers {
            if user == watchUser {
                found = true
                break
            }
        }
        if !found {
            return nil
        }
    }

    return &SessionInfo{
        UserName: user,
        TTY:      tty,
        FromIP:   ip,
        LoginTime: time.Now(),
    }
}

func (m *UserLoginMonitor) checkAuthLogs() {
    if runtime.GOOS == "darwin" {
        cmd := exec.Command("log", "show", "--predicate",
            "eventMessage CONTAINS 'FAILED' && eventMessage CONTAINS 'authentication'",
            "--last", "5m")
        output, err := cmd.Output()
        if err == nil {
            m.parseAuthLogOutput(string(output))
        }
    } else {
        data, err := os.ReadFile("/var/log/auth.log")
        if err != nil {
            data, err = os.ReadFile("/var/log/secure")
        }
        if err == nil {
            m.parseAuthLog(string(data))
        }
    }
}

func (m *UserLoginMonitor) parseAuthLogOutput(output string) {
    lines := strings.Split(output, "\n")
    for _, line := range lines {
        if strings.Contains(line, "Failed") || strings.Contains(line, "FAILED") {
            event := &UserLoginEvent{
                EventType: "failed",
                Timestamp: time.Now(),
            }
            m.onLoginFailed(event)
        }
    }
}

func (m *UserLoginMonitor) parseAuthLog(log string) {
    lines := strings.Split(log, "\n")
    for _, line := range lines {
        if strings.Contains(line, "Failed") || strings.Contains(line, "authentication failure") {
            event := &UserLoginEvent{
                EventType: "failed",
                Timestamp: time.Now(),
            }
            m.onLoginFailed(event)
        }
    }
}

func (m *UserLoginMonitor) evaluateSession(session *SessionInfo) {
    key := fmt.Sprintf("%s-%s", session.UserName, session.TTY)

    if m.activeSessions[key] == nil {
        // New session
        m.activeSessions[key] = session
        m.onUserLoggedIn(session)
    }
}

func (m *UserLoginMonitor) onUserLoggedIn(session *SessionInfo) {
    if !m.config.SoundOnLogin {
        return
    }

    sound := m.config.Sounds["login"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *UserLoginMonitor) onUserLoggedOut(session *SessionInfo) {
    if !m.config.SoundOnLogout {
        return
    }

    key := fmt.Sprintf("%s-%s", session.UserName, session.TTY)
    delete(m.activeSessions, key)

    sound := m.config.Sounds["logout"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *UserLoginMonitor) onLoginFailed(event *UserLoginEvent) {
    if !m.config.SoundOnFail {
        return
    }

    sound := m.config.Sounds["failed"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| who | System Tool | Free | User sessions |
| log | System Tool | Free | macOS logging |
| /var/log/auth.log | File | Free | Linux auth logs |

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
| macOS | Supported | Uses who, log |
| Linux | Supported | Uses who, /var/log/auth.log |
| Windows | Not Supported | ccbell only supports macOS/Linux |
