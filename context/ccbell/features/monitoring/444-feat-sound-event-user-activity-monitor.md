# Feature: Sound Event User Activity Monitor

Play sounds for user logins, logout events, and session activity.

## Summary

Monitor user authentication events, login/logout activities, and session changes, playing sounds for user activity events.

## Motivation

- Login awareness
- Security monitoring
- Session tracking
- User presence detection
- Authentication failure alerts

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### User Activity Events

| Event | Description | Example |
|-------|-------------|---------|
| User Login | Successful login | user logged in |
| User Logout | Session ended | user logged out |
| Failed Login | Authentication failure | failed password |
| SSH Login | SSH connection | SSH session |
| Sudo Use | Privilege escalation | sudo executed |
| New Session | New session created | new terminal |

### Configuration

```go
type UserActivityMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchUsers     []string          `json:"watch_users"` // specific users or "*" for all
    WatchTTYs      []string          `json:"watch_ttys"` // tty devices
    SoundOnLogin   bool              `json:"sound_on_login"`
    SoundOnLogout  bool              `json:"sound_on_logout"`
    SoundOnFailed  bool              `json:"sound_on_failed"`
    SoundOnSudo    bool              `json:"sound_on_sudo"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 10 default
}
```

### Commands

```bash
/ccbell:user status                 # Show user activity status
/ccbell:user add root               # Add user to watch
/ccbell:user sound login <sound>
/ccbell:user test                   # Test user sounds
```

### Output

```
$ ccbell:user status

=== Sound Event User Activity Monitor ===

Status: Enabled
Watch Users: all
Watch TTYs: all

Current Sessions:

[1] mutlu (tty1)
    Login: Jan 14 08:00
    Idle: 2h 15m
    Sound: bundled:user-login

[2] root (tty2)
    Login: Jan 14 09:30
    Idle: 45m
    Sound: bundled:user-login

Recent Activity:

[1] mutlu: Logout (10 min ago)
       tty1 session ended
       Sound: bundled:user-logout
  [2] root: Failed Login (30 min ago)
       tty2 - 3 failed attempts
       Sound: bundled:user-failed
  [3] mutlu: Login (1 hour ago)
       tty1 session started
       Sound: bundled:user-login

Activity Statistics:
  Logins Today: 8
  Logouts Today: 5
  Failed Logins: 2

Sound Settings:
  Login: bundled:user-login
  Logout: bundled:user-logout
  Failed: bundled:user-failed
  Sudo: bundled:user-sudo

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

User activity monitoring doesn't play sounds directly:
- Monitoring feature using who, last
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### User Activity Monitor

```go
type UserActivityMonitor struct {
    config        *UserActivityMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    activeUsers   map[string]*SessionInfo
    lastEventTime map[string]time.Time
}

type SessionInfo struct {
    User      string
    TTY       string
    LoginTime time.Time
    IP        string
    From      string
}

func (m *UserActivityMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.activeUsers = make(map[string]*SessionInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *UserActivityMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotUserState()

    for {
        select {
        case <-ticker.C:
            m.checkUserState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *UserActivityMonitor) snapshotUserState() {
    sessions := m.getActiveSessions()
    for _, session := range sessions {
        key := m.sessionKey(session)
        m.activeUsers[key] = session
    }
}

func (m *UserActivityMonitor) getActiveSessions() []*SessionInfo {
    var sessions []*SessionInfo

    cmd := exec.Command("who", "-u")
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

        session := m.parseWhoOutput(line)
        if session != nil {
            sessions = append(sessions, session)
        }
    }

    return sessions
}

func (m *UserActivityMonitor) parseWhoOutput(line string) *SessionInfo {
    fields := strings.Fields(line)
    if len(fields) < 3 {
        return nil
    }

    session := &SessionInfo{
        User:      fields[0],
        TTY:       fields[1],
        LoginTime: m.parseLoginTime(fields[2] + " " + fields[3]),
    }

    if len(fields) > 5 {
        session.From = fields[5]
    }

    return session
}

func (m *UserActivityMonitor) parseLoginTime(timeStr string) time.Time {
    t, err := time.Parse("2006-01-02 15:04", timeStr)
    if err != nil {
        return time.Now()
    }
    return t
}

func (m *UserActivityMonitor) sessionKey(session *SessionInfo) string {
    return fmt.Sprintf("%s:%s", session.User, session.TTY)
}

func (m *UserActivityMonitor) checkUserState() {
    currentSessions := m.getActiveSessions()
    currentMap := make(map[string]*SessionInfo)

    for _, session := range currentSessions {
        key := m.sessionKey(session)
        currentMap[key] = session

        // Check for new sessions
        if m.activeUsers[key] == nil {
            if m.shouldAlert(key+"login", 1*time.Minute) {
                m.onUserLogin(session)
            }
        }
    }

    // Check for ended sessions
    for key, oldSession := range m.activeUsers {
        if currentMap[key] == nil {
            if m.shouldAlert(key+"logout", 1*time.Minute) {
                m.onUserLogout(oldSession)
            }
        }
    }

    m.activeUsers = currentMap
}

func (m *UserActivityMonitor) onUserLogin(session *SessionInfo) {
    // Check if user should be watched
    if !m.shouldWatchUser(session.User) {
        return
    }

    if m.config.SoundOnLogin {
        sound := m.config.Sounds["login"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserActivityMonitor) onUserLogout(session *SessionInfo) {
    if !m.shouldWatchUser(session.User) {
        return
    }

    if m.config.SoundOnLogout {
        sound := m.config.Sounds["logout"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *UserActivityMonitor) shouldWatchUser(user string) {
    for _, watchedUser := range m.config.WatchUsers {
        if watchedUser == "*" || watchedUser == user {
            return true
        }
    }
    return false
}

func (m *UserActivityMonitor) onFailedLogin(tty string) {
    key := fmt.Sprintf("failed:%s", tty)
    if m.shouldAlert(key, 30*time.Second) {
        if m.config.SoundOnFailed {
            sound := m.config.Sounds["failed"]
            if sound != "" {
                m.player.Play(sound, 0.5)
            }
        }
    }
}

func (m *UserActivityMonitor) shouldAlert(key string, interval time.Duration) bool {
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
| who | System Tool | Free | User session listing |
| last | System Tool | Free | Login history |
| w | System Tool | Free | User activity |

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
| macOS | Supported | Uses who, last |
| Linux | Supported | Uses who, last, w |
