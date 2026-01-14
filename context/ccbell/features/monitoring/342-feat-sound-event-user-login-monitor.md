# Feature: Sound Event User Login Monitor

Play sounds for user login/logout events and session changes.

## Summary

Monitor user logins, logouts, SSH connections, and session changes, playing sounds for authentication events.

## Motivation

- Security awareness
- Session tracking
- SSH connection alerts
- Failed login detection
- User presence awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### User Login Events

| Event | Description | Example |
|-------|-------------|---------|
| User Logged In | Successful login | user logged in via tty1 |
| User Logged Out | Session ended | user logged out |
| SSH Connected | SSH connection | user@192.168.1.100 connected |
| SSH Disconnected | SSH disconnected | session closed |
| Failed Login | Failed attempt | Invalid password 3 times |
| Sudo Usage | Sudo command executed | sudo invoked |
| Session Locked | Screen locked | Session locked |
| Session Unlocked | Screen unlocked | Session unlocked |

### Configuration

```go
type UserLoginMonitorConfig struct {
    Enabled            bool              `json:"enabled"`
    WatchUsers         []string          `json:"watch_users"` // "root", "admin", "*"
    WatchTTYs          []string          `json:"watch_ttys"` // "tty", "pts", "ssh"
    SoundOnLogin       bool              `json:"sound_on_login"`
    SoundOnLogout      bool              `json:"sound_on_logout"`
    SoundOnSSH         bool              `json:"sound_on_ssh"`
    SoundOnFailed      bool              `json:"sound_on_failed"`
    Sounds             map[string]string `json:"sounds"`
    PollInterval       int               `json:"poll_interval_sec"` // 10 default
}

type UserLoginEvent struct {
    User      string
    TTY       string
    IP        string
    PID       int
    SessionID int
    EventType string // "login", "logout", "ssh", "failed", "sudo"
}
```

### Commands

```bash
/ccbell:login status                  # Show login status
/ccbell:login add root                # Add user to watch
/ccbell:login remove root
/ccbell:login sound login <sound>
/ccbell:login sound ssh <sound>
/ccbell:login sound failed <sound>
/ccbell:login test                    # Test login sounds
```

### Output

```
$ ccbell:login status

=== Sound Event User Login Monitor ===

Status: Enabled
Login Sounds: Yes
SSH Sounds: Yes
Failed Login Sounds: Yes

Watched Users: 2
Watched TTYs: 2

Current Sessions:

[1] root
    TTY: tty1
    Since: 2 days ago
    Sound: bundled:login-root

[2] admin
    TTY: pts/0 (SSH)
    IP: 192.168.1.100
    Since: 5 hours ago
    Sound: bundled:login-ssh

[3] admin
    TTY: pts/1 (SSH)
    IP: 10.0.0.50
    Since: 1 hour ago
    Sound: bundled:login-ssh

Recent Events:
  [1] admin: SSH Connected (5 min ago)
       192.168.1.100 (pts/0)
  [2] root: Sudo Usage (10 min ago)
       apt update && apt upgrade
  [3] admin: Failed Login (1 hour ago)
       Invalid password 3 attempts

Login Statistics:
  Logins today: 15
  SSH connections: 12
  Failed logins: 3

Sound Settings:
  Login: bundled:login-success
  Logout: bundled:login-logout
  SSH: bundled:login-ssh
  Failed: bundled:login-fail

[Configure] [Add User] [Test All]
```

---

## Audio Player Compatibility

User login monitoring doesn't play sounds directly:
- Monitoring feature using who/last/ac commands
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
    sessionState    map[int]*SessionInfo
    lastEventTime   map[string]time.Time
}

type SessionInfo struct {
    User      string
    TTY       string
    IP        string
    PID       int
    LoginTime time.Time
}

func (m *UserLoginMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.sessionState = make(map[int]*SessionInfo)
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
    if runtime.GOOS == "darwin" {
        m.snapshotDarwinSessions()
    } else {
        m.snapshotLinuxSessions()
    }
}

func (m *UserLoginMonitor) snapshotLinuxSessions() {
    cmd := exec.Command("who")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))
}

func (m *UserLoginMonitor) parseWhoOutput(output string) {
    lines := strings.Split(output, "\n")
    currentSessions := make(map[int]*SessionInfo)

    for _, line := range lines {
        if line == "" {
            continue
        }

        parts := strings.Fields(line)
        if len(parts) < 4 {
            continue
        }

        user := parts[0]
        tty := parts[1]
        date := parts[2]
        timeStr := parts[3]

        if !m.shouldWatchUser(user) || !m.shouldWatchTTY(tty) {
            continue
        }

        // Parse IP from SSH connections
        ip := ""
        if strings.Contains(tty, "pts") {
            ipRe := regexp.MustCompile(`\(([0-9.]+)\)`)
            match := ipRe.FindStringSubmatch(line)
            if match != nil {
                ip = match[1]
            }
        }

        // Get session PID from /proc
        pid := m.getSessionPID(tty)

        sessionKey := m.getSessionKey(user, tty, pid)

        info := &SessionInfo{
            User:      user,
            TTY:       tty,
            IP:        ip,
            PID:       pid,
            LoginTime: m.parseDateTime(date, timeStr),
        }

        currentSessions[sessionKey] = info

        lastInfo := m.sessionState[sessionKey]
        if lastInfo == nil {
            m.sessionState[sessionKey] = info
            if strings.HasPrefix(tty, "pts") || strings.Contains(tty, "ssh") {
                m.onSSHConnected(user, tty, ip)
            } else {
                m.onUserLoggedIn(user, tty)
            }
        }
    }

    // Check for logged out sessions
    for key, lastInfo := range m.sessionState {
        if _, exists := currentSessions[key]; !exists {
            delete(m.sessionState, key)
            m.onUserLoggedOut(lastInfo)
        }
    }
}

func (m *UserLoginMonitor) snapshotDarwinSessions() {
    cmd := exec.Command("who", "-u")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    m.parseWhoOutput(string(output))
}

func (m *UserLoginMonitor) getSessionPID(tty string) int {
    // Try to get PID from /proc
    if runtime.GOOS != "linux" {
        return 0
    }

    ttyNum := strings.TrimPrefix(tty, "/dev/")
    pidPath := filepath.Join("/proc", "stat")
    data, err := os.ReadFile(pidPath)
    if err != nil {
        return 0
    }

    // This is a simplified approach
    return 0
}

func (m *UserLoginMonitor) getSessionKey(user, tty string, pid int) int {
    key := fmt.Sprintf("%s:%s:%d", user, tty, pid)
    hash := 0
    for _, c := range key {
        hash = hash*31 + int(c)
    }
    return hash
}

func (m *UserLoginMonitor) parseDateTime(date, timeStr string) time.Time {
    // Parse "2024-01-15" and "10:30"
    layout := "2006-01-02 15:04"
    combined := fmt.Sprintf("%s %s", date, timeStr)
    t, _ := time.Parse(layout, combined)
    return t
}

func (m *UserLoginMonitor) shouldWatchUser(user string) bool {
    if len(m.config.WatchUsers) == 0 {
        return true
    }

    for _, u := range m.config.WatchUsers {
        if u == "*" || u == user {
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
        if strings.HasPrefix(tty, t) {
            return true
        }
    }

    return false
}

func (m *UserLoginMonitor) onUserLoggedIn(user, tty string) {
    if !m.config.SoundOnLogin {
        return
    }

    key := fmt.Sprintf("login:%s", user)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["login"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserLoginMonitor) onUserLoggedOut(info *SessionInfo) {
    if !m.config.SoundOnLogout {
        return
    }

    key := fmt.Sprintf("logout:%s", info.User)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["logout"]
        if sound != "" {
            m.player.Play(sound, 0.3)
        }
    }
}

func (m *UserLoginMonitor) onSSHConnected(user, tty, ip string) {
    if !m.config.SoundOnSSH {
        return
    }

    key := fmt.Sprintf("ssh:%s:%s", user, ip)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["ssh"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *UserLoginMonitor) onFailedLogin(user, ip string) {
    if !m.config.SoundOnFailed {
        return
    }

    key := fmt.Sprintf("failed:%s:%s", user, ip)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["failed"]
        if sound != "" {
            m.player.Play(sound, 0.6)
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
| who | System Tool | Free | Session listing |
| last | System Tool | Free | Login history |
| /proc/*/fd/* | Filesystem | Free | TTY info |

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
| macOS | Supported | Uses who |
| Linux | Supported | Uses who, /proc |
