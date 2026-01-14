# Feature: Sound Event User Login Monitor

Play sounds for user logins, logouts, SSH connections, and session changes.

## Summary

Monitor user authentication events including logins, logouts, SSH connections, and session activity, playing sounds for login events.

## Motivation

- Security awareness
- Session tracking
- SSH connection alerts
- User presence detection
- Audit trail feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### User Login Events

| Event | Description | Example |
|-------|-------------|---------|
| Local Login | User logged in | console |
| SSH Login | SSH connection | user@host |
| SSH Logout | Session ended | disconnected |
| Sudo Usage | Elevated privileges | sudo command |
| Failed Login | Auth failed | wrong password |
| Session Timeout | Auto logout | expired |

### Configuration

```go
type UserLoginMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchUsers        []string          `json:"watch_users"` // "root", "*"
    WatchTTYs         []string          `json:"watch_ttys"` // "tty1", "pts/0", "*"
    SoundOnLogin      bool              `json:"sound_on_login"`
    SoundOnLogout     bool              `json:"sound_on_logout"`
    SoundOnSSH        bool              `json:"sound_on_ssh"`
    SoundOnFailed     bool              `json:"sound_on_failed"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 30 default
}
```

### Commands

```bash
/ccbell:login status                 # Show login status
/ccbell:login add root               # Add user to watch
/ccbell:login remove root
/ccbell:login sound login <sound>
/ccbell:login sound ssh <sound>
/ccbell:login test                   # Test login sounds
```

### Output

```
$ ccbell:login status

=== Sound Event User Login Monitor ===

Status: Enabled
Login Sounds: Yes
SSH Sounds: Yes
Logout Sounds: Yes

Watched Users: *
Watched TTYs: *

Current Sessions:

[1] root (tty1)
    Status: ACTIVE
    Login: Jan 14, 2026 08:00:00
    TTY: tty1
    From: console
    Idle: 0 sec
    Sound: bundled:login-root

[2] user (pts/0)
    Status: ACTIVE
    Login: Jan 14, 2026 09:15:00
    TTY: pts/0
    From: 192.168.1.100 (SSH)
    Idle: 5 min
    Sound: bundled:login-user

[3] user (pts/1)
    Status: ACTIVE
    Login: Jan 14, 2026 10:30:00
    TTY: pts/1
    From: 192.168.1.101 (SSH)
    Idle: 0 sec
    Sound: bundled:login-user

Recent Login Events:
  [1] user: SSH Login (1 hour ago)
       192.168.1.100
       Sound: bundled:login-ssh
  [2] root: Local Login (2 hours ago)
       tty1 console
       Sound: bundled:login-local
  [3] user: SSH Logout (3 hours ago)
       Session ended

Login Statistics:
  Logins Today: 8
  SSH Logins: 6
  Local Logins: 2
  Failed Attempts: 0

Sound Settings:
  Login: bundled:login-local
  SSH: bundled:login-ssh
  Logout: bundled:login-logout
  Failed: bundled:login-failed

[Configure] [Test All]
```

---

## Audio Player Compatibility

Login monitoring doesn't play sounds directly:
- Monitoring feature using who/w/last
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
    sessionState    map[string]*SessionInfo
    lastEventTime   map[string]time.Time
}

type SessionInfo struct {
    User       string
    TTY        string
    From       string
    LoginTime  time.Time
    Status     string // "active", "logged_out"
    IsSSH      bool
    PID        int
}

func (m *UserLoginMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sessionState = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *UserLoginMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotSessionState()

    for {
        select {
        case <-ticker.C:
            m.checkSessionState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *UserLoginMonitor) snapshotSessionState() {
    m.checkSessionState()
}

func (m *UserLoginMonitor) checkSessionState() {
    sessions := m.listSessions()

    // Build current session map
    currentSessions := make(map[string]*SessionInfo)

    for _, session := range sessions {
        if !m.shouldWatchUser(session.User) {
            continue
        }
        if !m.shouldWatchTTY(session.TTY) {
            continue
        }

        key := m.sessionKey(session)
        currentSessions[key] = session

        // Check for new sessions
        if _, exists := m.sessionState[key]; !exists {
            m.onUserLogin(session)
        }
    }

    // Check for ended sessions
    for key, lastSession := range m.sessionState {
        if _, exists := currentSessions[key]; !exists {
            m.onUserLogout(lastSession)
        }
    }

    m.sessionState = currentSessions
}

func (m *UserLoginMonitor) listSessions() []*SessionInfo {
    var sessions []*SessionInfo

    // Use 'who' command
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return sessions
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 3 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        loginTime := parts[2] + " " + parts[3]

        // Check if from remote (SSH)
        from := "local"
        isSSH := false

        // Get more info about the connection
        cmd := exec.Command("who", "-la")
        laOutput, _ := cmd.Output()
        laLines := strings.Split(string(laOutput), "\n")

        for _, laLine := range laLines {
            if strings.Contains(laLine, user) && strings.Contains(laLine, tty) {
                if strings.Contains(laLine, "pts/") || strings.Contains(laLine, "192.168.") ||
                   strings.Contains(laLine, "10.") || strings.Contains(laLine, "remote") {
                    from = "SSH"
                    isSSH = true
                }
                break
            }
        }

        session := &SessionInfo{
            User:   user,
            TTY:    tty,
            From:   from,
            IsSSH:  isSSH,
            Status: "active",
        }

        // Parse login time
        session.LoginTime, _ = time.Parse("2006-01-02 15:04", loginTime)

        sessions = append(sessions, session)
    }

    return sessions
}

func (m *UserLoginMonitor) listLinuxSessions() []*SessionInfo {
    var sessions []*SessionInfo

    // Use 'w' command for more detail
    cmd := exec.Command("w", "-h")
    output, err := cmd.Output()
    if err != nil {
        return sessions
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 5 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        from := parts[2]
        loginTime := parts[3]

        isSSH := false
        if strings.Contains(from, ":") || strings.Contains(from, "192.168.") ||
           strings.Contains(from, "10.") || strings.Contains(from, ".") {
            isSSH = true
            from = "SSH"
        }

        session := &SessionInfo{
            User:  user,
            TTY:   tty,
            From:  from,
            IsSSH: isSSH,
        }

        // Parse login time
        session.LoginTime, _ = time.Parse("2006-01-02 15:04", loginTime)

        sessions = append(sessions, session)
    }

    return sessions
}

func (m *UserLoginMonitor) sessionKey(session *SessionInfo) string {
    return fmt.Sprintf("%s:%s", session.User, session.TTY)
}

func (m *UserLoginMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == "*" || user == u {
            return true
        }
    }

    return false
}

func (m *UserLoginMonitor) shouldWatchTTY(tty string) bool {
    if len(m.config.WatchTTYs) == 0 {
        return true
    }

    for _, t := range m.config.WatchTTYs {
        if t == "*" || tty == t {
            return true
        }
    }

    return false
}

func (m *UserLoginMonitor) onUserLogin(session *SessionInfo) {
    if session.IsSSH {
        if m.config.SoundOnSSH {
            m.onSSHLogin(session)
        }
    } else {
        if m.config.SoundOnLogin {
            m.onLocalLogin(session)
        }
    }
}

func (m *UserLoginMonitor) onUserLogout(session *SessionInfo) {
    if m.config.SoundOnLogout {
        m.onSessionLogout(session)
    }
}

func (m *UserLoginMonitor) onSSHLogin(session *SessionInfo) {
    key := fmt.Sprintf("ssh:%s", session.User)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["ssh"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserLoginMonitor) onLocalLogin(session *SessionInfo) {
    key := fmt.Sprintf("login:%s", session.User)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["login"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserLoginMonitor) onSessionLogout(session *SessionInfo) {
    key := fmt.Sprintf("logout:%s:%s", session.User, session.TTY)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["logout"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *UserLoginMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| who | System Tool | Free | User listing |
| w | System Tool | Free | Who with details |

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
| macOS | Supported | Uses who, w |
| Linux | Supported | Uses who, w |
